import Foundation

/// Ported from chatService.ts's tryExtractJsonFromText/isStructuredMealPlan: scans
/// for the first balanced {...} or [...] block in assistant text, tolerating preamble
/// text the model sometimes adds despite instructions not to.
enum AssistantJSONExtractor {
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

    private static func attemptParse(_ candidate: String) -> [String: Any]? {
        guard let data = candidate.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
