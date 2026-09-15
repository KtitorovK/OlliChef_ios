import Testing
@testable import OlliChef

/// Mirrors ChatScreen.tsx's getStepStatus test matrix — the 3-step "Saving meal plan /
/// Building grocery list / All done!" progress popup shown while accepting a plan.
struct AcceptStepTests {
    @Test func savingStepOnlyStepOneIsActive() {
        #expect(AcceptStep.saving.status(forStep: 1) == .active)
        #expect(AcceptStep.saving.status(forStep: 2) == .inactive)
        #expect(AcceptStep.saving.status(forStep: 3) == .inactive)
    }

    @Test func groceryStepFirstIsDoneSecondIsActive() {
        #expect(AcceptStep.grocery.status(forStep: 1) == .done)
        #expect(AcceptStep.grocery.status(forStep: 2) == .active)
        #expect(AcceptStep.grocery.status(forStep: 3) == .inactive)
    }

    @Test func doneStepFirstTwoAreDoneThirdIsActive() {
        #expect(AcceptStep.done.status(forStep: 1) == .done)
        #expect(AcceptStep.done.status(forStep: 2) == .done)
        #expect(AcceptStep.done.status(forStep: 3) == .active)
    }
}
