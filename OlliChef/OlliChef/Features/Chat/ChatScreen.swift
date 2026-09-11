import SwiftUI

/// Ported from ChatScreen.tsx: message list, meal-plan card rendering inline in chat,
/// and the accept flow. Visual polish (bubble shapes, markdown, streaming) is deferred —
/// this phase is the AI plumbing and Firestore contract, not final design.
struct ChatScreen: View {
    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject private var tabRouter: TabRouter

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.contentPadding) {
                        ForEach(viewModel.messages) { message in
                            messageView(message).id(message.id)
                        }
                        if viewModel.isThinking {
                            ProgressView().padding(.vertical, 8)
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
            .background(AppColor.surfaceHeader)
        }
        .background(AppColor.surfaceBody)
        .task { await viewModel.loadWelcomeMessage() }
        .alert("Error", isPresented: .constant(viewModel.acceptError != nil), presenting: viewModel.acceptError) { _ in
            Button("OK") { viewModel.acceptError = nil }
        } message: { message in
            Text(message)
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
                    .font(.system(size: AppTypography.body))
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

private struct MealPlanCard: View {
    let mealPlan: MealPlan
    let isAccepting: Bool
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(mealPlan.days, id: \.date) { day in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(day.day ?? day.date) — \(day.meals.count) Meals")
                        .font(.system(size: AppTypography.subhead, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    ForEach(day.meals) { meal in
                        Text(meal.name)
                            .font(.system(size: AppTypography.body, weight: .medium))
                            .foregroundStyle(AppColor.textPrimary)
                    }
                }
            }

            Button(action: onAccept) {
                if isAccepting {
                    ProgressView().tint(AppColor.textOnBrand)
                } else {
                    Text("Accept Plan")
                }
            }
            .font(.system(size: AppTypography.body, weight: .bold))
            .foregroundStyle(AppColor.textOnBrand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(AppColor.brandPrimary)
            .clipShape(Capsule())
            .disabled(isAccepting)
        }
        .padding(14)
        .background(AppColor.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
    }
}
