import AgentPetLibrary
import AgentPetTestSupport
import Foundation
import OmapetSupport
import XCTest

final class OmapetPetCommandTests: XCTestCase {
  private var home: URL!
  private var runner: OmapetCommandRunner!
  private var downloader: RecordingDownloader!
  private var package: URL!

  override func setUpWithError() throws {
    home = try PetPackageFixture.temporaryDirectory(prefix: "omapet-cli-pet")
    downloader = RecordingDownloader()
    runner = OmapetCommandRunner(
      environment: [:],
      homeDirectory: home,
      executableURL: home.appendingPathComponent("omapet"),
      currentDirectory: home,
      petPackageDownloader: downloader,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
    package = try PetPackageFixture.writePackage(
      into: home.appendingPathComponent("sources/haaap"), id: "haaap", displayName: "Haaap")
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: home)
  }

  private func json(_ result: OmapetCommandResult) throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any],
      result.standardError
    )
  }

  private var libraryRoot: URL {
    home.appendingPathComponent("Library/Application Support/Oh My Agent Pet/Pets")
  }

  func testListIsEmptyAndCreatesNothingOnFreshHome() throws {
    let result = runner.run(arguments: ["pet", "list", "--json"])
    let object = try json(result)

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(object["ok"] as? Bool, true)
    XCTAssertEqual((object["pets"] as? [Any])?.count, 0)
    XCTAssertEqual((object["selection"] as? [String: Any])?["kind"] as? String, "original")
    XCTAssertFalse(FileManager.default.fileExists(atPath: libraryRoot.path))
    XCTAssertEqual(runner.run(arguments: ["pet", "list"]).standardOutput, "Selection: original\n")
  }

  func testInspectAndDryRunDoNotWriteLibraryOrSelection() throws {
    let inspect = runner.run(arguments: ["pet", "inspect", "sources/haaap", "--json"])
    let inspected = try json(inspect)
    XCTAssertEqual(inspect.exitCode, 0)
    XCTAssertEqual(inspected["manifestID"] as? String, "haaap")
    XCTAssertEqual(inspected["wouldInstallAs"] as? String, "haaap")
    XCTAssertEqual(inspected["licenseStatus"] as? String, "unknown")
    XCTAssertEqual(inspected["warnings"] as? [String], ["license_unknown"])
    XCTAssertNil(inspected["dryRun"])
    XCTAssertEqual(inspected["changed"] as? Bool, false)

    let dryRun = runner.run(arguments: ["pet", "install", "sources/haaap", "--dry-run", "--json"])
    let planned = try json(dryRun)
    XCTAssertEqual(dryRun.exitCode, 0)
    XCTAssertEqual(planned["dryRun"] as? Bool, true)
    XCTAssertEqual(
      planned["packageFingerprint"] as? String, inspected["packageFingerprint"] as? String)

    XCTAssertFalse(
      FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent("library").path))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: libraryRoot.appendingPathComponent("selection.json").path))
    XCTAssertEqual(
      (try? FileManager.default.contentsOfDirectory(
        atPath: libraryRoot.appendingPathComponent("staging").path)) ?? [],
      [])
  }

  func testInstallSelectListRemoveRoundTrip() throws {
    let install = runner.run(arguments: ["pet", "install", package.path, "--json"])
    let installed = try json(install)
    XCTAssertEqual(install.exitCode, 0)
    XCTAssertEqual(installed["ok"] as? Bool, true)
    XCTAssertEqual(installed["changed"] as? Bool, true)
    XCTAssertEqual(installed["recordID"] as? String, "haaap")
    XCTAssertEqual(installed["alreadyInstalled"] as? Bool, false)
    XCTAssertEqual(installed["nextCommands"] as? [String], ["omapet pet select haaap"])

    let again = try json(runner.run(arguments: ["pet", "install", package.path, "--json"]))
    XCTAssertEqual(again["alreadyInstalled"] as? Bool, true)
    XCTAssertEqual(again["changed"] as? Bool, false)

    let select = try json(runner.run(arguments: ["pet", "select", "haaap", "--json"]))
    XCTAssertEqual(select["changed"] as? Bool, true)
    XCTAssertEqual((select["selection"] as? [String: Any])?["recordID"] as? String, "haaap")

    let list = try json(runner.run(arguments: ["pet", "list", "--json"]))
    let pets = try XCTUnwrap(list["pets"] as? [[String: Any]])
    XCTAssertEqual(pets.count, 1)
    XCTAssertEqual(pets[0]["recordID"] as? String, "haaap")
    XCTAssertEqual(pets[0]["selected"] as? Bool, true)
    XCTAssertEqual(pets[0]["health"] as? String, "ready")
    XCTAssertEqual(pets[0]["installedAt"] as? String, "2023-11-14T22:13:20Z")
    XCTAssertEqual((pets[0]["source"] as? [String: String])?["kind"], "folder")

    let none = try json(runner.run(arguments: ["pet", "select", "none", "--json"]))
    XCTAssertEqual((none["selection"] as? [String: Any])?["kind"] as? String, "none")
    XCTAssertEqual(
      runner.run(arguments: ["pet", "select", "original"]).standardOutput,
      "Selection: original (changed)\n")
    _ = runner.run(arguments: ["pet", "select", "haaap"])

    let remove = try json(runner.run(arguments: ["pet", "remove", "haaap", "--json"]))
    XCTAssertEqual(remove["changed"] as? Bool, true)
    XCTAssertEqual(remove["selectionReset"] as? Bool, true)
    XCTAssertEqual(
      (try json(runner.run(arguments: ["pet", "list", "--json"]))["pets"] as? [Any])?.count, 0)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: package.appendingPathComponent("pet.json").path))
  }

  func testErrorsUseStableCodesAndExitCodes() throws {
    let cases: [([String], String, Int32)] = [
      (["pet", "install", "missing-folder"], "source_unavailable", 66),
      (["pet", "select", "not-installed"], "record_not_found", 66),
      (["pet", "remove", "../escape"], "invalid_record_id", 64),
      (["pet", "install", "https://example.com/#/pets/x"], "url_not_allowed", 73),
      (["pet", "install", "https://codex-pets.net/#/pets/nope"], "pet_not_found", 69),
    ]
    for (arguments, code, exitCode) in cases {
      let result = runner.run(arguments: arguments + ["--json"])
      let object = try json(result)
      XCTAssertEqual(result.exitCode, exitCode, arguments.joined(separator: " "))
      XCTAssertEqual(object["status"] as? String, "error")
      XCTAssertEqual(object["code"] as? String, code)
      XCTAssertTrue(result.standardError.isEmpty)
    }
    let text = runner.run(arguments: ["pet", "install", "missing-folder"])
    XCTAssertEqual(text.exitCode, 66)
    XCTAssertTrue(text.standardError.hasPrefix("Pet command failed: source_unavailable"))

    let invalid = try PetPackageFixture.writePackage(
      into: home.appendingPathComponent("sources/bad"), id: "bad", version: 1, rows: 11)
    let mismatch = try json(runner.run(arguments: ["pet", "inspect", invalid.path, "--json"]))
    XCTAssertEqual(mismatch["code"] as? String, "version_dimension_mismatch")
    XCTAssertEqual((mismatch["detail"] as? [String: String])?["actualHeight"], "2288")
    XCTAssertEqual(runner.run(arguments: ["pet", "list", "--dry-run"]).exitCode, 64)
    XCTAssertEqual(runner.run(arguments: ["pet", "frobnicate", "x"]).exitCode, 64)
  }

  func testFolderArchiveAndURLProduceTheSameInspection() throws {
    let archiveData = try ZipFixtureWriter.packageArchive(packageDirectory: package, root: "haaap/")
    let archive = home.appendingPathComponent("haaap.codex-pet.zip")
    try archiveData.write(to: archive)
    downloader.respond(
      "https://codex-pets.net/api/pets/haaap",
      PetDownloadResponse(
        statusCode: 200,
        body: Data(#"{"pet":{"id":"haaap","downloadUrl":"/api/pets/haaap/download?v=5"}}"#.utf8)))
    downloader.respond(
      "https://codex-pets.net/api/pets/haaap/download?v=5",
      PetDownloadResponse(statusCode: 200, body: archiveData))

    let folder = try json(runner.run(arguments: ["pet", "inspect", package.path, "--json"]))
    let zipped = try json(runner.run(arguments: ["pet", "inspect", archive.path, "--json"]))
    let remote = try json(
      runner.run(arguments: ["pet", "inspect", "https://codex-pets.net/#/pets/haaap", "--json"]))

    for key in [
      "manifestID", "packageFingerprint", "spritesheetFingerprint", "licenseStatus",
      "wouldInstallAs",
    ] {
      XCTAssertEqual(folder[key] as? String, zipped[key] as? String, key)
      XCTAssertEqual(folder[key] as? String, remote[key] as? String, key)
    }
    XCTAssertEqual((folder["source"] as? [String: String])?["kind"], "folder")
    XCTAssertEqual((zipped["source"] as? [String: String])?["kind"], "archive")
    XCTAssertEqual(
      (remote["source"] as? [String: String])?["value"], "https://codex-pets.net/#/pets/haaap")

    let installed = try json(
      runner.run(arguments: ["pet", "install", "https://codex-pets.net/#/pets/haaap", "--json"]))
    XCTAssertEqual(installed["recordID"] as? String, "haaap")
    let duplicate = try json(runner.run(arguments: ["pet", "inspect", archive.path, "--json"]))
    XCTAssertEqual(duplicate["duplicateOf"] as? String, "haaap")
  }
}

private final class RecordingDownloader: PetPackageDownloader, @unchecked Sendable {
  private let lock = NSLock()
  private var responses: [String: PetDownloadResponse] = [:]

  func respond(_ url: String, _ response: PetDownloadResponse) {
    lock.lock()
    responses[url] = response
    lock.unlock()
  }

  func fetch(_ url: URL, maximumBytes: Int) throws -> PetDownloadResponse {
    lock.lock()
    defer { lock.unlock() }
    return responses[url.absoluteString] ?? PetDownloadResponse(statusCode: 404)
  }
}
