import AgentPetCore
import AgentPetSprites
import Foundation
import XCTest

@testable import AgentPetUI

final class OverlayPresentationTests: XCTestCase {
  func testOneModeShowsRepresentativeAndCountsOtherInterventionTasks() throws {
    let latestPrompt = task(id: "latest", provider: "claude", prompt: 30)
    let olderWaiting = task(id: "older-waiting", provider: "codex", prompt: 10, waiting: 20)
    let newerWaiting = task(id: "newer-waiting", provider: "claude", prompt: 5, waiting: 25)
    let tasks = [latestPrompt, olderWaiting, newerWaiting]
    let representative = try XCTUnwrap(RepresentativeTaskSelector().select(from: tasks))

    let presentation = OverlayPresenter().makePresentation(
      tasks: tasks,
      representative: representative,
      savedMode: .one,
      isTemporarilyExpanded: false
    )

    XCTAssertEqual(presentation.cards.map(\.task.identity.taskID), ["newer-waiting"])
    XCTAssertEqual(presentation.cards.first?.status, .inputNeeded)
    XCTAssertEqual(presentation.additionalInterventionCount, 1)
    XCTAssertTrue(presentation.canToggleExpansion)
    XCTAssertEqual(presentation.cards.first?.providerLabel, "Claude")
  }

  func testManyModeUsesSharedOrderAndAddsOnlyNeededDisambiguation() throws {
    let duplicateOne = task(id: "abcdef-1", provider: "claude", title: "Project", prompt: 10)
    let duplicateTwo = task(id: "abcdef-2", provider: "claude", title: "Project", prompt: 20)
    let codex = task(id: "codex", provider: "codex", title: "Other", prompt: 30)
    let tasks = [duplicateOne, duplicateTwo, codex]

    let presentation = OverlayPresenter().makePresentation(
      tasks: tasks,
      representative: RepresentativeTaskSelector().select(from: tasks),
      savedMode: .many,
      isTemporarilyExpanded: false
    )

    XCTAssertEqual(
      presentation.cards.map(\.task.identity.taskID),
      ["codex", "abcdef-2", "abcdef-1"]
    )
    XCTAssertEqual(presentation.cards.map(\.providerLabel), ["Codex", "Claude", "Claude"])
    XCTAssertNil(presentation.cards.first?.shortTaskID)
    XCTAssertEqual(presentation.cards[1].shortTaskID, "abcdef")
    XCTAssertEqual(presentation.cards[2].shortTaskID, "abcdef")
    XCTAssertEqual(presentation.additionalInterventionCount, 0)
    XCTAssertFalse(presentation.canToggleExpansion)
  }

  func testNoCardModeUsesSinglePetCompletionDotAndTemporaryExpansion() {
    let completed = task(
      id: "done",
      provider: "claude",
      prompt: 20,
      result: .completed,
      unseen: true
    )
    let running = task(id: "running", provider: "claude", prompt: 10)
    let tasks = [completed, running]
    let presenter = OverlayPresenter()

    let hidden = presenter.makePresentation(
      tasks: tasks,
      representative: RepresentativeTaskSelector().select(from: tasks),
      savedMode: .none,
      isTemporarilyExpanded: false
    )
    let expanded = presenter.makePresentation(
      tasks: tasks,
      representative: RepresentativeTaskSelector().select(from: tasks),
      savedMode: .none,
      isTemporarilyExpanded: true
    )

    XCTAssertTrue(hidden.cards.isEmpty)
    XCTAssertTrue(hidden.showsPetCompletionDot)
    XCTAssertTrue(hidden.canToggleExpansion)
    XCTAssertEqual(expanded.cards.count, 2)
    XCTAssertFalse(expanded.showsPetCompletionDot)
  }

  func testPointerIntentSeparatesClickDragAndHold() {
    let resolver = OverlayPointerIntentResolver(dragDistance: 5, holdDuration: 0.35)

    XCTAssertEqual(resolver.resolve(distance: 2, duration: 0.1), .click)
    XCTAssertEqual(resolver.resolve(distance: 5, duration: 0.1), .drag)
    XCTAssertEqual(resolver.resolve(distance: 1, duration: 0.35), .hold)
    XCTAssertEqual(resolver.resolve(distance: 7, duration: 1), .drag)
  }

  func testTaskStatusMapsToCompatiblePetAnimationWithoutTreatingStopAsFailure() {
    XCTAssertEqual(TaskVisualStatus.inputNeeded.petAnimationState, .waiting)
    XCTAssertEqual(TaskVisualStatus.working.petAnimationState, .running)
    XCTAssertEqual(TaskVisualStatus.finished.petAnimationState, .review)
    XCTAssertEqual(TaskVisualStatus.failed.petAnimationState, .failed)
    XCTAssertEqual(TaskVisualStatus.stopped.petAnimationState, .idle)
    XCTAssertEqual(TaskVisualStatus.ready.petAnimationState, .idle)
  }

  private func task(
    id: String,
    provider: String,
    title: String = "Task",
    prompt: TimeInterval,
    waiting: TimeInterval? = nil,
    result: ResultState = .none,
    unseen: Bool = false
  ) -> AgentTaskSnapshot {
    let base = Date(timeIntervalSince1970: 1_000)
    return AgentTaskSnapshot(
      identity: TaskIdentity(
        provider: ProviderIdentifier(provider)!,
        profileID: "default",
        dataRoot: "/fixture",
        taskID: id,
        executionID: id,
        turnID: "turn"
      ),
      title: title,
      work: result == .none ? .running : .stopped,
      result: result,
      waiting: waiting == nil ? .none : .user(.approval),
      lastPromptAt: base.addingTimeInterval(prompt),
      interventionRequestedAt: waiting.map(base.addingTimeInterval),
      completedAt: result == .none ? nil : base.addingTimeInterval(prompt + 1),
      updatedAt: base.addingTimeInterval(prompt + 1),
      hasUnseenCompletion: unseen
    )
  }
}
