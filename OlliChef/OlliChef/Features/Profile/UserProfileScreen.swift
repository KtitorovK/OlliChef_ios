import FirebaseAuth
import SwiftUI

/// Ported from UserProfileScreen.tsx and its AppProfile styles directly — matching the
/// RN app's actual visual design (plain grouped sections with no card background, filled
/// colored buttons) rather than substituting a native-iOS reinterpretation. Save/trial/
/// restore/manage-subscription/logout all use brandAction (interactive controls);
/// deleteButton = statusError, clearChatButton = statusWarning.
/// The RN screen's dietary-preferences fields on `UserProfile` are never actually shown
/// here — verified, not an oversight — so this doesn't add editing for them either.
struct UserProfileScreen: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var subscriptionState: SubscriptionState
    @EnvironmentObject private var tabRouter: TabRouter
    @StateObject private var viewModel = UserProfileViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var metrics: AppMetrics { AppMetrics(horizontalSizeClass: horizontalSizeClass) }

    @State private var showingClearChatConfirm = false
    @State private var showingLogoutConfirm = false
    @State private var showingDeleteAccountConfirm = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    private var status: SubscriptionStatusInfo? { subscriptionState.status }
    private var hasAccess: Bool { subscriptionState.hasAccess }
    private var isGrace: Bool { status?.state == .grace }
    private var isTrial: Bool { status?.state == .active && status?.isTrial == true }
    private var willAutoRenew: Bool { status?.willAutoRenew ?? false }
    private var isSubscriptionActive: Bool { status?.state == .active }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                accountInformationSection
                subscriptionSection
                accountActionsSection
            }
            .padding(AppSpacing.contentPadding)
            .frame(maxWidth: metrics.formContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AppColor.surfaceBody)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh(subscriptionState: subscriptionState) }
        .task { await viewModel.load() }
        .alert(
            viewModel.alert?.title ?? "",
            isPresented: Binding(
                get: { viewModel.alert != nil },
                set: { if !$0 { viewModel.alert = nil } }
            ),
            presenting: viewModel.alert
        ) { _ in
            Button("OK") { viewModel.alert = nil }
        } message: { alert in
            Text(alert.message)
        }
        .alert("Clear Chat History", isPresented: $showingClearChatConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { Task { await viewModel.clearChatHistory(router: tabRouter) } }
        } message: {
            Text("Are you sure you want to clear your chat history? This action cannot be undone.")
        }
        .alert("Logout", isPresented: $showingLogoutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Logout", role: .destructive) { viewModel.signOut(authState: authState) }
        } message: {
            Text("Are you sure you want to logout?")
        }
        .alert("Delete Account", isPresented: $showingDeleteAccountConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await viewModel.deleteAccount() } }
        } message: {
            Text("Are you sure you want to delete your account? This action cannot be undone. Your data will be preserved for analytics purposes but will be anonymized.")
        }
    }

    // MARK: - Account Information

    private var accountInformationSection: some View {
        sectionContainer(title: "Account Information") {
            fieldRow(label: "Email", value: authState.user?.email ?? "Not available")

            VStack(alignment: .leading, spacing: 4) {
                Text("Display Name")
                    .font(AppTypography.body.weight(.medium))
                    .foregroundStyle(AppColor.textSecondary)

                if viewModel.isEditingDisplayName {
                    TextField("Enter display name", text: $viewModel.displayName)
                        .padding(12)
                        .background(AppColor.surfaceCard)
                        .overlay(RoundedRectangle(cornerRadius: AppRadius.small).stroke(AppColor.divider, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))

                    HStack(spacing: 8) {
                        filledButton("Save", color: AppColor.brandAction) {
                            Task { await viewModel.saveDisplayName() }
                        }
                        outlinedButton("Cancel") {
                            viewModel.cancelEditingDisplayName()
                        }
                    }
                    .disabled(viewModel.isSavingDisplayName)
                } else {
                    HStack {
                        Text(viewModel.displayName.isEmpty ? "Not set" : viewModel.displayName)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        Button("Edit") { viewModel.beginEditingDisplayName() }
                            .font(AppTypography.body.weight(.medium))
                            .foregroundStyle(AppColor.brandAction)
                    }
                }
            }
        }
    }

    // MARK: - Subscription

    @ViewBuilder
    private var subscriptionSection: some View {
        sectionContainer(title: "Subscription") {
            fieldRow(label: "Plan", value: "Basic")
            fieldRow(label: "Status", value: statusText, valueColor: statusColor)

            if isTrial, let expiresAt = status?.expiresAt {
                fieldRow(label: "Trial ends", value: Self.dateFormatter.string(from: expiresAt))
                if let productInfo = viewModel.productInfo {
                    fieldRow(label: "Then", value: "\(productInfo.displayPrice)/month")
                }
            }

            if hasAccess, !isTrial, willAutoRenew, let expiresAt = status?.expiresAt {
                fieldRow(label: "Renews on", value: Self.dateFormatter.string(from: expiresAt))
            }

            if hasAccess, !isTrial, !willAutoRenew, let expiresAt = status?.expiresAt {
                fieldRow(label: "Access ends on", value: Self.dateFormatter.string(from: expiresAt), valueColor: AppColor.statusWarning)
            }

            if isGrace {
                Text("Update your payment method in Apple Subscriptions to keep access.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.statusWarning)
            }

            if hasAccess || isGrace {
                outlinedButton("Manage Subscription", textColor: AppColor.brandAction, borderColor: AppColor.brandAction) {
                    Task { await viewModel.manageSubscription() }
                }
            }

            if !hasAccess, !isGrace, let productInfo = viewModel.productInfo {
                fieldRow(
                    label: "Price",
                    value: productInfo.isEligibleForIntroOffer
                        ? "14-day free trial, then \(productInfo.displayPrice)/month"
                        : "\(productInfo.displayPrice)/month"
                )
            }

            if !hasAccess, !isGrace {
                if let productInfo = viewModel.productInfo, productInfo.isEligibleForIntroOffer {
                    filledButton(
                        viewModel.isPurchasing ? "Processing..." : "Start your 14-day free trial",
                        color: AppColor.brandAction
                    ) {
                        Task { await viewModel.purchase(subscriptionState: subscriptionState) }
                    }
                    .disabled(viewModel.isPurchasing)

                    Button {
                        Task { await viewModel.restorePurchases(subscriptionState: subscriptionState) }
                    } label: {
                        Text(viewModel.isRestoring ? "Restoring..." : "Restore Purchases")
                            .font(.footnote)
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(viewModel.isRestoring)
                } else if viewModel.productInfo != nil {
                    filledButton(
                        viewModel.isRestoring ? "Restoring..." : "Restore Purchases",
                        color: AppColor.brandAction
                    ) {
                        Task { await viewModel.restorePurchases(subscriptionState: subscriptionState) }
                    }
                    .disabled(viewModel.isRestoring)
                }
            }
        }
    }

    private var statusText: String {
        if subscriptionState.isLoading { return "Checking..." }
        if isGrace { return "Billing issue" }
        if isTrial { return "Trial active" }
        if hasAccess && !willAutoRenew { return "Canceled" }
        if hasAccess { return "Active" }
        return "Not active"
    }

    private var statusColor: Color {
        if isGrace { return AppColor.statusWarning }
        if hasAccess { return AppColor.statusSuccess }
        return AppColor.statusError
    }

    // MARK: - Account Actions

    private var accountActionsSection: some View {
        sectionContainer(title: "Account Actions") {
            filledButton(
                viewModel.isClearingChat ? "Clearing..." : "Clear Chat History",
                color: AppColor.statusWarning
            ) {
                showingClearChatConfirm = true
            }
            .disabled(viewModel.isClearingChat)

            filledButton("Logout", color: AppColor.brandAction) {
                showingLogoutConfirm = true
            }

            // Deliberately not a filled button like the others, per explicit user
            // preference — a quieter link-style treatment for the most destructive
            // action, rather than matching RN's actual filled-red deleteButton style.
            Button {
                showingDeleteAccountConfirm = true
            } label: {
                Text(isSubscriptionActive ? "Delete Account (Cancel Subscription First)" : "Delete Account")
                    .font(AppTypography.body.weight(.medium))
                    .foregroundStyle(isSubscriptionActive ? AppColor.textSecondary : AppColor.statusError)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .disabled(isSubscriptionActive)

            if isSubscriptionActive {
                Text("You must cancel your subscription before deleting your account")
                    .font(AppTypography.smallMetadata)
                    .foregroundStyle(AppColor.textSecondary)
                    .italic()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Shared building blocks (mirroring AppProfile's styles exactly)

    private func sectionContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(AppTypography.cardTitle.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldRow(label: String, value: String, valueColor: Color = AppColor.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AppTypography.body.weight(.medium))
                .foregroundStyle(AppColor.textSecondary)
            Text(value)
                .font(AppTypography.body)
                .foregroundStyle(valueColor)
        }
    }

    /// Mirrors AppProfile.button + a color, with textOnBrand (white) label text — matches
    /// every real filled button in the RN screen (save/trial/restore/logout/delete/clear).
    private func filledButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.body.weight(.medium))
                .foregroundStyle(AppColor.textOnBrand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
    }

    /// Mirrors cancelButton/manageSubscription's outlined style. RN's actual `cancelButton`
    /// reuses the same white `buttonText` color as filled buttons, which renders illegibly
    /// on its light `surface` fill — not replicated here, since that's a real contrast bug
    /// in the source, not a deliberate design choice; textPrimary is used instead so Cancel
    /// stays readable.
    private func outlinedButton(_ title: String, textColor: Color = AppColor.textPrimary, borderColor: Color = AppColor.divider, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.body.weight(.medium))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .background(AppColor.surfaceCard)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.small).stroke(borderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
    }
}
