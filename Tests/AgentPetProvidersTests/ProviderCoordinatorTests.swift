import AgentPetCore
import AgentPetProviders
import XCTest

final class ProviderCoordinatorTests: XCTestCase {
  func testSingleProviderWorksWithoutOptionalProvider() async throws {
    let claude = ProviderIdentifier("claude")!
    let coordinator = try ProviderCoordinator(
      adapters: [
        StubAdapter(identifier: claude, behavior: .tasks([task(provider: claude, id: "one")]))
      ]
    )

    let report = await coordinator.refresh()

    XCTAssertEqual(report.tasks.map(\.identity.taskID), ["one"])
    XCTAssertEqual(report.representative?.task.identity.provider, claude)
    XCTAssertTrue(report.failures.isEmpty)
  }

  func testBothProvidersUseSharedRepresentativePolicy() async throws {
    let claude = ProviderIdentifier("claude")!
    let codex = ProviderIdentifier("codex")!
    let coordinator = try ProviderCoordinator(
      adapters: [
        StubAdapter(
          identifier: claude,
          behavior: .tasks([task(provider: claude, id: "active", promptOffset: 100)])
        ),
        StubAdapter(
          identifier: codex,
          behavior: .tasks([
            task(
              provider: codex,
              id: "waiting",
              promptOffset: 1,
              waiting: .user(.approval),
              interventionOffset: 2
            )
          ])
        ),
      ]
    )

    let report = await coordinator.refresh()

    XCTAssertEqual(report.tasks.count, 2)
    XCTAssertEqual(report.representative?.task.identity.taskID, "waiting")
    XCTAssertEqual(report.representative?.reason, .intervention)
  }

  func testProviderFailureDoesNotDiscardHealthyProvider() async throws {
    let healthy = ProviderIdentifier("healthy")!
    let failed = ProviderIdentifier("failed")!
    let coordinator = try ProviderCoordinator(
      adapters: [
        StubAdapter(identifier: healthy, behavior: .tasks([task(provider: healthy, id: "one")])),
        StubAdapter(identifier: failed, behavior: .failure),
      ]
    )

    let report = await coordinator.refresh()

    XCTAssertEqual(report.tasks.map(\.identity.taskID), ["one"])
    XCTAssertEqual(report.failures.map(\.provider), [failed])
    XCTAssertEqual(report.failures.map(\.reason), [.loadFailed])
  }

  func testMismatchedProviderPayloadIsRejected() async throws {
    let expected = ProviderIdentifier("expected")!
    let other = ProviderIdentifier("other")!
    let coordinator = try ProviderCoordinator(
      adapters: [
        StubAdapter(identifier: expected, behavior: .tasks([task(provider: other, id: "wrong")]))
      ]
    )

    let report = await coordinator.refresh()

    XCTAssertTrue(report.tasks.isEmpty)
    XCTAssertEqual(report.failures.map(\.provider), [expected])
    XCTAssertEqual(report.failures.map(\.reason), [.mismatchedProvider])
  }

  func testDuplicateTaskIdentityFromAdapterIsRejected() async throws {
    let provider = ProviderIdentifier("provider")!
    let duplicate = task(provider: provider, id: "duplicate")
    let coordinator = try ProviderCoordinator(
      adapters: [
        StubAdapter(identifier: provider, behavior: .tasks([duplicate, duplicate]))
      ]
    )

    let report = await coordinator.refresh()

    XCTAssertTrue(report.tasks.isEmpty)
    XCTAssertEqual(report.failures.map(\.reason), [.duplicateTaskIdentity])
  }

  func testDuplicateProviderAdaptersFailAtConstruction() {
    let provider = ProviderIdentifier("duplicate")!

    XCTAssertThrowsError(
      try ProviderCoordinator(
        adapters: [
          StubAdapter(identifier: provider, behavior: .tasks([])),
          StubAdapter(identifier: provider, behavior: .tasks([])),
        ]
      )
    ) { error in
      XCTAssertEqual(error as? ProviderCoordinatorError, .duplicateProvider(provider))
    }
  }

  private func task(
    provider: ProviderIdentifier,
    id: String,
    promptOffset: TimeInterval = 1,
    waiting: WaitingState = .none,
    interventionOffset: TimeInterval? = nil
  ) -> AgentTaskSnapshot {
    let base = Date(timeIntervalSince1970: 1_000)
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
      lastPromptAt: base.addingTimeInterval(promptOffset),
      interventionRequestedAt: interventionOffset.map(base.addingTimeInterval),
      completedAt: nil,
      updatedAt: base.addingTimeInterval(promptOffset),
      hasUnseenCompletion: false
    )
  }
}

private struct StubAdapter: TaskProviderAdapter {
  enum Behavior: Sendable {
    case tasks([AgentTaskSnapshot])
    case failure
  }

  let identifier: ProviderIdentifier
  let behavior: Behavior

  func loadTasks() async throws -> [AgentTaskSnapshot] {
    switch behavior {
    case .tasks(let tasks):
      return tasks
    case .failure:
      throw StubError.failed
    }
  }
}

private enum StubError: Error {
  case failed
}
