import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PetSpritePackageError: Error, Equatable, Sendable {
  case missingManifest
  case manifestNotRegularFile
  case manifestTooLarge
  case invalidManifest
  case invalidIdentifier
  case invalidDisplayName
  case unsupportedVersion(Int)
  case unsafeSpritesheetPath
  case missingSpritesheet
  case spritesheetNotRegularFile
  case spritesheetTooLarge
  case unsupportedImageFormat
  case animatedImage
  case invalidDimensions(
    expectedWidth: Int, expectedHeight: Int, actualWidth: Int, actualHeight: Int)
  case missingRequiredFrame(row: Int, column: Int)
  case undecodableImage
}

public final class PetSpritePackage: @unchecked Sendable {
  public let directoryURL: URL
  public let manifest: PetSpriteManifest
  public let version: PetSpriteVersion
  public let image: CGImage

  init(
    directoryURL: URL,
    manifest: PetSpriteManifest,
    version: PetSpriteVersion,
    image: CGImage
  ) {
    self.directoryURL = directoryURL
    self.manifest = manifest
    self.version = version
    self.image = image
  }

  public func frame(row: Int, column: Int) -> CGImage? {
    guard (0..<version.rows).contains(row),
      (0..<PetSpriteVersion.columns).contains(column)
    else {
      return nil
    }
    let crop = CGRect(
      x: column * PetSpriteVersion.cellWidth,
      y: row * PetSpriteVersion.cellHeight,
      width: PetSpriteVersion.cellWidth,
      height: PetSpriteVersion.cellHeight
    )
    return image.cropping(to: crop)
  }
}

public struct PetSpritePackageLoader {
  public static let maximumManifestBytes = 64 * 1_024
  public static let maximumSpritesheetBytes = 32 * 1_024 * 1_024

  private let fileManager: FileManager

  public init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  public func load(packageDirectory: URL) throws -> PetSpritePackage {
    let directory = packageDirectory.standardizedFileURL.resolvingSymlinksInPath()
    let manifestURL = directory.appendingPathComponent("pet.json", isDirectory: false)
    let manifestData = try readRegularFile(
      at: manifestURL,
      missing: .missingManifest,
      invalid: .manifestNotRegularFile,
      oversized: .manifestTooLarge,
      limit: Self.maximumManifestBytes
    )
    let manifest: PetSpriteManifest
    do {
      manifest = try JSONDecoder().decode(PetSpriteManifest.self, from: manifestData)
    } catch {
      throw PetSpritePackageError.invalidManifest
    }
    guard Self.isValidPackageIdentifier(manifest.id) else {
      throw PetSpritePackageError.invalidIdentifier
    }
    guard Self.isValidDisplayName(manifest.displayName) else {
      throw PetSpritePackageError.invalidDisplayName
    }
    guard let version = PetSpriteVersion(rawValue: manifest.spriteVersionNumber) else {
      throw PetSpritePackageError.unsupportedVersion(manifest.spriteVersionNumber)
    }
    guard Self.isSafeRelativePath(manifest.spritesheetPath) else {
      throw PetSpritePackageError.unsafeSpritesheetPath
    }

    let spritesheetURL =
      directory
      .appendingPathComponent(manifest.spritesheetPath, isDirectory: false)
      .standardizedFileURL
    let resolvedSpritesheetURL = spritesheetURL.resolvingSymlinksInPath()
    guard Self.contains(resolvedSpritesheetURL, in: directory) else {
      throw PetSpritePackageError.unsafeSpritesheetPath
    }
    let spritesheetData = try readRegularFile(
      at: spritesheetURL,
      missing: .missingSpritesheet,
      invalid: .spritesheetNotRegularFile,
      oversized: .spritesheetTooLarge,
      limit: Self.maximumSpritesheetBytes
    )
    guard let source = CGImageSourceCreateWithData(spritesheetData as CFData, nil) else {
      throw PetSpritePackageError.undecodableImage
    }
    guard Self.isSupportedImageType(CGImageSourceGetType(source) as String?) else {
      throw PetSpritePackageError.unsupportedImageFormat
    }
    guard CGImageSourceGetCount(source) == 1 else {
      throw PetSpritePackageError.animatedImage
    }
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else {
      throw PetSpritePackageError.undecodableImage
    }
    guard width == version.pixelWidth, height == version.pixelHeight else {
      throw PetSpritePackageError.invalidDimensions(
        expectedWidth: version.pixelWidth,
        expectedHeight: version.pixelHeight,
        actualWidth: width,
        actualHeight: height
      )
    }
    guard
      let image = CGImageSourceCreateImageAtIndex(
        source,
        0,
        [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
      )
    else {
      throw PetSpritePackageError.undecodableImage
    }
    if let missingFrame = Self.firstMissingRequiredFrame(in: image, version: version) {
      throw PetSpritePackageError.missingRequiredFrame(
        row: missingFrame.row,
        column: missingFrame.column
      )
    }
    return PetSpritePackage(
      directoryURL: directory,
      manifest: manifest,
      version: version,
      image: image
    )
  }

  private func readRegularFile(
    at url: URL,
    missing: PetSpritePackageError,
    invalid: PetSpritePackageError,
    oversized: PetSpritePackageError,
    limit: Int
  ) throws -> Data {
    guard fileManager.fileExists(atPath: url.path) else { throw missing }
    let values: URLResourceValues
    do {
      values = try url.resourceValues(forKeys: [
        .fileSizeKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
      ])
    } catch {
      throw invalid
    }
    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw invalid }
    guard let size = values.fileSize, size <= limit else { throw oversized }
    do {
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      guard data.count <= limit else { throw oversized }
      return data
    } catch let error as PetSpritePackageError {
      throw error
    } catch {
      throw invalid
    }
  }

