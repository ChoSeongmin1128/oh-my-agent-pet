import AgentPetSprites
import Foundation

public enum PetLibraryPolicy {
  // Only the codex-pets gallery is a supported download origin. Exact host match, HTTPS only.
  public static let allowedHosts: Set<String> = ["codex-pets.net"]
  public static let allowedScheme = "https"
  // Each redirect hop is re-checked against the host and scheme rules above.
  public static let maximumRedirects = 3
  public static let requestTimeout: TimeInterval = 30
  public static let resourceTimeout: TimeInterval = 180

  // Gallery metadata is about 1 KiB; it shares the manifest cap so the same reader bound applies.
  public static let maximumMetadataBytes = PetSpritePackageLoader.maximumManifestBytes
  // A package is one spritesheet plus a manifest. The allowance covers license and readme files
  // and archive container overhead.
  public static let auxiliaryFilesAllowanceBytes = 8 * 1_024 * 1_024
  public static let maximumArchiveBytes =
    PetSpritePackageLoader.maximumSpritesheetBytes
    + PetSpritePackageLoader.maximumManifestBytes
    + auxiliaryFilesAllowanceBytes
  public static let maximumUnpackedBytes = maximumArchiveBytes
  public static let maximumArchiveEntries = 32

  public static let recordSchemaVersion = 1
  public static let recordIdentifierSuffixLength = 8
  public static let ignoredArchiveDirectory = "__MACOSX"
  public static let licenseNoticeFileNames: Set<String> = ["license", "copying", "notice"]
}
