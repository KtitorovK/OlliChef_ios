import SwiftUI

private enum LegalURLs {
    static let privacyPolicy = URL(string: "https://www.notion.so/Privacy-Policy-24855c46acf08017b9a5d2ccc5db95aa?source=copy_link")!
    static let termsOfUse = URL(string: "https://www.notion.so/Terms-of-Use-24855c46acf080b48dd7dd153a8c6990?source=copy_link")!
}

/// Ported from PaywallScreen.tsx: shown in place of the whole tab navigator whenever
/// the user lacks an active subscription — a hard block, not a dismissible sheet.
struct PaywallScreen: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var subscriptionState: SubscriptionState
    @StateObject private var viewModel = PaywallViewModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            VStack(spacing: 16) {
                Text("OlliChef Basic")
                    .font(AppTypography.title.weight(.bold))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Monthly subscription — meal planning and grocery list features.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)

                if viewModel.isLoading {
                    ProgressView()
                        .tint(AppColor.brandPrimary)
                        .padding(.vertical, 16)
                } else if let priceHint = viewModel.priceHint {
                    Text(priceHint)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.bottom, 16)
                }
            }

            Button {
                Task { await viewModel.subscribe(subscriptionState: subscriptionState) }
            } label: {
                if viewModel.isPurchasing {
                    ProgressView().tint(AppColor.textOnBrand)
                } else {
                    Text(viewModel.subscribeLabel)
                }
            }
            .font(AppTypography.body.weight(.semibold))
            .foregroundStyle(AppColor.textOnBrand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppColor.brandPrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
            .disabled(viewModel.isPurchasing || viewModel.isLoading)
            .opacity(viewModel.isPurchasing || viewModel.isLoading ? 0.5 : 1)
            .padding(.bottom, 4)

            Button {
                Task { await viewModel.restore(subscriptionState: subscriptionState) }
            } label: {
                if viewModel.isRestoring {
                    ProgressView().tint(AppColor.brandPrimary)
                } else {
                    Text("Restore Purchases")
                }
            }
            .font(AppTypography.body.weight(.medium))
            .foregroundStyle(AppColor.brandPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .disabled(viewModel.isRestoring)
            .opacity(viewModel.isRestoring ? 0.5 : 1)
            .padding(.bottom, 16)

            HStack(spacing: 8) {
                Button {
                    openURL(LegalURLs.privacyPolicy)
                } label: {
                    Text("Privacy Policy").underline()
                }
                Text("·")
                Button {
                    openURL(LegalURLs.termsOfUse)
                } label: {
                    Text("Terms of Use").underline()
                }
            }
            .font(AppTypography.caption)
            .foregroundStyle(AppColor.textSecondary)
            .padding(.bottom, 16)

            Button("Sign out") {
                try? authState.signOut()
            }
            .font(AppTypography.body)
            .foregroundStyle(AppColor.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.surfaceBody)
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
    }
}
