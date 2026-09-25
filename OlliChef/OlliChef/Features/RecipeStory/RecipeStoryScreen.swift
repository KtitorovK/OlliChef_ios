import SwiftUI

/// Ported from RecipeStoryScreen.tsx, then redesigned per the App Store marketing
/// mockup's step-by-step layout — a real app-store screenshot, not something either
/// RN or the earlier native version ever actually rendered. That layout has no
/// analogue in the RN source (its `Markdown` component just renders `story` flat,
/// with no icon-based macros), so this is new design work built on top of the same
/// underlying data: a Pexels hero image, nutrition info, the meal's own ingredients
/// list, and the AI-generated Markdown recipe story.
struct RecipeStoryScreen: View {
    let meal: Meal

    @StateObject private var viewModel = RecipeStoryViewModel()

    private var sections: [MarkdownSection]? {
        // A bare `Self.parseSections` reference here would need to convert a
        // MainActor-isolated static method into a plain, isolation-erased function
        // value to satisfy `Optional.map`'s signature — which is exactly what
        // `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` flags. Wrapping it in a
        // closure keeps the call inside this MainActor context instead.
        viewModel.story.map { Self.parseSections($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Full-bleed hero, matching RN's mealImage override (width: '100%',
                // ~40% of screen height, square corners) — sits outside the padded
                // content below, not inset like the rest of the screen.
                MealImageView(mealName: meal.name, size: .large, overrideBox: (nil, UIScreen.main.bounds.height * 0.4, 0))

                VStack(alignment: .leading, spacing: AppSpacing.contentPadding) {
                    Text(meal.name)
                        .font(AppTypography.pageTitle)
                        .foregroundStyle(AppColor.textPrimary)

                    if let overview = sections.flatMap({ Self.overviewBody(from: $0) }), !overview.isEmpty {
                        Text(overview)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    if let nutrition = meal.nutritionInfo {
                        nutritionSection(nutrition)
                    }

                    if !meal.ingredients.isEmpty {
                        ingredientsSection
                    }

                    storySection
                }
                .padding(AppSpacing.contentPadding)
            }
        }
        .background(AppColor.surfaceBody)
        .navigationTitle("Recipe Story")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(for: meal) }
    }

    // MARK: - Story (steps + any extra sections)

