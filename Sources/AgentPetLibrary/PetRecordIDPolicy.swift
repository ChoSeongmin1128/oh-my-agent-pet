import Foundation

enum PetRecordIDPolicy {
  static let fingerprintLength = 64
  static let maximumLength = 64 + 1 + fingerprintLength

  static func isValid(_ value: String) -> Bool {
    guard !value.isEmpty,
      value.count <= maximumLength,
      value != ".",
      value != "..",
      !value.hasPrefix(".")
    else {
      return false
    }
    return value.unicodeScalars.allSatisfy {
      CharacterSet.alphanumerics.contains($0)
        || CharacterSet(charactersIn: "-_.").contains($0)
    }
  }

  static func propose(
    manifestID: String,
    fingerprint: String,
    takenIDs: Set<String>
  ) -> String {
    if !PetSelection.reservedIdentifiers.contains(manifestID), !takenIDs.contains(manifestID) {
      return manifestID
    }

    var length = PetLibraryPolicy.recordIdentifierSuffixLength
    while length <= fingerprint.count {
      let candidate = "\(manifestID)-\(fingerprint.prefix(length))"
      if !takenIDs.contains(candidate) {
        return candidate
      }
      length += PetLibraryPolicy.recordIdentifierSuffixLength
    }
    return "\(manifestID)-\(fingerprint)"
  }
}
