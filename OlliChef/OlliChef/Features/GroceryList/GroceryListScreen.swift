import SwiftUI

/// Ported from GroceryListScreen.tsx: grouped-by-category checklist with a per-category
/// "check all" toggle. Loading/refresh follows the same `.task` + `.refreshable`
/// convention as MealPlanScreen, rather than RN's focus-triggered refetch — reasonable
/// here since toggles now persist (see GroceryListViewModel), so a stale in-memory list
/// isn't the correctness problem it was in the RN version.
struct GroceryListScreen: View {
    @StateObject private var viewModel = GroceryListViewModel()
    @EnvironmentObject private var tabRouter: TabRouter

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
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .toolbar {
            // Mirrors shareGroceryList: only shown once there's something to share,
            // formatting the checklist as plain text via the system share sheet.
            // On iPad, Chat/Meal Plan/Groceries all stay mounted at once (see
            // MainTabView's detailView) so their toolbars share one NavigationStack —
            // without this selection check, this button would keep showing on whichever
            // tab is actually visible instead of just Groceries.
            if viewModel.hasItems, tabRouter.selection == .groceries {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: viewModel.shareText()) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(AppColor.brandPrimary)
                    }
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(viewModel.groupedItems, id: \.category) { group in
                    Section {
                        ForEach(group.items, id: \.name) { item in
                            itemRow(item, category: group.category)
                            Divider()
                        }
                    } header: {
                        categoryHeader(group.category, items: group.items)
                    }
                }
            }
        }
    }

    /// Mirrors AppGrocery.categoryHeader/categoryHeaderText: a filled brand-color bar
    /// with light text — not a plain background, which is what this had before.
    private func categoryHeader(_ category: String, items: [GroceryItem]) -> some View {
        HStack {
            Text(category)
                .font(AppTypography.subhead.weight(.semibold))
                .foregroundStyle(AppColor.textOnBrand)
            Spacer()
            Button {
                Task { await viewModel.toggleCategory(category) }
            } label: {
                Image(systemName: viewModel.isCategoryFullyChecked(items) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(AppColor.textOnBrand)
            }
            .hoverEffect(.highlight)
        }
        .padding(.horizontal, AppSpacing.contentPadding)
        .padding(.vertical, 12)
        .background(AppColor.brandPrimary)
    }

    private func itemRow(_ item: GroceryItem, category: String) -> some View {
        Button {
            Task { await viewModel.toggleItem(category: category, name: item.name) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(AppTypography.body)
                        .foregroundStyle(item.checked ? AppColor.textSecondary : AppColor.textPrimary)
                        .strikethrough(item.checked)
                    if let notes = item.notes, !notes.isEmpty {
                        Text(notes)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                Spacer()
                if let amount = item.amount {
                    Text(quantityLabel(amount, item.unit))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(item.checked ? AppColor.brandPrimary : AppColor.textSecondary)
            }
            .padding(.horizontal, AppSpacing.contentPadding)
            .padding(.vertical, 12)
            .background(AppColor.surfaceBody)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
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
                .font(AppTypography.subhead.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
            Text("Use Olli to generate a grocery list based on your meal plan")
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Create New List") {
                tabRouter.selection = .chat
            }
            .font(AppTypography.body.weight(.bold))
            .foregroundStyle(AppColor.textOnBrand)
            .padding(.horizontal, AppSpacing.buttonHorizontal)
            .padding(.vertical, AppSpacing.buttonVertical)
            .background(AppColor.brandPrimary)
            .clipShape(Capsule())
        }
        .padding(AppSpacing.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
