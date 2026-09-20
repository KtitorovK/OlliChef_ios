import SwiftUI

private enum LegalURLs {
    static let privacyPolicy = URL(string: "https://www.notion.so/Privacy-Policy-24855c46acf08017b9a5d2ccc5db95aa?source=copy_link")!
    static let termsOfUse = URL(string: "https://www.notion.so/Terms-of-Use-24855c46acf080b48dd7dd153a8c6990?source=copy_link")!
}

private struct PaywallBenefit: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
}

// Wording locked in the KB (§3, Subscription & Monetisation, "Paywall copy
// (founder-approved)") — keep in sync with that page, not with local taste.
// Icons reuse the app's own tab-bar iconset (TabRouter.swift) rather than generic SF
// Symbols, so the paywall reads as the same product as the tabs behind it. There's no
// dedicated "Recipes" icon in the set — IconChat stands in for it since recipes are
// the AI/chat-generated content, same association as the Chat tab itself.
private let benefits: [PaywallBenefit] = [
    PaywallBenefit(id: "meals", icon: "IconMealPlan", title: "Meals", detail: "Weekly meal plans tailored to your diet and schedule"),
    PaywallBenefit(id: "recipes", icon: "IconChat", title: "Recipes", detail: "Step-by-step recipes for every meal, powered by AI"),
    PaywallBenefit(id: "grocery", icon: "IconGroceries", title: "Grocery", detail: "Auto-generated grocery lists so you never wonder what to buy"),
]

/// Ported from PaywallScreen.tsx: shown in place of the whole tab navigator whenever
/// the user lacks an active subscription — a hard block, not a dismissible sheet.
///
/// Structure follows the standard high-converting paywall shape (visual proof of
/// value → outcome headline → benefit bullets → single CTA with billing terms
/// attached) rather than the original bare title/button screen — there's only ever
/// one plan (KB §3: single $9.99/mo tier, no annual/family/lifetime at v1), so this
/// doesn't need plan-comparison cards, just a plan worth wanting.
struct PaywallScreen: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var subscriptionState: SubscriptionState
    @StateObject private var viewModel = PaywallViewModel()
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIPad: Bool { horizontalSizeClass == .regular }
    // Narrower than the app's usual form/content caps — a paywall reads best as a
    // tight single column even on iPad's much wider detail column.
    private let maxContentWidth: CGFloat = 480

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Cropped tight on the plan-ready moment (a full day's meals plus the
                // "Accept Plan" button) rather than a shrunk full-screen mockup — the
                // single most convincing proof of "a full week, planned in seconds"
                // the app has, and it needs to read at a glance, not be squinted at.
                Image(isIPad ? "PaywallHeroIpad" : "PaywallHero")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                    .shadow(color: AppColor.textPrimary.opacity(0.08), radius: 8, y: 4)
                    .padding(.top, AppSpacing.lg)

                VStack(spacing: AppSpacing.sm) {
                    Text("Your personal AI chef. Every week.")
                        .font(AppTypography.pageTitle)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Chat your way to a full weekly meal plan — with recipes and a ready-to-shop grocery list, generated in seconds.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    ForEach(benefits) { benefit in
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            Image(benefit.icon)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(AppColor.brandAction)
                                .frame(width: 24, height: 24)
                                .padding(.top, 2)
                            (Text("\(benefit.title): ").font(AppTypography.body.weight(.semibold))
                                + Text(benefit.detail).font(AppTypography.body))
                                .foregroundStyle(AppColor.textPrimary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: AppSpacing.sm) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(AppColor.brandAction)
                            .padding(.vertical, AppSpacing.md)
                    } else {
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
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColor.brandAction)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                        .disabled(viewModel.isPurchasing)
                        .opacity(viewModel.isPurchasing ? 0.5 : 1)

                        if let legalFootnote = viewModel.legalFootnote {
                            Text(legalFootnote)
                                .font(AppTypography.smallMetadata)
                                .foregroundStyle(AppColor.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.top, AppSpacing.xs)

                VStack(spacing: AppSpacing.md) {
                    // "Start trial" and "Restore" aren't two equally-valid choices for
                    // the same person — they're the right action for two different
                    // people (someone new vs. someone who's subscribed before). Apple
                    // requires Restore stay accessible on this screen at all times
                    // (isEligibleForTrial is only a StoreKit intro-offer signal, not
                    // proof this Apple ID has no purchase history — family sharing, a
                    // reinstall, or a past non-trial purchase can all make Restore the
                    // right action even when it reports true). So for a likely-new user
                    // Restore doesn't disappear, it just moves down into the small
                    // utility row with the legal links below, where it reads as "if you
                    // need it" rather than a real second choice next to the primary CTA.
                    if viewModel.isEligibleForTrial == false {
                        Button {
                            Task { await viewModel.restore(subscriptionState: subscriptionState) }
                        } label: {
                            if viewModel.isRestoring {
                                ProgressView().tint(AppColor.brandAction)
                            } else {
                                Text("Restore Purchases")
                            }
                        }
                        .font(AppTypography.body.weight(.medium))
                        .foregroundStyle(AppColor.brandAction)
                        .disabled(viewModel.isRestoring)
                        .opacity(viewModel.isRestoring ? 0.5 : 1)
                    }

                    HStack(spacing: AppSpacing.xs) {
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
                        if viewModel.isEligibleForTrial != false {
                            Text("·")
                            Button {
                                Task { await viewModel.restore(subscriptionState: subscriptionState) }
                            } label: {
                                if viewModel.isRestoring {
                                    ProgressView().tint(AppColor.textSecondary)
                                } else {
                                    Text("Restore Purchases").underline()
                                }
                            }
                            .disabled(viewModel.isRestoring)
                            .opacity(viewModel.isRestoring ? 0.5 : 1)
                        }
                    }
                    .font(AppTypography.smallMetadata)
                    .foregroundStyle(AppColor.textSecondary)

                    Button("Sign out") {
                        try? authState.signOut()
                    }
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textSecondary)
                }
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.lg)
            }
            .padding(.horizontal, AppSpacing.xxl)
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity)
        }
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
