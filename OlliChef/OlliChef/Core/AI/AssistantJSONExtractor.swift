import Foundation

/// Ported from chatService.ts's tryExtractJsonFromText/isStructuredMealPlan: scans
/// for the first balanced {...} or [...] block in assistant text, tolerating preamble
/// text the model sometimes adds despite instructions not to.
nonisolated enum AssistantJSONExtractor {
    static func tryExtractJSON(from text: String) -> [String: Any]? {
        guard !text.isEmpty else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let parsed = attemptParse(trimmed) {
                return parsed
            }
        }

        let chars = Array(text)
        var starts: [Int] = []
        for (i, ch) in chars.enumerated() where ch == "{" || ch == "[" {
            starts.append(i)
        }

        for startIdx in starts {
            let open = chars[startIdx]
            let close: Character = open == "{" ? "}" : "]"
            var depth = 0
            var inString = false
            var escape = false

            var i = startIdx
            while i < chars.count {
                let ch = chars[i]
                if inString {
                    if escape {
                        escape = false
                    } else if ch == "\\" {
                        escape = true
                    } else if ch == "\"" {
                        inString = false
                    }
                    i += 1
                    continue
                }

                if ch == "\"" {
                    inString = true
                } else if ch == open {
                    depth += 1
                } else if ch == close {
                    depth -= 1
                    if depth == 0 {
                        let candidate = String(chars[startIdx...i])
                        if let parsed = attemptParse(candidate) {
                            return parsed
                        }
                        break
                    }
                }
                i += 1
            }
        }

        return nil
    }

    static func isStructuredMealPlan(_ parsed: [String: Any]) -> Bool {
        guard (parsed["type"] as? String) == "JSON",
              let mealPlan = parsed["meal_plan"] as? [String: Any],
              mealPlan["days"] is [Any] else {
            return false
        }
        return true
    }

    /// The model occasionally drops the "unit" key partway through a long ingredient
    /// list — e.g. `"amount": 1, "can"` instead of `"amount": 1, "unit": "can"` —
    /// which is invalid JSON (a bare value with no key) and fails parsing outright.
    /// Confirmed live: prompt instructions reduce this but don't eliminate it on long
    /// responses, so repair the one specific shape before parsing rather than losing
    /// the whole meal plan to one dropped key several ingredients deep.
    private static func repairMissingUnitKey(_ text: String) -> String {
        let pattern = #""amount"(\s*:\s*-?\d+(?:\.\d+)?)\s*,\s*"([^"]+)"(\s*\})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: #""amount"$1, "unit": "$2"$3"#
        )
    }

    /// The model is explicitly told to use plain numerals for protein_g/fat_g/carbs_g
    /// and mostly does, but occasionally still spells one out on a long response (e.g.
    /// `"carbs_g": fifty`) — also invalid JSON, since a bare identifier isn't a valid
    /// value. Same repair strategy as `repairMissingUnitKey`: fix the one specific shape
    /// before parsing rather than losing the whole meal plan to one word deep in it.
    /// Matches are replaced back-to-front so each replacement's own offset shift never
    /// invalidates the ranges of matches still waiting to be applied.
    private static func repairSpelledOutNumbers(_ text: String) -> String {
        let pattern = #""(protein_g|fat_g|carbs_g)"\s*:\s*([A-Za-z][A-Za-z\s-]*[A-Za-z])\s*([,}])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let range = NSRange(result.startIndex..., in: result)
        let matches = regex.matches(in: result, range: range)

        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let keyRange = Range(match.range(at: 1), in: result),
                  let wordRange = Range(match.range(at: 2), in: result),
                  let terminatorRange = Range(match.range(at: 3), in: result),
                  let number = NumberWordParser.parse(String(result[wordRange])) else { continue }
            let key = result[keyRange]
            let terminator = result[terminatorRange]
            result.replaceSubrange(fullRange, with: "\"\(key)\": \(number)\(terminator)")
        }
        return result
    }

    private static func attemptParse(_ candidate: String) -> [String: Any]? {
        let repaired = repairSpelledOutNumbers(repairMissingUnitKey(candidate))
        guard let data = repaired.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

/// Parses simple English number words up to a few hundred — enough range for a
/// per-meal gram count, not a general-purpose word-to-number parser. Returns nil for
/// anything it doesn't recognize, so an unrecognized phrase leaves the JSON untouched
/// and parsing fails safely rather than guessing at a value.
private enum NumberWordParser {
    private static let ones: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    static func parse(_ phrase: String) -> Int? {
        let normalized = phrase
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: " and ", with: " ")
        let words = normalized.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }

        var current = 0
        for word in words {
            if let value = ones[word] {
                current += value
            } else if let value = tens[word] {
                current += value
            } else if word == "hundred" {
                guard current > 0 else { return nil }
                current *= 100
            } else {
                return nil
            }
        }
        return current
    }
}
