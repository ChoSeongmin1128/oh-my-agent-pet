import Foundation
import OmapetSupport
import XCTest

final class OmapetCommandRunnerTests: XCTestCase {
  func testVersionTextIsStable() {
    let result = OmapetCommandRunner().run(arguments: ["version"])

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.standardOutput, "Oh My Agent Pet 0.0.0-dev\n")
    XCTAssertEqual(result.standardError, "")
  }

  func testVersionJSONIsMachineReadable() throws {
    let result = OmapetCommandRunner().run(arguments: ["version", "--json"])
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: String]
    )

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(object["name"], "Oh My Agent Pet")
    XCTAssertEqual(object["version"], "0.0.0-dev")
  }

  func testSetupStatusDoesNotClaimConnection() throws {
    let result = OmapetCommandRunner().run(arguments: ["setup", "status", "--json"])
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any]
    )

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(object["status"] as? String, "notConfigured")
    XCTAssertEqual((object["connections"] as? [String])?.count, 0)
  }

  func testDoctorReportsOnlyImplementedRuntimeCheck() throws {
    let result = OmapetCommandRunner().run(arguments: ["doctor", "--json"])
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any]
    )
    let checks = try XCTUnwrap(object["checks"] as? [[String: String]])

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(checks, [["id": "runtime", "status": "pass"]])
  }

  func testUnknownCommandUsesUsageExitCode() {
    let result = OmapetCommandRunner().run(arguments: ["connect"])

    XCTAssertEqual(result.exitCode, 64)
    XCTAssertTrue(result.standardOutput.isEmpty)
    XCTAssertTrue(result.standardError.contains("Unsupported arguments"))
  }
}
