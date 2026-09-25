import Foundation
import Testing
@testable import OlliChef

struct AssistantJSONExtractorTests {
    @Test func extractsCleanJSONObject() {
        let text = #"{"type": "JSON", "meal_plan": {"days": []}}"#
        let parsed = AssistantJSONExtractor.tryExtractJSON(from: text)
        #expect(parsed?["type"] as? String == "JSON")
    }

    @Test func extractsJSONWithPreambleText() {
        // The model sometimes ignores the instruction not to add commentary.
        let text = #"Sure, here's your plan! {"type": "JSON", "meal_plan": {"days": []}} Let me know if you'd like changes."#
        let parsed = AssistantJSONExtractor.tryExtractJSON(from: text)
        #expect(parsed?["type"] as? String == "JSON")
    }

    @Test func toleratesBracesInsideStringValues() {
        // A naive first-'{'-to-last-'}' scan would break on this; the real extractor
        // tracks string state so a brace inside a quoted value doesn't confuse depth.
        let text = #"{"type": "JSON", "notes": "use a {mixing} bowl", "meal_plan": {"days": []}}"#
        let parsed = AssistantJSONExtractor.tryExtractJSON(from: text)
        #expect(parsed?["notes"] as? String == "use a {mixing} bowl")
    }

    @Test func toleratesEscapedQuotesInsideStrings() {
        let text = #"{"type": "JSON", "notes": "the \"best\" dinner", "meal_plan": {"days": []}}"#
        let parsed = AssistantJSONExtractor.tryExtractJSON(from: text)
        #expect(parsed?["notes"] as? String == "the \"best\" dinner")
    }

    @Test func returnsNilForPlainTextWithNoJSON() {
        let text = "Sure! What would you like to eat this week?"
        #expect(AssistantJSONExtractor.tryExtractJSON(from: text) == nil)
    }

    @Test func returnsNilForEmptyString() {
        #expect(AssistantJSONExtractor.tryExtractJSON(from: "") == nil)
    }

    @Test func skipsAnUnbalancedCandidateAndFindsALaterValidOne() {
        // The leading stray "{" never finds a matching close before the string ends, so
        // the scan starting there can't reach depth 0 and falls through to the next "{".
        let text = #"{ {"type": "JSON", "meal_plan": {"days": []}}"#
        let parsed = AssistantJSONExtractor.tryExtractJSON(from: text)
        #expect(parsed?["type"] as? String == "JSON")
    }

    @Test func isStructuredMealPlanTrueForWellFormedPayload() {
        let parsed: [String: Any] = ["type": "JSON", "meal_plan": ["days": [Any]()]]
        #expect(AssistantJSONExtractor.isStructuredMealPlan(parsed))
    }

    @Test func isStructuredMealPlanFalseWhenTypeIsNotJSON() {
        let parsed: [String: Any] = ["type": "text", "meal_plan": ["days": [Any]()]]
        #expect(!AssistantJSONExtractor.isStructuredMealPlan(parsed))
    }

    @Test func isStructuredMealPlanFalseWhenDaysMissing() {
        let parsed: [String: Any] = ["type": "JSON", "meal_plan": ["notes": "no days key"]]
        #expect(!AssistantJSONExtractor.isStructuredMealPlan(parsed))
    }

    @Test func isStructuredMealPlanFalseWhenMealPlanMissing() {
        let parsed: [String: Any] = ["type": "JSON"]
        #expect(!AssistantJSONExtractor.isStructuredMealPlan(parsed))
    }

    @Test func extractQuestionTextReturnsTextForQuestionEnvelope() {
        let parsed: [String: Any] = ["type": "question", "question_text": "What's your family size?", "meal_plan": NSNull()]
        #expect(AssistantJSONExtractor.extractQuestionText(from: parsed) == "What's your family size?")
    }

    @Test func extractQuestionTextNilForMealPlanEnvelope() {
        let parsed: [String: Any] = ["type": "JSON", "question_text": NSNull(), "meal_plan": ["days": [Any]()]]
        #expect(AssistantJSONExtractor.extractQuestionText(from: parsed) == nil)
    }

    @Test func extractQuestionTextNilWhenQuestionTextMissing() {
        let parsed: [String: Any] = ["type": "question"]
        #expect(AssistantJSONExtractor.extractQuestionText(from: parsed) == nil)
    }
}
