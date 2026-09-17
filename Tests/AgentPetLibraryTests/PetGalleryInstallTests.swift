import AgentPetLibrary
import AgentPetTestSupport
import Foundation
import XCTest

@testable import AgentPetLibrary

final class PetGalleryInstallTests: XCTestCase {
  private var fixture: LibraryFixture!
  private var archive: Data!

  private let metadataURL = "https://codex-pets.net/api/pets/yuumi"
  private let downloadURL = "https://codex-pets.net/api/pets/yuumi/download?v=1789279767982"

  override func setUpWithError() throws {
    fixture = try LibraryFixture()
    let package = try PetPackageFixture.writePackage(
      into: fixture.sourceDirectory("yuumi"), id: "yuumi", displayName: "Yuumi", version: 2)
    archive = try ZipFixtureWriter.packageArchive(packageDirectory: package)
  }

  override func tearDown() {
    fixture.remove()
    fixture = nil
  }

  private func stubGallery(downloadPath: String = "/api/pets/yuumi/download?v=1789279767982") {
    let metadata = """
      {"pet":{"id":"yuumi","displayName":"Yuumi","downloadUrl":"\(downloadPath)","ownerHandle":"yuumi-owner"}}
      """
    fixture.downloader.respond(
      to: metadataURL, with: PetDownloadResponse(statusCode: 200, body: Data(metadata.utf8)))
    fixture.downloader.respond(
      to: downloadURL, with: PetDownloadResponse(statusCode: 200, body: archive))
  }

  func testParserAcceptsPageAPIAndDownloadLinksOnly() {
    let expected = PetGalleryReference(
      petID: "yuumi",
      pageURL: URL(string: "https://codex-pets.net/#/pets/yuumi")!,
      metadataURL: URL(string: "https://codex-pets.net/api/pets/yuumi")!
    )
    for link in [
      "https://codex-pets.net/#/pets/yuumi",
      "https://CODEX-PETS.NET/#/pets/yuumi",
      "https://codex-pets.net/api/pets/yuumi",
      "https://codex-pets.net/api/pets/yuumi/download?v=1",
      "https://codex-pets.net/pets/yuumi",
    ] {
      XCTAssertEqual(PetGalleryURLParser.parse(URL(string: link)!), expected, link)
    }
    for link in [
      "http://codex-pets.net/#/pets/yuumi",
      "https://example.com/#/pets/yuumi",
      "https://codex-pets.net.evil.com/#/pets/yuumi",
      "https://codex-pets.net/#/users/yuumi",
      "https://codex-pets.net/api/pets/",
      "https://codex-pets.net/api/pets/../secret",
      "https://user@codex-pets.net/#/pets/yuumi",
      "https://codex-pets.net:8443/#/pets/yuumi",
    ] {
      XCTAssertNil(PetGalleryURLParser.parse(URL(string: link)!), link)
    }
  }

  func testURLInstallResolvesMetadataDownloadsAndRecordsSource() throws {
    stubGallery()

    let staged = try fixture.service.stage(
      .url(URL(string: "https://codex-pets.net/#/pets/yuumi")!))
    XCTAssertEqual(
      staged.inspection.source, .url(URL(string: "https://codex-pets.net/#/pets/yuumi")!))
    XCTAssertEqual(staged.inspection.license.attribution, "yuumi-owner")
    XCTAssertEqual(staged.inspection.licenseStatus, .unknown, "owner handle alone is not a license")
    XCTAssertEqual(
      fixture.downloader.requests.map(\.absoluteString), [metadataURL, downloadURL])

    let outcome = try fixture.service.install(staged)
    XCTAssertEqual(outcome.record.recordID, "yuumi")
    XCTAssertEqual(outcome.record.source.kind, "url")

    let folderStaged = try fixture.service.stage(.folder(fixture.sourceDirectory("yuumi")))
    XCTAssertEqual(
      folderStaged.inspection.duplicateOf, "yuumi", "URL and folder share fingerprints")
    fixture.service.discard(folderStaged)
  }

