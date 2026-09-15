import Foundation

/// Ported from src/types/grocery.ts.
struct GroceryItem: Codable, Hashable {
    var name: String
    var category: String
    var amount: Double?
    var unit: String?
    var checked: Bool
    var notes: String?
}

/// Ported from src/types/grocery.ts's GroceryList: one document per meal plan,
/// keyed by `mealPlanId` — replaced wholesale (delete + recreate) on every
/// "Accept Plan", never merged across weeks.
struct GroceryList: Codable, Hashable, Identifiable {
    var id: String
    var mealPlanId: String
    var items: [GroceryItem]
    var createdAt: String
    var updatedAt: String
}
