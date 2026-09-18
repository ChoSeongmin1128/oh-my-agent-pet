import AgentPetCore
import XCTest

final class TaskIdentityTests: XCTestCase {
  func testStableKeyIsUnambiguousEvenWhenComponentsContainLegacySeparator() throws {
    let separator = "\u{1F}"
    let first = TaskIdentity(
      provider: try XCTUnwrap(ProviderIdentifier("a")),
      profileID: "b\(separator)c",
      dataRoot: "root",
      taskID: "task",
      executionID: "execution",
      turnID: "turn"
    )
    let second = TaskIdentity(
      provider: try XCTUnwrap(ProviderIdentifier("a\(separator)b")),
      profileID: "c",
      dataRoot: "root",
      taskID: "task",
      executionID: "execution",
      turnID: "turn"
    )

    XCTAssertNotEqual(first, second)
    XCTAssertNotEqual(first.stableKey, second.stableKey)
  }
}
