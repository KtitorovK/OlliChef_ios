import SwiftUI

/// NavigationLink(value:) silently fails to reach an ancestor's navigationDestination
/// when it sits inside this screen's own page-style day-pager TabView nested inside
/// iPad's outer Chat/MealPlan/Groceries TabView inside a NavigationSplitView detail
/// column — a real, still-unresolved SwiftUI/NavigationSplitView bug on this SDK (every
/// push mechanism tried there, including the pre-iOS16 NavigationLink(isActive:), silently
/// no-ops even though the bound state does update). iPhone has no NavigationSplitView and
/// the plain NavigationLink works there, so this is an opt-in override: nil here preserves
/// that working default, and iPad's MainSplitView is the one place that injects a real
/// closure, opening the recipe as a fullScreenCover instead of a pushed destination.
private struct MealTapActionKey: EnvironmentKey {
    static let defaultValue: ((Meal) -> Void)? = nil
}

extension EnvironmentValues {
    var mealTapAction: ((Meal) -> Void)? {
        get { self[MealTapActionKey.self] }
        set { self[MealTapActionKey.self] = newValue }
    }
}

/// Ported from MealPlanScreen.tsx: a day-selector pill strip synced with a paged day
/// browser. Full visual parity (meal thumbnails via Pexels, expandable ingredients) is
/// a later design pass — this establishes the real data flow, the date picker, and the
/// Firestore contract.
struct MealPlanScreen: View {
    @StateObject private var viewModel = MealPlanViewModel()
    @EnvironmentObject private var tabRouter: TabRouter
    @State private var selectedDate: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var metrics: AppMetrics { AppMetrics(horizontalSizeClass: horizontalSizeClass) }

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
        .onChange(of: viewModel.mealPlan?.id) {
            tabRouter.hasMealPlan = viewModel.mealPlan != nil
        }
        // A .toolbar declared here never renders on either platform: this screen lives
        // inside MainTabView's TabView with no NavigationStack of its own, and toolbar
        // content from a TabView child doesn't propagate to an ancestor's navigation bar
        // (confirmed live — Groceries' own pre-existing ShareLink toolbar button has the
        // identical, previously unnoticed problem). The "Clear Current Meal Plan" button
        // is declared instead at each platform's outer navigation level (RootView for
        // iPhone, MainSplitView for iPad, next to where the Profile button already lives
        // for the same reason) and signals here via TabRouter.requestMealPlanClear.
        .onChange(of: tabRouter.requestMealPlanClear) {
            Task { await viewModel.clearMealPlan(router: tabRouter) }
        }
        .alert("Error", isPresented: .constant(viewModel.clearError != nil), presenting: viewModel.clearError) { _ in
            Button("OK") { viewModel.clearError = nil }
        } message: { message in
            Text(message)
        }
    }

    /// Mirrors renderDaySelector: a horizontal strip of date pills, auto-scrolling to
    /// keep the selected pill in view, that drives the paged day browser below it.
    /// Selected uses BrandForest (a strong, deliberate selection color); unselected
    /// pills use the subtle BrandTint instead of the same saturated green repeated
    /// across every day, which read as one undifferentiated bright-green block.
    private func daySelector(_ mealPlan: MealPlan) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: metrics.dayChipGap) {
                    ForEach(mealPlan.days, id: \.date) { day in
                        let isSelected = day.date == selectedDate
                        Button {
                            withAnimation { selectedDate = day.date }
                        } label: {
                            VStack(spacing: 2) {
                                Text(day.pillWeekdayLabel)
                                    .font(AppTypography.smallMetadata.weight(.semibold))
                                Text(day.pillDateLabel)
                                    .font(AppTypography.tabLabel)
                            }
                            .foregroundStyle(isSelected ? AppColor.textOnBrand : AppColor.brandForest)
                            .frame(width: metrics.dayChipWidth, height: metrics.dayChipHeight)
                            .background(isSelected ? AppColor.brandForest : AppColor.brandTint)
                            .clipShape(RoundedRectangle(cornerRadius: metrics.dayChipRadius))
                        }
                        .hoverEffect(.highlight)
                        .id(day.date)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, AppSpacing.md)
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
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColor.textPrimary)
            Text("Ask Olli in Chat to plan your week")
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
            // Mirrors GroceryListScreen's own empty-state "Create New List" button —
            // same call to action (jump to Chat), same styling.
            Button("Create Meal Plan") {
                tabRouter.selection = .chat
            }
            .font(AppTypography.button)
            .foregroundStyle(AppColor.textOnBrand)
            .padding(.horizontal, AppSpacing.buttonHorizontal)
            .frame(minHeight: metrics.primaryButtonHeight)
            .background(AppColor.brandAction)
            .clipShape(Capsule())
        }
        .padding(AppSpacing.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dayView(_ day: DayMeals) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.contentPadding) {
                HStack {
                    Text(day.fullWeekdayLabel)
                        .font(AppTypography.pageTitle)
                        .foregroundStyle(AppColor.textPrimary)
                    if day.isToday {
                        Text("Today")
                            .font(AppTypography.tabLabel)
                            .foregroundStyle(AppColor.textOnBrand)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, AppSpacing.xxs)
                            .background(AppColor.brandAccent)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }

                ForEach(day.meals) { meal in
                    MealCardView(meal: meal, metrics: metrics)
                }
            }
            .padding(.vertical, AppSpacing.contentPadding)
            .padding(.horizontal, metrics.screenPadding)
            .frame(maxWidth: metrics.mealPlanContentMaxWidth, alignment: .leading)
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
    let metrics: AppMetrics
    @State private var isExpanded = false
    @Environment(\.mealTapAction) private var mealTapAction

    /// The base thumbnail size, grown further while expanded so the enlarged photo and the
    /// ingredients list (now beside it, not below the whole row) grow together — a deliberate
    /// per-user-request deviation from RN, which never resizes the thumbnail on expand.
    private var thumbSize: CGFloat {
        isExpanded ? metrics.mealImageSize * 1.6 : metrics.mealImageSize
    }

    private var thumbRadius: CGFloat {
        isExpanded ? AppRadius.image * 1.6 : AppRadius.image
    }

    @ViewBuilder
    private func mealLink<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        if let mealTapAction {
            Button { mealTapAction(meal) } label: { label() }
        } else {
            NavigationLink(value: meal) { label() }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            mealLink {
                MealImageView(mealName: meal.name, overrideBox: (thumbSize, thumbSize, thumbRadius))
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                mealLink {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(meal.type?.capitalized ?? "Meal")
                            .font(AppTypography.metadata.weight(.semibold))
                            .foregroundStyle(AppColor.textSecondary)
                        Text(meal.name)
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(AppColor.textPrimary)
                        if let nutrition = meal.nutritionInfo {
                            Text(nutrition.summaryText)
                                .font(AppTypography.metadata)
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
                            .font(AppTypography.metadata.weight(.medium))
                            .foregroundStyle(AppColor.brandAction)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityLabel(isExpanded ? "Hide ingredient details" : "View ingredient details")
                }

                if isExpanded, !meal.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Divider()
                            .padding(.bottom, AppSpacing.xxs)
                        Text("Ingredients:")
                            .font(AppTypography.smallMetadata)
                            .foregroundStyle(AppColor.textSecondary)
                        ForEach(Array(meal.ingredients.enumerated()), id: \.offset) { _, ingredient in
                            Text("• \(ingredient.name)")
                                .font(AppTypography.smallMetadata)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(metrics.cardPadding)
        .background(AppColor.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: metrics.cardRadius))
    }
}
