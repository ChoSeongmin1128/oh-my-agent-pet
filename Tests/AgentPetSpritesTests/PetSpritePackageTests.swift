import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import AgentPetSprites

final class PetSpritePackageTests: XCTestCase {
  func testMissingVersionDefaultsToV1AndCropsTopOriginRows() throws {
    let package = try makePackage(version: nil, rows: 9, coloredEdges: true)

    let loaded = try PetSpritePackageLoader().load(packageDirectory: package)

    XCTAssertEqual(loaded.version, .v1)
    XCTAssertEqual(loaded.manifest.spriteVersionNumber, 1)
    let top = try pixel(in: XCTUnwrap(loaded.frame(row: 0, column: 0)))
    let bottom = try pixel(in: XCTUnwrap(loaded.frame(row: 8, column: 0)))
    XCTAssertGreaterThan(top[0], top[2])
    XCTAssertGreaterThan(bottom[2], bottom[0])
    XCTAssertEqual(top[3], 255)
    XCTAssertEqual(bottom[3], 255)
    XCTAssertNil(loaded.frame(row: 9, column: 0))
    XCTAssertNil(loaded.frame(row: 0, column: 8))
  }

  func testV2LoadsExactElevenRowAtlas() throws {
    let package = try makePackage(version: 2, rows: 11)

    let loaded = try PetSpritePackageLoader().load(packageDirectory: package)

    XCTAssertEqual(loaded.version, .v2)
    XCTAssertTrue(loaded.version.supportsGaze)
    XCTAssertNotNil(loaded.frame(row: 10, column: 7))
  }

  func testManifestVersionControlsExpectedHeight() throws {
    let v1WithV2Image = try makePackage(version: 1, rows: 11)
    let v2WithV1Image = try makePackage(version: 2, rows: 9)

    XCTAssertThrowsError(try PetSpritePackageLoader().load(packageDirectory: v1WithV2Image)) {
      XCTAssertEqual(
        $0 as? PetSpritePackageError,
        .invalidDimensions(
          expectedWidth: 1_536,
          expectedHeight: 1_872,
          actualWidth: 1_536,
          actualHeight: 2_288
        )
      )
    }
    XCTAssertThrowsError(try PetSpritePackageLoader().load(packageDirectory: v2WithV1Image)) {
      XCTAssertEqual(
        $0 as? PetSpritePackageError,
        .invalidDimensions(
          expectedWidth: 1_536,
          expectedHeight: 2_288,
          actualWidth: 1_536,
          actualHeight: 1_872
        )
      )
    }
  }

  func testRejectsUnsupportedVersionAndUnsafePaths() throws {
    let unsupported = try makePackage(version: 3, rows: 9)
    XCTAssertThrowsError(try PetSpritePackageLoader().load(packageDirectory: unsupported)) {
      XCTAssertEqual($0 as? PetSpritePackageError, .unsupportedVersion(3))
    }

    for path in [
      "../outside.png", "/tmp/outside.png", "folder/../../outside.png", "folder\\pet.png",
    ] {
      let package = try makePackage(version: 1, rows: 9, spritesheetPath: path)
      XCTAssertThrowsError(try PetSpritePackageLoader().load(packageDirectory: package)) {
        XCTAssertEqual($0 as? PetSpritePackageError, .unsafeSpritesheetPath)
      }
    }
  }

