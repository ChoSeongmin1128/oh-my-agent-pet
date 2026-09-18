import AgentPetCore
import Foundation
import XCTest

final class ApplicationIdentityTests: XCTestCase {
  func testApplicationPathsOwnSharedProductStorage() {
    let home = URL(fileURLWithPath: "/tmp/omapet-home", isDirectory: true)
    let paths = ApplicationPaths(homeDirectory: home)

    XCTAssertEqual(
      paths.applicationSupportDirectory.path,
      "/tmp/omapet-home/Library/Application Support/Oh My Agent Pet"
    )
    XCTAssertEqual(paths.eventsURL.lastPathComponent, "events.ndjson")
    XCTAssertEqual(paths.petsDirectory.lastPathComponent, "Pets")
  }

  func testProviderCatalogHasUniqueKnownProvidersAndCentralLabels() {
    XCTAssertEqual(ProviderIdentifier.claude.displayName, "Claude")
    XCTAssertEqual(ProviderIdentifier.codex.displayName, "Codex")
    XCTAssertEqual(
      Set(ProviderCatalog.supported.map(\.identifier)).count,
      ProviderCatalog.supported.count
    )
    XCTAssertEqual(ProviderIdentifier("future-provider")?.displayName, "future-provider")
  }
}
