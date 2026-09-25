import FirebaseRemoteConfig
import Foundation

/// Ported verbatim from remoteConfigService.ts's DEFAULT_PROMPTS. These are an
/// emergency-only fallback, not a routine code path: every AI feature depends on
/// network access anyway (they all call OpenAI), so there is no real "offline mode"
/// worth silently degrading into with a possibly-stale local prompt. Chat and Recipe
/// require a genuine Remote Config fetch before they'll run at all — see
/// `PromptManager.requireRemote(_:)` — and surface the same offline message as any
/// other network failure instead. Grocery's AI step is the one exception: it's an
/// optional polish step that already falls back to a deterministic, non-AI list on
/// any failure, so it stays lenient and may use these defaults rather than fail the
/// whole grocery-list feature.
nonisolated enum DefaultPrompts {
    static let dynamicPrompt = """
    You are a master chef specializing in crafting weekly meal plans for families, with a flair for humor and a love for keeping things lighthearted. Today is {{CURRENT_DATE}}.

    Always:
    - Use this current date ({{CURRENT_DATE}}) to plan meals, starting from today unless the user specifies otherwise.
    - Format dates as "Day, YYYY-MM-DD" (e.g., Monday, 2025-01-27). Never use past dates or wrong months.
    - If the user says "next week", generate a plan starting from the next Monday following today.

    Your primary goal is to provide a complete weekly menu with diverse, balanced, and family-friendly meals covering the full week. Greet users with a joke and gather key details one question at a time, like a natural dialogue — if the user already provided information, use it without asking again. Foundational questions: family size, ages of members (especially small children), dietary preferences or allergies, meals per day, and favorite cuisines. Additional fine-tuning questions (available ingredients, specific meals or snacks) are asked during planning. Automatically include one soup per week unless told otherwise. Base the menu on ingredients the user already has first, then suggest additions. Include alcohol pairing suggestions in the menu without prompting. Prioritize practical, health-conscious, and time-efficient meals. For each meal, include protein_g, fat_g, and carbs_g as plain numeric literals (e.g. 25), never spelled out as words (e.g. never "twenty-five") and never as quoted strings — reasonable, rounded integers only. Your tone is warm, funny, and enthusiastic. You can respond in two ways only: a single question or a meal plan in JSON format — never mix them. The JSON you return must be strictly valid: every number a bare numeral, every string double-quoted, no trailing commas.

    When the user asks you to change, swap, replace, or adjust any part of a plan you already generated earlier in this conversation — a single meal, a single day, or anything else — always return the COMPLETE updated weekly plan in the exact same JSON format below, covering every day and every meal, not just the part that changed. Never return a partial plan, a single day on its own, or a single meal on its own: the app can only display and save one full week at a time, so a partial response loses the rest of that week's plan.

    Every ingredient MUST include a category field. Use consistent grocery store categories: Produce, Dairy, Meat & Seafood, Bakery, Grains & Pasta, Canned & Jarred, Condiments & Sauces, Oils & Vinegars, Spices & Herbs, Frozen, Beverages, Snacks, or Other.

    Every ingredient object MUST have all four keys spelled out explicitly — "name", "category", "amount", "unit" — every single time, for every single ingredient, with no exceptions late in a long response. Never write a bare trailing value like `"amount": 1, "can"` — that is invalid JSON. Always write `"amount": 1, "unit": "can"`. Re-check every ingredient before responding, especially ones later in the list, since dropping the "unit" key partway through is a common mistake to avoid.

    When the user mentions ingredients they already have at home, include them in the userHas array. If none mentioned, use [].

    Return meal plans in this exact JSON format (no extra text, markdown, or comments):

    {
      "type": "JSON",
      "meal_plan": {
        "week": "YYYY-MM-DD to YYYY-MM-DD",
        "userHas": ["olive oil", "pasta", "eggs"],
        "days": [
          {
            "day": "Day of the Week",
            "date": "YYYY-MM-DD",
            "meals": [
              {
                "type": "meal type name",
                "name": "meal name",
                "protein_g": 25,
                "fat_g": 12,
                "carbs_g": 45,
                "ingredients": [
                  { "name": "ingredient 1", "category": "Produce", "amount": 2, "unit": "cups" },
                  { "name": "ingredient 2", "category": "Dairy", "amount": 1, "unit": "tbsp" },
                  { "name": "ingredient 3", "category": "Spices & Herbs" }
                ]
              }
            ]
          }
        ]
      }
    }
    """

    static let welcomeMessage = "Hello! I'm Olli, your AI meal planning chef. How can I help today?"

    static let errorRecoveryPrompt = "Sorry about that! Something went wrong on my end. I'm still here to help — just send your next message and we'll continue where we left off."

    static let recipePrompt = """
    You are an enthusiastic home cook sharing your favorite recipes. Given a meal name and its main ingredients, write a complete recipe in Markdown format.

    Structure your response as:
    ### Overview
    A short, appetizing 1–2 sentence description.

    ### Ingredients
    A formatted list with amounts.

    ### Instructions
    Numbered steps, each with a ### heading that names the step (e.g., ### 1. Prep the vegetables). Keep steps clear and actionable.

    ### Tips
    1–2 practical tips for best results (optional).

    Keep the tone warm and encouraging. Do not include JSON or any structured data — plain Markdown only.
    """

    static let groceryPrompt = """
    You are a grocery shopping assistant. Convert the list of recipe ingredients into a shopper-friendly grocery list.

    Rules:
    - Exclude any items listed in userHas — the user already has them at home
    - Convert recipe units to store-friendly format (e.g. 3 tbsp lemon juice → 2 lemons, 5 basil leaves → 1 bunch basil, 200 ml olive oil → 1 bottle olive oil)
    - Use clear store-friendly names (e.g. "Chicken breast" not "boneless skinless chicken thighs")
    - Keep realistic quantities a person would buy in a store
    - Preserve the category from the input where correct; fix it if clearly wrong
    - Return a JSON array only. No explanation, no markdown, no extra text.

    Output format (JSON array only):
    [{ "name": "string", "amount": number, "unit": "string", "category": "string", "note": "string (optional)" }]
    """

    /// Local fallback only, used if Remote Config hasn't fetched yet or fails — kept in
    /// sync with the `ai_model` parameter's own dashboard default so a cold start or a
    /// failed fetch still gets the intended model, not the pre-Remote-Config value.
    static let aiModel = "gpt-5.6-luna"
}

