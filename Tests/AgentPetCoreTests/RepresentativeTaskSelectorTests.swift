import AgentPetCore
import XCTest

final class RepresentativeTaskSelectorTests: XCTestCase {
  func testNewestInterventionWinsOverNewerRunningPrompt() throws {
    let base = Date(timeIntervalSince1970: 1_000)
    let running = task(
      id: "running",
      waiting: .none,
      prompt: base.addingTimeInterval(100),
      intervention: nil,
      updated: base.addingTimeInterval(200)
    )
    let waiting = task(
      id: "waiting",
      waiting: .user(.choice),
      prompt: base,
      intervention: base.addingTimeInterval(10),
      updated: base.addingTimeInterval(10)
    )

    let selected = RepresentativeTaskSelector().select(from: [running, waiting])

    XCTAssertEqual(selected?.task.identity.taskID, "waiting")
    XCTAssertEqual(selected?.reason, .intervention)
  }

  func testNewestInterventionWinsAmongInterventions() throws {
    let base = Date(timeIntervalSince1970: 1_000)
    let older = task(
      id: "older",
      waiting: .user(.approval),
      prompt: base,
      intervention: base.addingTimeInterval(10),
      updated: base.addingTimeInterval(500)
    )
    let newer = task(
      id: "newer",
      waiting: .user(.answer),
      prompt: base,
      intervention: base.addingTimeInterval(20),
      updated: base.addingTimeInterval(20)
    )

    let selected = RepresentativeTaskSelector().select(from: [older, newer])

    XCTAssertEqual(selected?.task.identity.taskID, "newer")
  }

  func testProgressUpdateDoesNotReorderLatestPrompt() throws {
    let base = Date(timeIntervalSince1970: 1_000)
    let latestPrompt = task(
      id: "latest-prompt",
      waiting: .none,
      prompt: base.addingTimeInterval(20),
      intervention: nil,
      updated: base.addingTimeInterval(20)
    )
    let latestProgress = task(
      id: "latest-progress",
      waiting: .none,
      prompt: base.addingTimeInterval(10),
      intervention: nil,
      updated: base.addingTimeInterval(100)
    )

    let selected = RepresentativeTaskSelector().select(from: [latestProgress, latestPrompt])

    XCTAssertEqual(selected?.task.identity.taskID, "latest-prompt")
    XCTAssertEqual(selected?.reason, .latestPrompt)
  }

  func testEmptyCatalogHasNoRepresentative() {
    XCTAssertNil(RepresentativeTaskSelector().select(from: []))
  }

  private func task(
    id: String,
    waiting: WaitingState,
    prompt: Date?,
    intervention: Date?,
    updated: Date
  ) -> AgentTaskSnapshot {
    let provider = ProviderIdentifier("test")!
    return AgentTaskSnapshot(
      identity: TaskIdentity(
        provider: provider,
        profileID: "default",
        dataRoot: "/fixture",
        taskID: id,
        executionID: "execution",
        turnID: "turn"
      ),
      title: id,
      work: .running,
      result: .none,
      waiting: waiting,
      lastPromptAt: prompt,
      interventionRequestedAt: intervention,
      completedAt: nil,
      updatedAt: updated,
      hasUnseenCompletion: false
    )
  }
}