  func testGalleryErrorsAreTyped() throws {
    assertLibraryError(
      try fixture.service.stage(.url(URL(string: "https://codex-pets.net/#/pets/yuumi")!)),
      .petNotFound)
    assertLibraryError(
      try fixture.service.stage(.url(URL(string: "https://example.com/#/pets/yuumi")!)),
      .urlNotAllowed)
    assertLibraryError(
      try fixture.service.stage(.url(URL(string: "http://codex-pets.net/#/pets/yuumi")!)),
      .urlNotAllowed)
    XCTAssertEqual(fixture.downloader.requests.count, 1, "disallowed URLs never hit the network")

    fixture.downloader.respond(
      to: metadataURL, with: PetDownloadResponse(statusCode: 500, body: Data()))
    assertLibraryError(
      try fixture.service.stage(.url(URL(string: "https://codex-pets.net/#/pets/yuumi")!)),
      .downloadFailed)

    fixture.downloader.respond(
      to: metadataURL, with: PetDownloadResponse(statusCode: 200, body: Data("[]".utf8)))
    assertLibraryError(
      try fixture.service.stage(.url(URL(string: "https://codex-pets.net/#/pets/yuumi")!)),
      .invalidGalleryResponse)

    stubGallery(downloadPath: "https://cdn.example.com/yuumi.zip")
    assertLibraryError(
      try fixture.service.stage(.url(URL(string: "https://codex-pets.net/#/pets/yuumi")!)),
      .urlNotAllowed)

    stubGallery()
    fixture.downloader.fail(downloadURL, with: .transport(code: -1009))
    assertLibraryError(
      try fixture.service.stage(.url(URL(string: "https://codex-pets.net/#/pets/yuumi")!)),
      .downloadFailed, reason: "transport")

    fixture.downloader.fail(downloadURL, with: .bodyTooLarge)
    assertLibraryError(
      try fixture.service.stage(.url(URL(string: "https://codex-pets.net/#/pets/yuumi")!)),
      .oversizedPackage, reason: "download_too_large")
    XCTAssertEqual(fixture.service.entries(), [])
    XCTAssertEqual(
      (try? FileManager.default.contentsOfDirectory(atPath: fixture.paths.stagingDirectory.path))
        ?? [],
      [])
  }

  func testRedirectsAreFollowedOnlyWithinPolicy() throws {
    let redirected = "https://codex-pets.net/api/pets/yuumi/download?v=2"
    stubGallery()
    fixture.downloader.respond(
      to: downloadURL,
      with: PetDownloadResponse(statusCode: 302, location: "/api/pets/yuumi/download?v=2"))
    fixture.downloader.respond(
      to: redirected, with: PetDownloadResponse(statusCode: 200, body: archive))
    let staged = try fixture.service.stage(
      .url(URL(string: "https://codex-pets.net/#/pets/yuumi")!))
    XCTAssertEqual(staged.inspection.manifestID, "yuumi")
    fixture.service.discard(staged)

    fixture.downloader.respond(
      to: downloadURL,
      with: PetDownloadResponse(statusCode: 307, location: "https://cdn.example.com/yuumi.zip"))
    assertLibraryError(
      try fixture.service.stage(.url(URL(string: "https://codex-pets.net/#/pets/yuumi")!)),
      .urlNotAllowed)

    for hop in 0...PetLibraryPolicy.maximumRedirects {
      fixture.downloader.respond(
        to: hop == 0 ? downloadURL : "https://codex-pets.net/hop/\(hop)",
        with: PetDownloadResponse(
          statusCode: 301, location: "https://codex-pets.net/hop/\(hop + 1)"))
    }
    assertLibraryError(
      try fixture.service.stage(.url(URL(string: "https://codex-pets.net/#/pets/yuumi")!)),
      .redirectLimitExceeded)

    fixture.downloader.respond(
      to: downloadURL, with: PetDownloadResponse(statusCode: 302, location: nil))
    assertLibraryError(
      try fixture.service.stage(.url(URL(string: "https://codex-pets.net/#/pets/yuumi")!)),
      .downloadFailed, reason: "redirect_without_location")
  }
}
