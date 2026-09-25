import Combine
import Foundation

/// Ported from GroceryListScreen.tsx. Unlike the RN screen — whose checkbox toggles
/// are local React state only, never written back to Firestore, so checked items don't
/// survive a restart — this persists every toggle immediately.
@MainActor
final class GroceryListViewModel: ObservableObject {
    @Published private(set) var groupedItems: [(category: String, items: [GroceryItem])] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    /// Categories the user has collapsed — absent means expanded, so a freshly loaded
    /// list starts with every category open rather than needing every category name
    /// pre-populated into this set.
    @Published private(set) var collapsedCategories: Set<String> = []

    private var groceryList: GroceryList?

    var totalItems: Int { groupedItems.reduce(0) { $0 + $1.items.count } }
    var hasItems: Bool { totalItems > 0 }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let mealPlan = try await MealPlanStorageService.currentMealPlan(),
                  let list = try await GroceryListStorageService.get(byMealPlanId: mealPlan.id) else {
                groceryList = nil
                groupedItems = []
                return
            }
            groceryList = list
            regroup()
        } catch {
            handleError(error, context: ErrorContext(location: "GroceryListScreen", action: "load"))
            errorMessage = NetworkErrorClassifier.isNetworkError(error) ? NetworkConfig.offlineMessage : "Failed to load grocery list"
        }
    }

    func isExpanded(_ category: String) -> Bool {
        !collapsedCategories.contains(category)
    }

    func toggleExpanded(_ category: String) {
        if collapsedCategories.contains(category) {
            collapsedCategories.remove(category)
        } else {
            collapsedCategories.insert(category)
        }
    }

    func toggleItem(category: String, name: String) async {
        guard var list = groceryList,
              let index = list.items.firstIndex(where: { $0.category == category && $0.name == name }) else { return }
        list.items[index].checked.toggle()
        groceryList = list
        regroup()
        await persist(list)
    }

    /// Only items still unchecked — a shared list is for someone else to go buy, so
    /// anything already checked off is done and has nothing to contribute. Dropping
    /// the per-item checkbox prefix too: it rendered as a broken tofu box in at least
    /// one share target (confirmed live), and a plain shared text list has no way for
    /// the recipient to actually check it off anyway, so it was purely decorative.
    func shareText() -> String {
        var text = "🛒 My Grocery List:\n\n"
        for (category, items) in groupedItems {
            let unchecked = items.filter { !$0.checked }
            guard !unchecked.isEmpty else { continue }
            text += "📋 \(category):\n"
            for item in unchecked {
                var amountText = ""
                if let amount = item.amount {
                    let amountString = amount.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(amount)) : String(amount)
                    amountText = " (\(amountString) \(item.unit ?? ""))"
                }
                text += "\(item.name)\(amountText)\n"
            }
            text += "\n"
        }
        return text
    }

    /// Mirrors the grouping in fetchGroceryList: buckets items by category, preserving
    /// each category's first-appearance order in the stored item array.
    private func regroup() {
        guard let groceryList else {
            groupedItems = []
            return
        }
        var order: [String] = []
        var buckets: [String: [GroceryItem]] = [:]
        for item in groceryList.items {
            if buckets[item.category] == nil {
                buckets[item.category] = []
                order.append(item.category)
            }
            buckets[item.category]?.append(item)
        }
        groupedItems = order.map { ($0, buckets[$0] ?? []) }
    }

    private func persist(_ list: GroceryList) async {
        do {
            try await GroceryListStorageService.update(list)
        } catch {
            handleError(error, context: ErrorContext(location: "GroceryListScreen", action: "persistToggle"))
        }
    }
}
