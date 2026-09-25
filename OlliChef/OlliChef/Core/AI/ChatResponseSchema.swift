import Foundation

/// The Responses API's Structured Outputs feature (`text.format`, a JSON Schema)
/// constrains the model's token sampling so every response is *guaranteed* to be
/// valid JSON matching this exact shape — replacing the old approach of describing
/// the format in prose and hoping the model complies. That old approach produced two
/// confirmed live failures `AssistantJSONExtractor` had to patch with regex:
/// a dropped "unit" key partway through a long ingredient list, and a spelled-out
/// number ("fifty") instead of a numeral. Both become structurally impossible once
/// the schema requires every listed property (nullable ones included) and the exact
/// type for each.
///
/// `type` distinguishes a clarifying question from a finished plan, and "JSON" is
/// kept (rather than e.g. "plan") as the plan discriminator specifically because it
/// matches `AssistantJSONExtractor.isStructuredMealPlan`'s existing check — no
/// changes needed there, or in `MealPlanParser.parse`, which already reads a
/// `[String: Any]` with a top-level "meal_plan" key exactly like this envelope.
///
/// Every property in a strict-mode schema must appear in that object's `required`
/// array, including ones that are conceptually optional — those are represented as
/// nullable types (e.g. `["string", "null"]`) instead of being omitted, and
/// `additionalProperties: false` is required on every object, recursively.
enum ChatResponseSchema {
    private static let ingredient: [String: Any] = [
        "type": "object",
        "properties": [
            "name": ["type": "string"],
            "category": ["type": "string"],
            // Some ingredients (e.g. "salt to taste") have no meaningful amount/unit —
            // nullable rather than omitted, per strict mode's all-properties-required rule.
            "amount": ["type": ["number", "null"]],
            "unit": ["type": ["string", "null"]],
        ],
        "required": ["name", "category", "amount", "unit"],
        "additionalProperties": false,
    ]

    private static let meal: [String: Any] = [
        "type": "object",
        "properties": [
            "type": ["type": "string"],
            "name": ["type": "string"],
            "protein_g": ["type": "number"],
            "fat_g": ["type": "number"],
            "carbs_g": ["type": "number"],
            "ingredients": ["type": "array", "items": ingredient],
        ],
        "required": ["type", "name", "protein_g", "fat_g", "carbs_g", "ingredients"],
        "additionalProperties": false,
    ]

    private static let day: [String: Any] = [
        "type": "object",
        "properties": [
            "day": ["type": "string"],
            "date": ["type": "string"],
            "meals": ["type": "array", "items": meal],
        ],
        "required": ["day", "date", "meals"],
        "additionalProperties": false,
    ]

    /// Nullable object: absent (null) on a "question" response, populated on a "JSON"
    /// (plan) response — `type: ["object", "null"]` with `properties`/`required`
    /// alongside is the documented pattern for a nullable object in strict mode.
    private static let mealPlan: [String: Any] = [
        "type": ["object", "null"],
        "properties": [
            "week": ["type": "string"],
            "userHas": ["type": "array", "items": ["type": "string"]],
            "notes": ["type": ["string", "null"]],
            "days": ["type": "array", "items": day],
        ],
        "required": ["week", "userHas", "notes", "days"],
        "additionalProperties": false,
    ]

    /// Passed as `text.format` in ChatService's `/responses` request body.
    static let responseFormat: [String: Any] = [
        "type": "json_schema",
        "name": "chat_response",
        "strict": true,
        "schema": [
            "type": "object",
            "properties": [
                "type": ["type": "string", "enum": ["question", "JSON"]],
                "question_text": ["type": ["string", "null"]],
                "meal_plan": mealPlan,
            ],
            "required": ["type", "question_text", "meal_plan"],
            "additionalProperties": false,
        ],
    ]
}
