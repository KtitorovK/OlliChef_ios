import SwiftUI

/// Grouped-by-category checklist, each category collapsible into a card ("bubble") —
/// a new native design, not ported from RN. Loading/refresh follows the same `.task` +
/// `.refreshable` convention as MealPlanScreen, rather than RN's focus-triggered
/// refetch — reasonable here since toggles now persist (see GroceryListViewModel), so
/// a stale in-memory list isn't the correctness problem it was in the RN version.
struct GroceryListScreen: View {
    @StateObject private var viewModel = GroceryListViewModel()
    @EnvironmentObject private var tabRouter: TabRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var metrics: AppMetrics { AppMetrics(horizontalSizeClass: horizontalSizeClass) }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.hasItems {
                list
            } else {
                emptyState
            }
        }
        .background(AppColor.surfaceBody)
        .task {
            await viewModel.load()
            syncShareText()
        }
        .refreshable {
            await viewModel.load()
            syncShareText()
        }
        .onChange(of: tabRouter.mealPlanClearedAt) {
            Task {
                await viewModel.load()
                syncShareText()
            }
        }
        // A .toolbar declared here never renders on either platform: this screen lives
        // inside MainTabView's TabView with no NavigationStack of its own, and toolbar
        // content from a TabView child doesn't propagate to an ancestor's navigation bar
        // (confirmed live — this ShareLink button itself sat here unnoticed until this
        // fix). The Share button is declared instead at each platform's outer navigation
        // level (RootView for iPhone, MainSplitView for iPad, next to where the Profile /
        // Clear Meal Plan buttons already live for the same reason) and reads the shared
        // text via TabRouter.groceryShareText, kept in sync here.
    }

    /// Mirrors shareGroceryList: nil once the list is empty, formatted as plain text
    /// for the system share sheet otherwise. Called after every load and toggle so the
    /// outer Share button (see the comment above) always reflects the current items.
    private func syncShareText() {
        tabRouter.groceryShareText = viewModel.hasItems ? viewModel.shareText() : nil
    }

    /// Unlike Chat/MealPlan, this content is deliberately NOT capped to a narrower
    /// reading width on iPad — a list/table of items benefits from the detail
    /// column's real width instead of an artificial phone-width column.
    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(viewModel.groupedItems, id: \.category) { group in
                    categoryBubble(group.category, items: group.items)
                }
            }
            .padding(.horizontal, metrics.screenPadding)
            .padding(.vertical, AppSpacing.contentPadding)
        }
    }

    /// One collapsible card per category: an icon badge, name, item count, and a
    /// chevron that flips to show/hide the rows — tapping anywhere on the header
    /// toggles it. Header uses BrandTint (a subtle large-area green) instead of a
    /// saturated full-width bar, with BrandForest for the category title.
    private func categoryBubble(_ category: String, items: [GroceryItem]) -> some View {
        let isExpanded = viewModel.isExpanded(category)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleExpanded(category)
                }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    ZStack {
                        Circle().fill(AppColor.surfaceCard)
                        Image(systemName: categoryIcon(category))
                            .font(AppTypography.metadata.weight(.semibold))
                            .foregroundStyle(AppColor.brandAccent)
                    }
                    .frame(width: 32, height: 32)

                    Text(category)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColor.brandForest)

                    Spacer(minLength: AppSpacing.xs)

                    Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                        .font(AppTypography.smallMetadata)
                        .foregroundStyle(AppColor.textSecondary)

                    Image(systemName: "chevron.up")
                        .font(AppTypography.smallMetadata.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : 180))
                }
                .padding(.horizontal, AppSpacing.contentPadding)
                .padding(.vertical, AppSpacing.md)
                .contentShape(Rectangle())
                .background(AppColor.brandTint)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.name) { index, item in
                        if index > 0 {
                            Divider().padding(.leading, AppSpacing.contentPadding)
                        }
                        itemRow(item, category: category)
                    }
                }
            }
        }
        .background(AppColor.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.divider, lineWidth: 1)
        }
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "Produce": return "carrot.fill"
        case "Dairy": return "drop.fill"
        case "Meat & Seafood": return "fish.fill"
        case "Bakery": return "birthday.cake.fill"
        case "Grains & Pasta": return "leaf.fill"
        case "Canned & Jarred": return "cylinder.fill"
        case "Condiments & Sauces": return "drop.triangle.fill"
        case "Oils & Vinegars": return "flask.fill"
        case "Spices & Herbs": return "sparkles"
        case "Frozen": return "snowflake"
        case "Beverages": return "cup.and.saucer.fill"
        case "Snacks": return "bag.fill"
        default: return "cart.fill"
        }
    }

    private func itemRow(_ item: GroceryItem, category: String) -> some View {
        Button {
            Task {
                await viewModel.toggleItem(category: category, name: item.name)
                syncShareText()
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(item.checked ? AppColor.brandAction : AppColor.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(AppTypography.body)
                        .foregroundStyle(item.checked ? AppColor.textTertiary : AppColor.textPrimary)
                        .strikethrough(item.checked)
                    if let notes = item.notes, !notes.isEmpty {
                        Text(notes)
                            .font(AppTypography.smallMetadata)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }

                Spacer(minLength: AppSpacing.xs)

                if let amount = item.amount {
                    Text(quantityLabel(amount, item.unit))
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding(.horizontal, AppSpacing.contentPadding)
            .frame(minHeight: metrics.groceryRowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityAddTraits(item.checked ? [.isSelected] : [])
        .accessibilityValue(item.checked ? "Checked" : "Unchecked")
    }

    private func quantityLabel(_ amount: Double, _ unit: String?) -> String {
        let amountText = amount.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(amount)) : String(amount)
        return [amountText, unit].compactMap { $0 }.joined(separator: " ")
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.contentPadding) {
            Image("EmptyGroceryList")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
            Text("Your grocery list is empty")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColor.textPrimary)
            Text("Use Olli to generate a grocery list based on your meal plan")
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Create New List") {
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
}
