import AgentPetCore
import XCTest

final class TaskCatalogTests: XCTestCase {
  func testEmptyCatalogStartsWithoutTasks() {
    XCTAssertTrue(TaskCatalog().tasks.isEmpty)
  }

  func testUpsertReplacesOnlyMatchingIdentity() {
    var catalog = TaskCatalog([task(id: "a", title: "old"), task(id: "b", title: "keep")])

    catalog.upsert(task(id: "a", title: "new"))

    XCTAssertEqual(catalog.tasks.count, 2)
    XCTAssertEqual(catalog.tasks.first(where: { $0.identity.taskID == "a" })?.title, "new")
    XCTAssertEqual(catalog.tasks.first(where: { $0.identity.taskID == "b" })?.title, "keep")
  }

  func testRemoveUsesCompleteTaskIdentity() {
    let first = task(id: "same", title: "first", turnID: "one")
    let second = task(id: "same", title: "second", turnID: "two")
    var catalog = TaskCatalog([first, second])

    catalog.remove(first.identity)

    XCTAssertNil(catalog[first.identity])
    XCTAssertEqual(catalog[second.identity]?.title, "second")
  }

  private func task(id: String, title: String, turnID: String = "turn") -> AgentTaskSnapshot {
    AgentTaskSnapshot(
      identity: TaskIdentity(
        provider: ProviderIdentifier("test")!,
        profileID: "default",
        dataRoot: "/fixture",
        taskID: id,
        executionID: "execution",
        turnID: turnID
      ),
      title: title,
      work: .running,
      result: .none,
      waiting: .none,
      lastPromptAt: Date(timeIntervalSince1970: 1),
      interventionRequestedAt: nil,
      completedAt: nil,
      updatedAt: Date(timeIntervalSince1970: 1),
      hasUnseenCompletion: false
    )
  }
}
