import SwiftUI

/// Ported from RecipeStoryScreen.tsx: a Pexels hero image, nutrition info, a plain
/// ingredients list (from the meal itself, not the AI text), then the AI-generated
/// Markdown recipe story.
struct RecipeStoryScreen: View {
    let meal: Meal

    @StateObject private var viewModel = RecipeStoryViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Full-bleed hero, matching RN's mealImage override (width: '100%',
                // ~40% of screen height, square corners) — sits outside the padded
                // content below, not inset like the rest of the screen.
                MealImageView(mealName: meal.name, size: .large, overrideBox: (nil, UIScreen.main.bounds.height * 0.4, 0))

                VStack(alignment: .leading, spacing: AppSpacing.contentPadding) {
                    if let nutrition = meal.nutritionInfo {
                        nutritionSection(nutrition)
                    }

                    if !meal.ingredients.isEmpty {
                        ingredientsSection
                    }

                    // Mirrors RN's actual order: the meal name title sits right before
                    // the AI story, after nutrition/ingredients — not at the very top.
                    Text(meal.name)
                        .font(AppTypography.title.weight(.bold))
                        .foregroundStyle(AppColor.textPrimary)

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

    @ViewBuilder
    private var storySection: some View {
        if viewModel.isLoading {
            VStack(spacing: 8) {
                ProgressView()
                    .tint(AppColor.brandPrimary)
                Text("Conjuring a culinary tale…")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
        } else if let story = viewModel.story {
            VStack(alignment: .leading, spacing: AppSpacing.contentPadding) {
                // The AI sometimes generates its own "Ingredients" section despite being
                // told not to — filtered here rather than relying solely on prompt
                // wording, since that also retroactively fixes already-cached stories
                // generated before this instruction existed.
                ForEach(Self.parseSections(story).filter { $0.heading?.localizedCaseInsensitiveContains("ingredients") != true }) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        if let heading = section.heading {
                            Text(heading)
                                .font(AppTypography.subhead.weight(.bold))
                                .foregroundStyle(AppColor.textPrimary)
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
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ingredients")
                .font(AppTypography.subhead.weight(.bold))
                .foregroundStyle(AppColor.textPrimary)
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

    private func nutritionSection(_ nutrition: NutritionInfo) -> some View {
        HStack(spacing: 16) {
            if let calories = nutrition.calories { nutritionChip("\(Int(calories))", "kcal") }
            if let protein = nutrition.protein { nutritionChip("\(Int(protein))g", "protein") }
            if let fat = nutrition.fat { nutritionChip("\(Int(fat))g", "fat") }
            if let carbs = nutrition.carbs { nutritionChip("\(Int(carbs))g", "carbs") }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(AppColor.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
    }

    private func nutritionChip(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppTypography.subhead.weight(.bold))
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
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
            if line.hasPrefix("### ") {
                flush()
                currentHeading = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else {
                currentBody.append(line)
            }
        }
        flush()
        return sections
    }

    /// Renders inline Markdown (bold/italic) the model uses within a section's body —
    /// mirrors react-native-markdown-display's `strong` styling without pulling in a
    /// full block-level Markdown renderer for content that's already pre-sectioned above.
    private static func attributedBody(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
