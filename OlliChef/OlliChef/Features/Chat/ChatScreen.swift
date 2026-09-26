import SwiftUI

/// Ported from ChatScreen.tsx: message list, meal-plan card rendering inline in chat,
/// and the accept flow. Visual polish (bubble shapes, markdown, streaming) is deferred —
/// this phase is the AI plumbing and Firestore contract, not final design.
struct ChatScreen: View {
    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject private var tabRouter: TabRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @FocusState private var isComposerFocused: Bool
    private var metrics: AppMetrics { AppMetrics(horizontalSizeClass: horizontalSizeClass) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.contentPadding) {
                        ForEach(viewModel.messages) { message in
                            messageView(message).id(message.id)
                        }
                        if viewModel.isThinking {
                            ProgressView()
                                .tint(AppColor.brandAccent)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, AppSpacing.xs)
                        }
                        // A stable anchor past both the last message and the thinking
                        // spinner — scrolling to the last message's own id left the
                        // spinner sitting below the fold (its appearance doesn't change
                        // messages.count, the only thing that triggered a scroll before),
                        // and long content (a big MealPlanCard) can still be mid-layout
                        // right when a scroll fires, which a plain post-append scrollTo
                        // can undershoot on.
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(AppSpacing.contentPadding)
                    .frame(maxWidth: metrics.chatContentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: viewModel.messages.count) { scrollToBottom(proxy) }
                .onChange(of: viewModel.isThinking) { scrollToBottom(proxy) }
                // Tapping anywhere in the message list should collapse the composer's
                // keyboard, same as tapping outside a text field anywhere else in the
                // app — a plain tap gesture here doesn't compete with the ScrollView's
                // own drag-to-scroll gesture.
                .contentShape(Rectangle())
                .onTapGesture { isComposerFocused = false }
            }

            Divider()

            composer
        }
        .background(AppColor.surfaceBody)
        .task { await viewModel.loadHistory() }
        .onChange(of: tabRouter.chatHistoryClearedAt) {
            Task { await viewModel.resetAfterExternalClear() }
        }
        .alert("Error", isPresented: .constant(viewModel.acceptError != nil), presenting: viewModel.acceptError) { _ in
            Button("OK") { viewModel.acceptError = nil }
        } message: { message in
            Text(message)
        }
        .overlay {
            if viewModel.isAccepting {
                acceptingOverlay
            }
        }
    }

    /// Composer: SurfaceCard pill with a custom TextTertiary placeholder (a plain
    /// TextField's own placeholder can't be recolored directly), 52pt minimum height,
    /// and a BrandAction send control with a real 44x44 tap target regardless of the
    /// glyph's own visual size.
    private var composer: some View {
        HStack(spacing: AppSpacing.xs) {
            ZStack(alignment: .leading) {
                if viewModel.inputText.isEmpty {
                    Text("Type your message...")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textTertiary)
                }
                TextField("", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(AppTypography.body)
                    .id(viewModel.composerResetToken)
                    .focused($isComposerFocused)
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(minHeight: metrics.textInputHeight)
            .background(AppColor.surfaceCard)
            // Capsule()'s radius is always half the view's own height, which reads as a
            // pill at the field's single-line minHeight but balloons into an odd bulging
            // shape once multi-line text grows it taller. A fixed radius stays a normal
            // rounded rectangle at any height, and still looks like a pill at minHeight
            // since AppRadius.large (24) is close to half of textInputHeight (52).
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))

            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(AppColor.brandAction)
                    .frame(minWidth: metrics.minimumTapTarget, minHeight: metrics.minimumTapTarget)
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isThinking)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, AppSpacing.contentPadding)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColor.surfaceHeader.ignoresSafeArea(edges: .bottom))
    }

    /// Scrolls twice: immediately, and again after the next runloop tick. A big
    /// MealPlanCard (or the thinking spinner appearing) can still be mid-layout the
    /// instant messages.count/isThinking flips, so a single scrollTo right then can
    /// undershoot; the deferred follow-up catches the settled layout.
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    /// Mirrors the "Meal plan acceptance blocking overlay": a dimmed full-screen scrim
    /// behind a small card with a 3-step progress list, so accepting a plan doesn't just
    /// silently swap the button for a spinner — a step this port had dropped entirely.
    private var acceptingOverlay: some View {
        ZStack {
            AppColor.textPrimary.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.sm) {
                Text("Saving your plan...")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColor.brandForest)
                    .multilineTextAlignment(.center)

                ProgressView()
                    .tint(AppColor.brandAccent)

                VStack(spacing: AppSpacing.sm) {
                    acceptStepRow(number: 1, icon: "1", label: "Saving meal plan")
                    acceptStepRow(number: 2, icon: "2", label: "Building grocery list")
                    acceptStepRow(number: 3, icon: "✓", label: "All done!")
                }
                .padding(.top, AppSpacing.xxs)

                Text("This takes a few seconds")
                    .font(AppTypography.smallMetadata)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, AppSpacing.xxs)
            }
            .padding(.vertical, AppSpacing.lg)
            .padding(.horizontal, AppSpacing.xl)
            .frame(width: metrics.isRegular ? 320 : 240)
            .background(AppColor.surfaceCard)
            // Matches the composer, bubbles, and meal plan card's rounding.
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
            .shadow(color: AppColor.textPrimary.opacity(0.2), radius: 16, y: 8)
        }
        .transition(.opacity)
    }

    private func acceptStepRow(number: Int, icon: String, label: String) -> some View {
        let status = viewModel.acceptStep.status(forStep: number)
        let isHighlighted = status != .inactive
        let textColor: Color = status == .inactive ? AppColor.textSecondary : status == .done ? AppColor.brandAccent : AppColor.textPrimary

        return HStack(spacing: AppSpacing.xs) {
            Circle()
                .strokeBorder(isHighlighted ? AppColor.brandAccent : AppColor.textSecondary, lineWidth: 2)
                .background(Circle().fill(isHighlighted ? AppColor.brandAccent : .clear))
                .frame(width: 18, height: 18)
                .overlay {
                    Text(icon)
                        .font(AppTypography.smallMetadata)
                        .foregroundStyle(isHighlighted ? AppColor.textOnBrand : AppColor.textSecondary)
                }
            Text(label)
                .font(AppTypography.smallMetadata)
                .foregroundStyle(textColor)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessageItem) -> some View {
        if let mealPlan = message.mealPlan {
            MealPlanCard(mealPlan: mealPlan, isAccepting: viewModel.isAccepting) {
                Task { await viewModel.acceptMealPlan(mealPlan, router: tabRouter) }
            }
        } else {
            HStack {
                if message.role == .user { Spacer(minLength: 40) }
                Text(message.error ?? message.content ?? "")
                    .font(AppTypography.body)
                    .foregroundStyle(message.role == .user ? AppColor.textOnBrand : AppColor.textPrimary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(message.role == .user ? AppColor.brandAction : AppColor.surfaceCard)
                    // Matches the composer input's rounding (AppRadius.large) instead
                    // of the smaller card radius, so bubbles and the input read as the
                    // same rounded-pill family instead of two different shapes.
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
                if message.role == .assistant { Spacer(minLength: 40) }
            }
        }
    }
}

/// Ported from ChatScreen.tsx's inline meal-plan bubble (AppChatMealPlanNew styles):
/// one card holding every day, each day listing its meals with a Pexels thumbnail and
/// inline nutrition, tap-through to the recipe, then an intro line + Accept Plan button.
private struct MealPlanCard: View {
    let mealPlan: MealPlan
    let isAccepting: Bool
    let onAccept: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // See MealPlanScreen's MealTapActionKey: on iPad, a NavigationLink(value:) inside
    // this NavigationSplitView's detail column silently fails to reach the
    // navigationDestination declared on an ancestor (a real, unresolved SwiftUI bug on
    // this SDK) — confirmed live here too ("no matching navigationDestination
    // declaration visible"). MealPlanScreen's own meal cards already work around it via
    // this same environment value; this card just hadn't been updated to check it.
    @Environment(\.mealTapAction) private var mealTapAction
    private var metrics: AppMetrics { AppMetrics(horizontalSizeClass: horizontalSizeClass) }

    @ViewBuilder
    private func mealLink<Label: View>(_ meal: Meal, @ViewBuilder label: () -> Label) -> some View {
        if let mealTapAction {
            Button { mealTapAction(meal) } label: { label() }
        } else {
            NavigationLink(value: meal) { label() }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            ForEach(mealPlan.days, id: \.date) { day in
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("\(day.shortWeekdayLabel) — \(day.meals.count) Meal\(day.meals.count == 1 ? "" : "s")")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColor.textPrimary)
                    ForEach(day.meals) { meal in
                        mealLink(meal) {
                            mealRow(meal)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                    }
                }
            }

            VStack(spacing: AppSpacing.xs) {
                Text("Your plan is ready!\nIf you like it, click:")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                Button(action: onAccept) {
                    if isAccepting {
                        ProgressView().tint(AppColor.textOnBrand)
                    } else {
                        Text("Accept Plan")
                    }
                }
                .font(AppTypography.button)
                .foregroundStyle(AppColor.textOnBrand)
                .padding(.horizontal, AppSpacing.buttonHorizontal)
                .frame(minHeight: metrics.primaryButtonHeight)
                .background(AppColor.brandAction)
                .clipShape(Capsule())
                .disabled(isAccepting)
                .hoverEffect(.highlight)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(AppSpacing.contentPadding)
        .background(AppColor.surfaceCard)
        // Matches the composer input's rounding and the message bubbles above, rather
        // than the smaller generic card radius — one consistent rounded-pill family
        // across every shape on this screen.
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        .overlay {
            // surfaceCard (#fff) sits on a near-identical cream page background
            // (surfaceBody, #fefdf2) — the same 1px-apart colors RN itself uses — so
            // without a visible edge the rounded corners all but disappear. RN leans on
            // this card floating over a plain screen; here it floats inside a scrolling
            // chat thread, where that lack of contrast reads as a layout bug rather than
            // an intentional flat design, so a hairline border makes the shape legible.
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.divider, lineWidth: 1)
        }
        // On iPad's much wider detail column this card had no cap at all and stretched
        // edge-to-edge, unlike every other message bubble in the thread — capping it
        // keeps it reading as a contained card. iPhone keeps filling the available
        // width since it was never too wide there.
        .frame(maxWidth: metrics.isRegular ? metrics.formContentMaxWidth : .infinity, alignment: .leading)
    }

    private func mealRow(_ meal: Meal) -> some View {
        HStack(spacing: AppSpacing.xs) {
            MealImageView(
                mealName: meal.name,
                size: .small,
                overrideBox: (metrics.chatThumbnailSize, metrics.chatThumbnailSize, AppRadius.small)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(AppTypography.body.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                if let nutrition = meal.nutritionInfo, !nutrition.summaryText.isEmpty {
                    Text(nutrition.summaryText)
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }
}
