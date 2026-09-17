import AgentPetSprites
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PetPackageFixtureError: Error {
  case imageEncodingFailed
}

public enum PetPackageFixture {
  public static func manifest(
    id: String = "fixture-pet",
    displayName: String = "Fixture Pet",
    version: Int? = 1,
    spritesheetPath: String = "spritesheet.png",
    extraFields: [String: Any] = [:]
  ) -> Data {
    var object: [String: Any] = [
      "id": id,
      "displayName": displayName,
      "description": "Test package",
      "spritesheetPath": spritesheetPath,
    ]
    if let version { object["spriteVersionNumber"] = version }
    for (key, value) in extraFields { object[key] = value }
    return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }

  @discardableResult
  public static func writePackage(
    into directory: URL,
    id: String = "fixture-pet",
    displayName: String = "Fixture Pet",
    version: Int? = 1,
    rows: Int? = nil,
    spritesheetPath: String = "spritesheet.png",
    coloredEdges: Bool = false,
    emptyFrame: (row: Int, column: Int)? = nil,
    seed: UInt8 = 0,
    extraFields: [String: Any] = [:]
  ) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try manifest(
      id: id, displayName: displayName, version: version, spritesheetPath: spritesheetPath,
      extraFields: extraFields
    ).write(to: directory.appendingPathComponent("pet.json"))
    let spritesheetURL = directory.appendingPathComponent(spritesheetPath)
    try FileManager.default.createDirectory(
      at: spritesheetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try writeAtlas(
      to: spritesheetURL,
      rows: rows ?? ((version ?? 1) == 2 ? PetSpriteVersion.v2.rows : PetSpriteVersion.v1.rows),
      coloredEdges: coloredEdges,
      emptyFrame: emptyFrame,
      seed: seed
    )
    return directory
  }

  public static func writeAtlas(
    to url: URL,
    rows: Int,
    coloredEdges: Bool = false,
    emptyFrame: (row: Int, column: Int)? = nil,
    seed: UInt8 = 0
  ) throws {
    let width = PetSpriteVersion.v1.pixelWidth
    let height = rows * PetSpriteVersion.cellHeight
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw PetPackageFixtureError.imageEncodingFailed
    }
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let frameCounts =
      rows == PetSpriteVersion.v2.rows
      ? PetSpriteVersion.v2.requiredFrameCounts
      : PetSpriteVersion.v1.requiredFrameCounts
    context.setFillColor(
      CGColor(red: 0.4, green: 0.5, blue: CGFloat(seed) / 255 * 0.5 + 0.3, alpha: 1))
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
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw PetPackageFixtureError.imageEncodingFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw PetPackageFixtureError.imageEncodingFailed
    }
  }

  public static func temporaryDirectory(prefix: String = "omapet-fixture") throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}
