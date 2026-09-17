import Foundation

enum PetLicenseReader {
  static func declaration(
    manifest: Data,
    rootFileNames: [String],
    fallbackAttribution: String?
  ) -> PetLicenseDeclaration {
    var declaration = PetLicenseDeclaration()
    if let object = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any] {
      switch object["license"] {
      case let name as String:
        declaration.name = trimmed(name)
      case let license as [String: Any]:
        declaration.name = trimmed(license["name"] as? String ?? license["spdx"] as? String)
        declaration.url = trimmed(license["url"] as? String)
      default:
        break
      }
      if declaration.url == nil {
        declaration.url = trimmed(
          object["licenseUrl"] as? String ?? object["licenseURL"] as? String)
      }
      declaration.attribution = trimmed(
        object["author"] as? String ?? object["attribution"] as? String)
    }
    if declaration.attribution == nil {
      declaration.attribution = trimmed(fallbackAttribution)
    }
    declaration.noticeFile = rootFileNames.sorted().first { fileName in
      let stem = (fileName as NSString).deletingPathExtension.lowercased()
      return PetLibraryPolicy.licenseNoticeFileNames.contains(stem)
    }
    return declaration
  }

  static func status(for declaration: PetLicenseDeclaration) -> PetLicenseStatus {
    declaration.declaresLicense ? .externallyDeclared : .unknown
  }

  private static func trimmed(_ value: String?) -> String? {
    guard let value else { return nil }
    let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty || result.count > 200 ? nil : result
  }
}
