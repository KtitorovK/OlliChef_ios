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

    private static func attemptParse(_ candidate: String) -> [String: Any]? {
        guard let data = repairMissingUnitKey(candidate).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