nonisolated enum RemoteConfigKey: String {
    case dynamicPrompt = "ai_dynamic_prompt"
    case welcomeMessage = "ai_welcome_message"
    case errorRecoveryPrompt = "ai_error_recovery_prompt"
    case recipePrompt = "ai_recipe_prompt"
    case groceryPrompt = "ai_grocery_prompt"
    case promptVersion = "ai_prompt_version"
    case aiModel = "ai_model"
}

/// Ported from remoteConfigService.ts. Prompts load from Firebase Remote Config with
/// the defaults above as fallback; {{CURRENT_DATE}} is substituted at read time.
actor PromptManager {
    static let shared = PromptManager()

    private var lastRefreshTime: Date?
    private let refreshInterval: TimeInterval = 3600 // 1 hour

    // `initialize()` (from AppDelegate at launch) and `refreshIfNeeded()` (from
    // RootView's scenePhase handler, which can fire almost immediately after launch
    // on a foreground transition) could otherwise both call Firebase's own
    // `fetchAndActivate()` concurrently on the same RemoteConfig instance — actors
    // allow reentrancy across `await` suspension points, so a second caller sees
    // `lastRefreshTime` still nil/stale and starts its own fetch before the first
    // one finishes. Tracking the in-flight fetch as a single shared Task and having
    // every caller await *that* instead of starting their own closes the race.
    private var inFlightFetch: Task<Void, Error>?

    private init() {}

    func initialize() async throws {
        let remoteConfig = RemoteConfig.remoteConfig()
        remoteConfig.setDefaults([
            RemoteConfigKey.dynamicPrompt.rawValue: DefaultPrompts.dynamicPrompt as NSObject,
            RemoteConfigKey.welcomeMessage.rawValue: DefaultPrompts.welcomeMessage as NSObject,
            RemoteConfigKey.errorRecoveryPrompt.rawValue: DefaultPrompts.errorRecoveryPrompt as NSObject,
            RemoteConfigKey.recipePrompt.rawValue: DefaultPrompts.recipePrompt as NSObject,
            RemoteConfigKey.groceryPrompt.rawValue: DefaultPrompts.groceryPrompt as NSObject,
            RemoteConfigKey.promptVersion.rawValue: "1.0.0" as NSObject,
            RemoteConfigKey.aiModel.rawValue: DefaultPrompts.aiModel as NSObject,
        ])

        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600
        settings.fetchTimeout = 10
        remoteConfig.configSettings = settings

        try await fetchAndActivate()
    }

    func refreshIfNeeded() async throws {
        if let lastRefreshTime, Date().timeIntervalSince(lastRefreshTime) < refreshInterval {
            return
        }
        try await fetchAndActivate()
    }

    private func fetchAndActivate() async throws {
        if let inFlightFetch {
            return try await inFlightFetch.value
        }
        let task = Task {
            _ = try await RemoteConfig.remoteConfig().fetchAndActivate()
        }
        inFlightFetch = task
        defer { inFlightFetch = nil }
        try await task.value
        lastRefreshTime = Date()
    }

    private func prompt(for key: RemoteConfigKey, default defaultValue: String) -> String {
        let value = RemoteConfig.remoteConfig().configValue(forKey: key.rawValue).stringValue
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultValue
        }
        return value
    }

    /// `configValue(forKey:).source` is `.remote` only for a value that actually came
    /// from an activated Remote Config fetch — this session's, or a previous session's
    /// persisted activation reloaded at SDK init. It's `.default`/`.static` whenever we
    /// never got a live value at all, which is exactly the "silently running on the
    /// emergency local string" case Chat and Recipe should refuse rather than mask.
    /// Reusing `URLError(.notConnectedToInternet)` here (rather than a bespoke error
    /// type) means every existing `NetworkErrorClassifier`/offline-message call site
    /// already handles this correctly with no further changes.
    private func requireRemote(_ key: RemoteConfigKey) throws {
        guard RemoteConfig.remoteConfig().configValue(forKey: key.rawValue).source == .remote else {
            throw URLError(.notConnectedToInternet)
        }
    }

    /// Mirrors getDynamicPrompt: substitutes {{CURRENT_DATE}} with today's date. Throws
    /// if Remote Config has never delivered a live value — see `requireRemote(_:)`.
    func dynamicPrompt() throws -> String {
        try requireRemote(.dynamicPrompt)
        let raw = prompt(for: .dynamicPrompt, default: DefaultPrompts.dynamicPrompt)
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        return raw.replacingOccurrences(of: "{{CURRENT_DATE}}", with: String(today))
    }

    /// Cosmetic only (a greeting shown before any AI call happens) — stays lenient.
    func welcomeMessage() -> String {
        prompt(for: .welcomeMessage, default: DefaultPrompts.welcomeMessage)
    }

    /// Only ever shown after a real AI call has already failed — stays lenient.
    func errorRecoveryPrompt() -> String {
        prompt(for: .errorRecoveryPrompt, default: DefaultPrompts.errorRecoveryPrompt)
    }

    /// Recipe has no degraded/offline mode, so this requires a live value — see
    /// `requireRemote(_:)`.
    func recipePrompt() throws -> String {
        try requireRemote(.recipePrompt)
        return prompt(for: .recipePrompt, default: DefaultPrompts.recipePrompt)
    }

    /// Grocery's AI step is an optional polish layer — `generateGroceryListForPlan`
    /// already falls back to a deterministic, non-AI list on any failure, so this
    /// deliberately stays lenient rather than refusing to run offline.
    func groceryPrompt() -> String {
        prompt(for: .groceryPrompt, default: DefaultPrompts.groceryPrompt)
    }

    /// Which OpenAI model every AI call (chat, recipe, grocery) uses — configurable via
    /// Remote Config's `ai_model` parameter without an app update. Lenient variant for
    /// Grocery's optional AI step; Chat/Recipe use `requiredAIModel()` instead.
    func aiModel() -> String {
        prompt(for: .aiModel, default: DefaultPrompts.aiModel)
    }

    /// Same value as `aiModel()`, but throws instead of silently returning the local
    /// default when Remote Config has never delivered a live value — used by Chat and
    /// Recipe alongside their own throwing prompt accessors.
    func requiredAIModel() throws -> String {
        try requireRemote(.aiModel)
        return prompt(for: .aiModel, default: DefaultPrompts.aiModel)
    }
}
