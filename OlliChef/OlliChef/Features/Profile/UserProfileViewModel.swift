import Combine
import Foundation

@MainActor
final class UserProfileViewModel: ObservableObject {
    @Published var displayName = ""
    @Published var isEditingDisplayName = false
    @Published var isSavingDisplayName = false

    @Published var productInfo: SubscriptionProductInfo?
    @Published var isPurchasing = false
    @Published var isRestoring = false
    @Published var isClearingChat = false

    @Published var alert: (title: String, message: String)?

    func load() async {
        do {
            if let profile = try await UserProfileService.getUserProfile(), let name = profile.displayName {
                displayName = name
            }
        } catch {
            handleError(error, context: ErrorContext(location: "UserProfileScreen", action: "load_user_profile"))
        }
        await loadProductInfo()
    }

    func loadProductInfo() async {
        productInfo = try? await StoreKitService.shared.fetchProduct()
    }

    func refresh(subscriptionState: SubscriptionState) async {
        async let refreshResult = subscriptionState.refresh()
        async let productTask: Void = loadProductInfo()
        _ = await refreshResult
        await productTask
    }

    // MARK: - Display name

    func beginEditingDisplayName() {
        isEditingDisplayName = true
    }

    func cancelEditingDisplayName() {
        isEditingDisplayName = false
    }

    func saveDisplayName() async {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alert = ("Error", "Display name cannot be empty")
            return
        }

        isSavingDisplayName = true
        defer { isSavingDisplayName = false }

        do {
            try await UserProfileService.updateDisplayName(trimmed)
            isEditingDisplayName = false
            alert = ("Success", "Display name updated successfully")
        } catch {
            handleError(error, context: ErrorContext(location: "UserProfileScreen", action: "save_display_name"))
            alert = NetworkErrorClassifier.isNetworkError(error)
                ? ("No Internet Connection", NetworkConfig.offlineMessage)
                : ("Error", "Failed to update display name. Please try again.")
        }
    }

    // MARK: - Subscription actions

    func purchase(subscriptionState: SubscriptionState) async {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let outcome = try await StoreKitService.shared.purchase()
            switch outcome {
            case .success:
                let hasAccess = await subscriptionState.refresh()
                if !hasAccess {
                    alert = ("Processing", "Your purchase is being processed. Please wait a moment.")
                }
            case .cancelled:
                alert = ("Cancelled", "Purchase was cancelled")
            case .pending:
                alert = ("Pending", "Purchase is pending approval")
            }
        } catch {
            handleError(error, context: ErrorContext(location: "UserProfileScreen", action: "purchase_subscription"))
            alert = ("Error", "Purchase failed. Please try again.")
        }
    }

    func restorePurchases(subscriptionState: SubscriptionState) async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            _ = try await StoreKitService.shared.restore()
            let hasAccess = await subscriptionState.refresh()
            if !hasAccess {
                alert = ("No Active Subscription", "No active subscription was found.")
            }
        } catch {
            handleError(error, context: ErrorContext(location: "UserProfileScreen", action: "restore_purchases"))
            alert = ("Restore Failed", "Unable to restore purchases. Please try again.")
        }
    }

    func manageSubscription() async {
        do {
            try await StoreKitService.shared.showManageSubscriptions()
        } catch {
            handleError(error, context: ErrorContext(location: "UserProfileScreen", action: "open_manage_subscription"))
            alert = ("Manage Subscription", "Unable to open subscription management automatically. Please open App Store > Account > Subscriptions.")
        }
    }

    // MARK: - Account actions

    func clearChatHistory() async {
        isClearingChat = true
        defer { isClearingChat = false }

        do {
            _ = try await ChatService.shared.resetChatConversation()
            alert = ("Success", "Chat history has been cleared successfully")
        } catch {
            handleError(error, context: ErrorContext(location: "UserProfileScreen", action: "clear_chat_history"))
            alert = NetworkErrorClassifier.isNetworkError(error)
                ? ("No Internet Connection", NetworkConfig.offlineMessage)
                : ("Error", "Failed to clear chat history. Please try again.")
        }
    }

    func signOut(authState: AuthState) {
        do {
            try authState.signOut()
        } catch {
            handleError(error, context: ErrorContext(location: "UserProfileScreen", action: "logout"))
            alert = ("Error", "Failed to logout")
        }
    }

    /// Mirrors proceedWithAccountDeletion. The dead `isAccountDeletionAllowed()` check
    /// RN calls before this (verified elsewhere to always return `{allowed: true}`, so
    /// it never actually blocks anything) is skipped — the real gate is the button's
    /// own disabled state in the view, matching `subscriptionStatus?.status === 'active'`.
    func deleteAccount() async {
        do {
            try await UserProfileService.deleteAccount()
            alert = ("Account Deleted", "Your account has been deleted successfully. You will be signed out.")
            // RootView's own auth-state observation handles navigation once the user
            // becomes unauthenticated, matching App.tsx's comment on this exact point.
        } catch {
            handleError(error, context: ErrorContext(location: "UserProfileScreen", action: "delete_account"))
            alert = ("Error", "Failed to delete account. Please try again.")
        }
    }
}