  func testRejectsSymlinkedSpritesheet() throws {
    let root = try temporaryDirectory()
    let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID()).png")
    try writeAtlas(to: outside, rows: 9)
    addTeardownBlock { try? FileManager.default.removeItem(at: outside) }
    try manifest(version: 1, spritesheetPath: "spritesheet.png").write(
      to: root.appendingPathComponent("pet.json")
    )
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("spritesheet.png"),
      withDestinationURL: outside
    )

    XCTAssertThrowsError(try PetSpritePackageLoader().load(packageDirectory: root)) {
      XCTAssertTrue(
        ($0 as? PetSpritePackageError) == .unsafeSpritesheetPath
          || ($0 as? PetSpritePackageError) == .spritesheetNotRegularFile
      )
    }
  }

  func testRejectsOversizedFilesBeforeDecoding() throws {
    let oversizedManifest = try temporaryDirectory()
    let manifestURL = oversizedManifest.appendingPathComponent("pet.json")
    FileManager.default.createFile(atPath: manifestURL.path, contents: nil)
    let manifestHandle = try FileHandle(forWritingTo: manifestURL)
    try manifestHandle.truncate(atOffset: UInt64(PetSpritePackageLoader.maximumManifestBytes + 1))
    try manifestHandle.close()
    XCTAssertThrowsError(try PetSpritePackageLoader().load(packageDirectory: oversizedManifest)) {
      XCTAssertEqual($0 as? PetSpritePackageError, .manifestTooLarge)
    }

    let oversizedImage = try temporaryDirectory()
    try manifest(version: 1, spritesheetPath: "spritesheet.png").write(
      to: oversizedImage.appendingPathComponent("pet.json")
    )
    let imageURL = oversizedImage.appendingPathComponent("spritesheet.png")
    FileManager.default.createFile(atPath: imageURL.path, contents: nil)
    let imageHandle = try FileHandle(forWritingTo: imageURL)
    try imageHandle.truncate(atOffset: UInt64(PetSpritePackageLoader.maximumSpritesheetBytes + 1))
    try imageHandle.close()
    XCTAssertThrowsError(try PetSpritePackageLoader().load(packageDirectory: oversizedImage)) {
      XCTAssertEqual($0 as? PetSpritePackageError, .spritesheetTooLarge)
    }
  }

  func testRejectsFullyTransparentRequiredFrame() throws {
    let package = try makePackage(
      version: 1,
      rows: 9,
      emptyFrame: (row: 5, column: 7)
    )

    XCTAssertThrowsError(try PetSpritePackageLoader().load(packageDirectory: package)) {
      XCTAssertEqual($0 as? PetSpritePackageError, .missingRequiredFrame(row: 5, column: 7))
    }
  }

  func testInstalledWebPPackageCanBeCheckedReadOnly() throws {
    guard let path = ProcessInfo.processInfo.environment["OMAPET_LIVE_PET_PACKAGE"] else {
      throw XCTSkip("Set OMAPET_LIVE_PET_PACKAGE for a read-only installed WebP format check.")
    }

    let package = try PetSpritePackageLoader().load(
      packageDirectory: URL(fileURLWithPath: path, isDirectory: true)
    )

    XCTAssertEqual(package.image.width, package.version.pixelWidth)
    XCTAssertEqual(package.image.height, package.version.pixelHeight)
  }

  private func makePackage(
    version: Int?,
    rows: Int,
    spritesheetPath: String = "spritesheet.png",
    coloredEdges: Bool = false,
    emptyFrame: (row: Int, column: Int)? = nil
  ) throws -> URL {
    let directory = try temporaryDirectory()
    try manifest(version: version, spritesheetPath: spritesheetPath).write(
      to: directory.appendingPathComponent("pet.json")
    )
    if spritesheetPath == "spritesheet.png" {
      try writeAtlas(
        to: directory.appendingPathComponent(spritesheetPath),
        rows: rows,
        coloredEdges: coloredEdges,
        emptyFrame: emptyFrame
      )
    }
    return directory
  }

  private func manifest(version: Int?, spritesheetPath: String) -> Data {
    var object: [String: Any] = [
      "id": "fixture-pet",
      "displayName": "Fixture Pet",
      "description": "Test package",
      "spritesheetPath": spritesheetPath,
    ]
    if let version { object["spriteVersionNumber"] = version }
    return try! JSONSerialization.data(withJSONObject: object)
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentPetSpritesTests-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return directory
  }

  private func writeAtlas(
    to url: URL,
    rows: Int,
    coloredEdges: Bool = false,
    emptyFrame: (row: Int, column: Int)? = nil
  ) throws {
    let width = PetSpriteVersion.v1.pixelWidth
    let height = rows * PetSpriteVersion.cellHeight
    let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try XCTUnwrap(
      CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let frameCounts =
      rows == PetSpriteVersion.v2.rows
      ? PetSpriteVersion.v2.requiredFrameCounts
      : PetSpriteVersion.v1.requiredFrameCounts
    context.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1))
    for (row, frameCount) in frameCounts.enumerated() {
      for column in 0..<frameCount where row != emptyFrame?.row || column != emptyFrame?.column {
        context.fill(
          CGRect(
            x: column * PetSpriteVersion.cellWidth,
            y: height - ((row + 1) * PetSpriteVersion.cellHeight),
            width: PetSpriteVersion.cellWidth,
            height: PetSpriteVersion.cellHeight
          )
        )
      }
    }
    if coloredEdges {
      context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
      context.fill(
        CGRect(
          x: 0,
          y: height - PetSpriteVersion.cellHeight,
          width: PetSpriteVersion.cellWidth,
          height: PetSpriteVersion.cellHeight
        )
      )
      context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
      context.fill(
        CGRect(
          x: 0,
          y: 0,
          width: PetSpriteVersion.cellWidth,
          height: PetSpriteVersion.cellHeight
        )
      )
    }
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    )
    CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
  }

  private func pixel(in image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = try XCTUnwrap(
      CGContext(
        data: &bytes,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return bytes
  }
}
