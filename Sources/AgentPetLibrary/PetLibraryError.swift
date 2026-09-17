import AgentPetSprites
import Foundation

public struct PetLibraryError: Error, Equatable, Sendable {
  public enum Code: String, Sendable, CaseIterable {
    case sourceUnavailable = "source_unavailable"
    case unsupportedSource = "unsupported_source"
    case invalidManifest = "invalid_manifest"
    case unsupportedVersion = "unsupported_version"
    case versionDimensionMismatch = "version_dimension_mismatch"
    case missingRequiredFrame = "missing_required_frame"
    case damagedImage = "damaged_image"
    case unsafePackage = "unsafe_package"
    case oversizedPackage = "oversized_package"
    case writeFailed = "write_failed"
    case urlNotAllowed = "url_not_allowed"
    case redirectLimitExceeded = "redirect_limit_exceeded"
    case downloadFailed = "download_failed"
    case petNotFound = "pet_not_found"
    case invalidGalleryResponse = "invalid_gallery_response"
    case invalidRecordID = "invalid_record_id"
    case recordNotFound = "record_not_found"
    case selectionStoreUnsupported = "selection_store_unsupported"
  }

  public let code: Code
  public let detail: [String: String]

  public init(_ code: Code, detail: [String: String] = [:]) {
    self.code = code
    self.detail = detail
  }

  init(spriteError: PetSpritePackageError) {
    switch spriteError {
    case .missingManifest:
      self.init(.unsafePackage, detail: ["reason": "missing_manifest"])
    case .manifestNotRegularFile:
      self.init(.unsafePackage, detail: ["reason": "manifest_not_regular_file"])
    case .manifestTooLarge:
      self.init(.oversizedPackage, detail: ["reason": "manifest_too_large"])
    case .invalidManifest:
      self.init(.invalidManifest, detail: ["reason": "undecodable"])
    case .invalidIdentifier:
      self.init(.invalidManifest, detail: ["reason": "invalid_id"])
    case .invalidDisplayName:
      self.init(.invalidManifest, detail: ["reason": "invalid_display_name"])
    case .unsupportedVersion(let version):
      self.init(.unsupportedVersion, detail: ["version": "\(version)"])
    case .unsafeSpritesheetPath:
      self.init(.unsafePackage, detail: ["reason": "unsafe_spritesheet_path"])
    case .missingSpritesheet:
      self.init(.unsafePackage, detail: ["reason": "missing_spritesheet"])
    case .spritesheetNotRegularFile:
      self.init(.unsafePackage, detail: ["reason": "spritesheet_not_regular_file"])
    case .spritesheetTooLarge:
      self.init(.oversizedPackage, detail: ["reason": "spritesheet_too_large"])
    case .unsupportedImageFormat:
      self.init(.damagedImage, detail: ["reason": "unsupported_image_format"])
    case .animatedImage:
      self.init(.damagedImage, detail: ["reason": "animated_image"])
    case .undecodableImage:
      self.init(.damagedImage, detail: ["reason": "undecodable_image"])
    case .invalidDimensions(
      let expectedWidth, let expectedHeight, let actualWidth, let actualHeight):
      self.init(
        .versionDimensionMismatch,
        detail: [
          "expectedWidth": "\(expectedWidth)",
          "expectedHeight": "\(expectedHeight)",
          "actualWidth": "\(actualWidth)",
          "actualHeight": "\(actualHeight)",
        ]
      )
    case .missingRequiredFrame(let row, let column):
      self.init(.missingRequiredFrame, detail: ["row": "\(row)", "column": "\(column)"])
    }
  }
}
