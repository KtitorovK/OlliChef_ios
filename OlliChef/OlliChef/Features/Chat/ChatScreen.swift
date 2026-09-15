import SwiftUI

/// Ported from ChatScreen.tsx: message list, meal-plan card rendering inline in chat,
/// and the accept flow. Visual polish (bubble shapes, markdown, streaming) is deferred —
/// this phase is the AI plumbing and Firestore contract, not final design.
struct ChatScreen: View {
    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject private var tabRouter: TabRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isRegular: Bool { horizontalSizeClass == .regular }

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
                                .tint(AppColor.brandPrimary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(AppSpacing.contentPadding)
                }
                .onChange(of: viewModel.messages.count) {
                    if let last = viewModel.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Type your message...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppColor.cardSurface)
                    .clipShape(Capsule())

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(AppColor.brandPrimary)
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isThinking)
            }
            .padding(AppSpacing.contentPadding)
            .background(AppColor.surfaceHeader.ignoresSafeArea(edges: .bottom))
        }
        .background(AppColor.surfaceBody)
        .task { await viewModel.loadHistory() }
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

    /// Mirrors the "Meal plan acceptance blocking overlay": a dimmed full-screen scrim
    /// behind a small card with a 3-step progress list, so accepting a plan doesn't just
    /// silently swap the button for a spinner — a step this port had dropped entirely.
    private var acceptingOverlay: some View {
        ZStack {
            AppColor.textPrimary.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Saving your plan...")
                    .font(.system(size: isRegular ? 22 : 18))
                    .foregroundStyle(AppColor.brandSecondary)
                    .multilineTextAlignment(.center)

                ProgressView()
                    .tint(AppColor.brandPrimary)

                VStack(spacing: 12) {
                    acceptStepRow(number: 1, icon: "1", label: "Saving meal plan")
                    acceptStepRow(number: 2, icon: "2", label: "Building grocery list")
                    acceptStepRow(number: 3, icon: "✓", label: "All done!")
                }
                .padding(.top, 4)

                Text("This takes a few seconds")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 24)
            .frame(width: isRegular ? 320 : 240)
            .background(AppColor.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
            .shadow(color: AppColor.textPrimary.opacity(0.2), radius: 16, y: 8)
        }
        .transition(.opacity)
    }

    private func acceptStepRow(number: Int, icon: String, label: String) -> some View {
        let status = viewModel.acceptStep.status(forStep: number)
        let isHighlighted = status != .inactive
        let textColor: Color = status == .inactive ? AppColor.textSecondary : status == .done ? AppColor.brandPrimary : AppColor.textPrimary

        return HStack(spacing: 10) {
            Circle()
                .strokeBorder(isHighlighted ? AppColor.brandPrimary : AppColor.textSecondary, lineWidth: 2)
                .background(Circle().fill(isHighlighted ? AppColor.brandPrimary : .clear))
                .frame(width: 18, height: 18)
                .overlay {
                    Text(icon)
                        .font(.system(size: 11))
                        .foregroundStyle(isHighlighted ? AppColor.textOnBrand : AppColor.textSecondary)
                }
            Text(label)
                .font(.system(size: 14))
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(message.role == .user ? AppColor.brandPrimary : AppColor.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(mealPlan.days, id: \.date) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(day.shortWeekdayLabel) — \(day.meals.count) Meal\(day.meals.count == 1 ? "" : "s")")
                        .font(AppTypography.subhead.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    ForEach(day.meals) { meal in
                        NavigationLink(value: meal) {
                            mealRow(meal)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                    }
                }
            }

            VStack(spacing: 8) {
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
                .font(AppTypography.body.weight(.bold))
                .foregroundStyle(AppColor.textOnBrand)
                .padding(.horizontal, AppSpacing.buttonHorizontal)
                .padding(.vertical, 10)
                .background(AppColor.brandPrimary)
                .clipShape(Capsule())
                .disabled(isAccepting)
                .hoverEffect(.highlight)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(AppColor.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
        .overlay {
            // cardSurface (#fff) sits on a near-identical cream page background
            // (surfaceBody, #fefdf2) — the same 1px-apart colors RN itself uses — so
            // without a visible edge the rounded corners all but disappear. RN leans on
            // this card floating over a plain screen; here it floats inside a scrolling
            // chat thread, where that lack of contrast reads as a layout bug rather than
            // an intentional flat design, so a hairline border makes the shape legible.
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .stroke(AppColor.border, lineWidth: 1)
        }
    }

    private func mealRow(_ meal: Meal) -> some View {
        HStack(spacing: 8) {
            MealImageView(mealName: meal.name, size: .small, overrideBox: (32, 32, 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(AppTypography.body.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                if let nutrition = meal.nutritionInfo, !nutrition.summaryText.isEmpty {
                    Text(nutrition.summaryText)
                        .font(AppTypography.label)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }
}