  public static func isValidPackageIdentifier(_ value: String) -> Bool {
    guard (1...64).contains(value.count), value != ".", value != ".." else { return false }
    return value.unicodeScalars.allSatisfy {
      CharacterSet.alphanumerics.contains($0)
        || CharacterSet(charactersIn: "-_.").contains($0)
    }
  }

  private static func isValidDisplayName(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed.count <= 80
  }

  public static func isSafeRelativePath(_ value: String) -> Bool {
    guard !value.isEmpty,
      !value.hasPrefix("/"),
      !value.contains("\\"),
      !value.contains(":"),
      !value.contains("\0")
    else {
      return false
    }
    return value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
      !$0.isEmpty && $0 != "." && $0 != ".."
    }
  }

  private static func contains(_ file: URL, in directory: URL) -> Bool {
    let root = directory.standardizedFileURL.path(percentEncoded: false)
    let child = file.standardizedFileURL.path(percentEncoded: false)
    return child.hasPrefix(root.hasSuffix("/") ? root : root + "/")
  }

  private static func isSupportedImageType(_ type: String?) -> Bool {
    guard let type else { return false }
    return type == UTType.png.identifier || type == UTType.webP.identifier
  }

  private static func firstMissingRequiredFrame(
    in image: CGImage,
    version: PetSpriteVersion
  ) -> (row: Int, column: Int)? {
    var pixels = [UInt8](
      repeating: 0,
      count: PetSpriteVersion.cellWidth * PetSpriteVersion.cellHeight * 4
    )
    let frameRect = CGRect(
      x: 0,
      y: 0,
      width: PetSpriteVersion.cellWidth,
      height: PetSpriteVersion.cellHeight
    )
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return (0, 0) }
    return pixels.withUnsafeMutableBytes { storage in
      guard
        let context = CGContext(
          data: storage.baseAddress,
          width: PetSpriteVersion.cellWidth,
          height: PetSpriteVersion.cellHeight,
          bitsPerComponent: 8,
          bytesPerRow: PetSpriteVersion.cellWidth * 4,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else {
        return (0, 0)
      }
      for (row, frameCount) in version.requiredFrameCounts.enumerated() {
        for column in 0..<frameCount {
          context.clear(frameRect)
          guard
            let frame = image.cropping(
              to: CGRect(
                x: column * PetSpriteVersion.cellWidth,
                y: row * PetSpriteVersion.cellHeight,
                width: PetSpriteVersion.cellWidth,
                height: PetSpriteVersion.cellHeight
              )
            )
          else {
            return (row, column)
          }
          context.draw(frame, in: frameRect)
          let hasVisiblePixel = stride(from: 3, to: storage.count, by: 4).contains {
            storage[$0] > 0
          }
          if !hasVisiblePixel { return (row, column) }
        }
      }
      return nil
    }
  }
}
