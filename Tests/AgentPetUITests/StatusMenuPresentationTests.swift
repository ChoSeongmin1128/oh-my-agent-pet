import AgentPetCore
import AgentPetUI
import XCTest

final class StatusMenuPresentationTests: XCTestCase {
  func testNoRepresentativeShowsDisconnectedState() {
    XCTAssertEqual(StatusMenuPresentation.title(for: nil), "No connected tasks")
  }

  func testInterventionTakesPresentationPriority() {
    let representative = RepresentativeTask(
      task: task(work: .running, result: .none, waiting: .user(.approval)),
      reason: .intervention
    )

    XCTAssertEqual(StatusMenuPresentation.title(for: representative), "Input needed · project")
  }

  func testRunningTaskShowsWorkingState() {
    let representative = RepresentativeTask(
      task: task(work: .running, result: .none),
      reason: .latestPrompt
    )

    XCTAssertEqual(StatusMenuPresentation.title(for: representative), "Working · project")
  }

  func testUnseenCompletionShowsFinishedState() {
    let representative = RepresentativeTask(
      task: task(work: .stopped, result: .completed, hasUnseenCompletion: true),
      reason: .latestPrompt
    )

    XCTAssertEqual(StatusMenuPresentation.title(for: representative), "Finished · project")
  }

  func testFailureShowsFailedState() {
    let representative = RepresentativeTask(
      task: task(work: .stopped, result: .failed),
      reason: .latestPrompt
    )

    XCTAssertEqual(StatusMenuPresentation.title(for: representative), "Failed · project")
  }

  private func task(
    work: WorkState,
    result: ResultState,
    waiting: WaitingState = .none,
    hasUnseenCompletion: Bool = false
  ) -> AgentTaskSnapshot {
    AgentTaskSnapshot(
      identity: TaskIdentity(
        provider: ProviderIdentifier("claude")!,
        profileID: "default",
        dataRoot: "/fixture",
        taskID: "session",
        executionID: "session",
        turnID: "turn"
      ),
      title: "project",
      work: work,
      result: result,
      waiting: waiting,
      lastPromptAt: Date(timeIntervalSince1970: 1),
      interventionRequestedAt: waiting.requiresUserIntervention
        ? Date(timeIntervalSince1970: 2) : nil,
      completedAt: result == .completed ? Date(timeIntervalSince1970: 3) : nil,
      updatedAt: Date(timeIntervalSince1970: 3),
      hasUnseenCompletion: hasUnseenCompletion
    )
  }
}