    @ViewBuilder
    private var storySection: some View {
        if viewModel.isLoading {
            VStack(spacing: 8) {
                ProgressView()
                    .tint(AppColor.brandAccent)
                Text("Conjuring a culinary tale…")
                    .font(AppTypography.smallMetadata)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
        } else if let sections {
            let steps = Self.stepSections(from: sections)

            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.contentPadding) {
                    Text("Step-by-step")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColor.brandForest)
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        stepRow(number: index + 1, section: step)
                    }
                }
            }

            // Anything that isn't Overview/Ingredients/Instructions or a step under
            // it — e.g. "Tips" — still renders, generically, so nothing the AI wrote
            // is silently dropped just because this design doesn't have a slot for it.
            ForEach(Self.extraSections(from: sections, excludingSteps: steps)) { section in
                VStack(alignment: .leading, spacing: 6) {
                    if let heading = section.heading {
                        Text(heading)
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(AppColor.brandForest)
                    }
                    if !section.body.isEmpty {
                        Text(Self.attributedBody(section.body))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColor.textPrimary)
                    }
                }
            }
        }
    }

    private func stepRow(number: Int, section: MarkdownSection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Step \(number)")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColor.brandForest)
            Text(Self.attributedBody(section.body))
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textPrimary)
        }
    }

    // MARK: - Ingredients / nutrition

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ingredients")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColor.brandForest)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(meal.ingredients, id: \.name) { ingredient in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text(ingredient.displayLabel)
                    }
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textPrimary)
                }
            }
        }
    }

    private func nutritionSection(_ nutrition: NutritionInfo) -> some View {
        HStack(spacing: 0) {
            if let protein = nutrition.protein {
                macroItem(icon: "leaf.fill", tint: AppColor.brandForest, value: "\(Int(protein))g", label: "Protein")
            }
            if let fat = nutrition.fat {
                macroItem(icon: "drop.fill", tint: AppColor.statusWarning, value: "\(Int(fat))g", label: "Fat")
            }
            if let carbs = nutrition.carbs {
                macroItem(icon: "carrot.fill", tint: AppColor.brandForest, value: "\(Int(carbs))g", label: "Carbs")
            }
            if let calories = nutrition.calories {
                caloriesChip(Int(calories))
            }
        }
    }

    private func macroItem(icon: String, tint: Color, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(value)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColor.textPrimary)
            }
            Text(label)
                .font(AppTypography.smallMetadata)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func caloriesChip(_ calories: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(calories)")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColor.textPrimary)
            Text("Calories")
                .font(AppTypography.smallMetadata)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColor.brandTint)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
    }

    // MARK: - Markdown sectioning

    private struct MarkdownSection: Identifiable {
        let id = UUID()
        let heading: String?
        let body: String
    }

    /// Splits the AI's response on "### " headings — matching the structure the recipe
    /// prompt asks for (Overview / Ingredients / Instructions / Tips, plus one heading
    /// per numbered step) — rather than pulling in a full Markdown rendering library for
    /// this narrow, well-known shape.
    ///
    /// The model doesn't always put the heading marker first: the prompt asks for
    /// "### 1. Prep the vegetables", but it sometimes emits "1. ### Prep the
    /// vegetables" instead (treating the numbering as its own list, with "###" as an
    /// inline marker inside it) — which used to leak the literal "###" into the
    /// rendered body since it didn't match the "### " prefix. `headingText(in:)`
    /// recognizes both orderings and always normalizes back to "N. Title", so
    /// numbering-detection below doesn't care which order the model chose.
    private static func parseSections(_ text: String) -> [MarkdownSection] {
        var sections: [MarkdownSection] = []
        var currentHeading: String?
        var currentBody: [String] = []

        func flush() {
            let body = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if currentHeading != nil || !body.isEmpty {
                sections.append(MarkdownSection(heading: currentHeading, body: body))
            }
            currentBody = []
        }

        for line in text.components(separatedBy: "\n") {
            if let heading = headingText(in: line) {
                flush()
                currentHeading = heading
            } else {
                currentBody.append(line)
            }
        }
        flush()
        return sections
    }

    private static func headingText(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var remainder = trimmed
        var leadingNumber: String?
        if let range = trimmed.range(of: #"^\d+[.)]\s*"#, options: .regularExpression) {
            leadingNumber = String(trimmed[range]).trimmingCharacters(in: .whitespaces)
            remainder = String(trimmed[range.upperBound...])
        }
        guard remainder.hasPrefix("### ") else { return nil }
        var title = String(remainder.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        if let leadingNumber, stepNumberAndTitle(from: title) == nil {
            title = "\(leadingNumber) \(title)"
        }
        return title
    }

    private static func isOverviewHeading(_ heading: String) -> Bool {
        heading.localizedCaseInsensitiveCompare("overview") == .orderedSame
    }

    private static func isIngredientsHeading(_ heading: String) -> Bool {
        heading.localizedCaseInsensitiveContains("ingredients")
    }

    private static func isInstructionsHeading(_ heading: String) -> Bool {
        heading.localizedCaseInsensitiveContains("instructions")
    }

    private static let stepNumberRegex = try! NSRegularExpression(pattern: #"^(\d+)[.)]\s*(.*)$"#)

    private static func stepNumberAndTitle(from heading: String) -> (number: Int, title: String)? {
        let range = NSRange(heading.startIndex..., in: heading)
        guard let match = stepNumberRegex.firstMatch(in: heading, range: range),
              let numberRange = Range(match.range(at: 1), in: heading),
              let titleRange = Range(match.range(at: 2), in: heading),
              let number = Int(heading[numberRange]) else { return nil }
        return (number, String(heading[titleRange]))
    }

    private static func overviewBody(from sections: [MarkdownSection]) -> String? {
        sections.first { $0.heading.map { isOverviewHeading($0) } == true }?.body
    }

    /// Steps are identified by position (everything right after the "Instructions"
    /// heading, up to the next Overview/Ingredients/Tips heading or the end) rather
    /// than purely by numbering, so a step still lands in "Step-by-step" even if the
    /// model drops its number entirely — the numbering is only used afterward, to
    /// pick a per-step Pexels search query.
    private static func stepSections(from sections: [MarkdownSection]) -> [MarkdownSection] {
        guard let instructionsIndex = sections.firstIndex(where: { $0.heading.map { isInstructionsHeading($0) } == true }) else {
            return sections.filter { $0.heading.flatMap { stepNumberAndTitle(from: $0) } != nil }
        }
        let afterInstructions = sections[(instructionsIndex + 1)...]
        return Array(afterInstructions.prefix { section in
            guard let heading = section.heading else { return true }
            return !isOverviewHeading(heading) && !isIngredientsHeading(heading) && !isTipsHeading(heading)
        })
    }

    private static func isTipsHeading(_ heading: String) -> Bool {
        heading.localizedCaseInsensitiveContains("tips")
    }

    private static func extraSections(from sections: [MarkdownSection], excludingSteps steps: [MarkdownSection]) -> [MarkdownSection] {
        let stepIDs = Set(steps.map(\.id))
        return sections.filter { section in
            if stepIDs.contains(section.id) { return false }
            guard let heading = section.heading else { return !section.body.isEmpty }
            return !isOverviewHeading(heading) && !isIngredientsHeading(heading) && !isInstructionsHeading(heading)
        }
    }

    /// Renders inline Markdown (bold/italic) the model uses within a section's body —
    /// mirrors react-native-markdown-display's `strong` styling without pulling in a
    /// full block-level Markdown renderer for content that's already pre-sectioned above.
    private static func attributedBody(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
