import SwiftUI

/// Ported from MealPlanScreen.tsx: a day-selector pill strip synced with a paged day
/// browser. Full visual parity (meal thumbnails via Pexels, expandable ingredients) is
/// a later design pass — this establishes the real data flow, the date picker, and the
/// Firestore contract.
struct MealPlanScreen: View {
    @StateObject private var viewModel = MealPlanViewModel()
    @State private var selectedDate: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Mirrors MealPlanScreen.tsx's own `isTablet` branch (thumb 100→130, caption→body,
    /// subhead→headline, 16→32 padding) — real RN tablet sizing that got dropped when this
    /// screen was first ported, not an invented iPad-only feature. RN never restructures
    /// into a grid on tablet, so this stays a single column, just bigger and better spaced,
    /// rather than filling the split-view detail pane's extra room with new content.
    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let mealPlan = viewModel.mealPlan {
                VStack(spacing: 0) {
                    daySelector(mealPlan)
                    TabView(selection: $selectedDate) {
                        ForEach(mealPlan.days, id: \.date) { day in
                            dayView(day).tag(Optional(day.date))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.surfaceBody)
        .task {
            await viewModel.load()
            if selectedDate == nil {
                selectedDate = viewModel.mealPlan?.days.first?.date
            }
        }
        .refreshable { await viewModel.load() }
    }

    /// Mirrors renderDaySelector: a horizontal strip of date pills, auto-scrolling to
    /// keep the selected pill in view, that drives the paged day browser below it.
    private func daySelector(_ mealPlan: MealPlan) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(mealPlan.days, id: \.date) { day in
                        let isSelected = day.date == selectedDate
                        Button {
                            withAnimation { selectedDate = day.date }
                        } label: {
                            VStack(spacing: 2) {
                                Text(day.pillWeekdayLabel)
                                    .font(AppTypography.caption.weight(.semibold))
                                Text(day.pillDateLabel)
                                    .font(AppTypography.label.weight(.medium))
                            }
                            .foregroundStyle(isSelected ? AppColor.textOnBrand : AppColor.textPrimary)
                            .frame(width: 56, height: 60)
                            .background(isSelected ? AppColor.brandSecondary : AppColor.brandPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .hoverEffect(.highlight)
                        .id(day.date)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 80)
            .background(AppColor.surfaceHeader)
            .onChange(of: selectedDate) {
                if let selectedDate {
                    withAnimation { proxy.scrollTo(selectedDate, anchor: .center) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.contentPadding) {
            Image("EmptyMealPlan")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
            Text("No meal plan yet")
                .font(AppTypography.subhead.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
            Text("Ask Olli in Chat to plan your week")
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(AppSpacing.contentPadding)
    }

    private func dayView(_ day: DayMeals) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.contentPadding) {
                HStack {
                    Text(day.fullWeekdayLabel)
                        .font(AppTypography.headline.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    if day.isToday {
                        Text("Today")
                            .font(AppTypography.label.weight(.semibold))
                            .foregroundStyle(AppColor.textOnBrand)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColor.brandPrimary)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }

                ForEach(day.meals) { meal in
                    MealCardView(meal: meal, isRegular: isRegular)
                }
            }
            .padding(.vertical, AppSpacing.contentPadding)
            .padding(.horizontal, isRegular ? 32 : AppSpacing.contentPadding)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Mirrors MealCard from MealPlanScreen.tsx: the row itself navigates to the recipe story,
/// while a separate "View Details"/"Hide Details" toggle expands the ingredient list inline
/// without leaving this screen. RN nests the toggle inside the text column (indented past the
/// image, directly under the nutrition line) since its TouchableOpacitys nest freely; a
/// SwiftUI Button can't live inside a NavigationLink's own label and still get its own tap
/// target, so the image and the text column are two separate NavigationLinks side by side —
/// both navigate to the same meal — letting the toggle sit as an ordinary sibling under the
/// text without being swallowed by either link's hit area.
private struct MealCardView: View {
    let meal: Meal
    let isRegular: Bool
    @State private var isExpanded = false

    /// The base thumbnail size, grown further while expanded so the enlarged photo and the
    /// ingredients list (now beside it, not below the whole row) grow together — a deliberate
    /// per-user-request deviation from RN, which never resizes the thumbnail on expand.
    private var thumbSize: CGFloat {
        let base: CGFloat = isRegular ? 130 : 100
        return isExpanded ? base * 1.6 : base
    }

    /// A fixed 8pt radius (fine at the base thumbnail size) reads as barely-rounded once
    /// the photo grows on expand, so it scales with the image instead of staying fixed.
    private var thumbRadius: CGFloat { thumbSize * 0.1 }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            NavigationLink(value: meal) {
                MealImageView(mealName: meal.name, overrideBox: (thumbSize, thumbSize, thumbRadius))
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)

            VStack(alignment: .leading, spacing: 4) {
                NavigationLink(value: meal) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meal.type?.capitalized ?? "Meal")
                            .font((isRegular ? AppTypography.body : AppTypography.label).weight(.semibold))
                            .foregroundStyle(AppColor.textSecondary)
                        Text(meal.name)
                            .font((isRegular ? AppTypography.headline : AppTypography.subhead).weight(.medium))
                            .foregroundStyle(AppColor.textPrimary)
                        if let nutrition = meal.nutritionInfo {
                            Text(nutrition.summaryText)
                                .font(isRegular ? AppTypography.body : AppTypography.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)

                if !meal.ingredients.isEmpty {
                    Button {
                        withAnimation { isExpanded.toggle() }
                    } label: {
                        Text(isExpanded ? "Hide Details" : "View Details")
                            .font(isRegular ? AppTypography.body : AppTypography.caption)
                            .foregroundStyle(AppColor.brandPrimary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                }

                if isExpanded, !meal.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Divider()
                            .padding(.bottom, 4)
                        Text("Ingredients:")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        ForEach(Array(meal.ingredients.enumerated()), id: \.offset) { _, ingredient in
                            Text("• \(ingredient.name)")
                                .font(AppTypography.label)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(isRegular ? 20 : 14)
        .background(AppColor.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
    }
}
