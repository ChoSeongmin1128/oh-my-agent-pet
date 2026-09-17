import CryptoKit
import Foundation

public enum PetPackageFingerprint {
  // Versioned domain separator so a future canonical form cannot collide with this one.
  static let domain = "omapet-pet-package-v1"

  public static func spritesheetDigest(_ spritesheet: Data) -> String {
    hex(SHA256.hash(data: spritesheet))
  }

  public static func packageDigest(manifest: Data, spritesheetDigest: String) throws -> String {
    var hasher = SHA256()
    hasher.update(data: Data(domain.utf8))
    hasher.update(data: Data([0]))
    hasher.update(data: try canonicalManifest(manifest))
    hasher.update(data: Data([0]))
    hasher.update(data: Data(spritesheetDigest.utf8))
    return hex(hasher.finalize())
  }

  // Key order and whitespace of pet.json do not change the asset, so they do not change the digest.
  static func canonicalManifest(_ manifest: Data) throws -> Data {
    let object = try JSONSerialization.jsonObject(with: manifest)
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }

  private static func hex(_ digest: SHA256.Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
  }
}
