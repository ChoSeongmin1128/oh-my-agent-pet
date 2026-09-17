import Foundation

public enum PetLicenseStatus: String, Codable, Equatable, Sendable {
  case bundledVerified = "bundled_verified"
  case externallyDeclared = "externally_declared"
  case unknown
}

public struct PetLicenseDeclaration: Codable, Equatable, Sendable {
  public var name: String?
  public var url: String?
  public var attribution: String?
  public var noticeFile: String?

  public init(
    name: String? = nil,
    url: String? = nil,
    attribution: String? = nil,
    noticeFile: String? = nil
  ) {
    self.name = name
    self.url = url
    self.attribution = attribution
    self.noticeFile = noticeFile
  }

  public var isEmpty: Bool {
    name == nil && url == nil && attribution == nil && noticeFile == nil
  }

  public var declaresLicense: Bool {
    name != nil || url != nil || noticeFile != nil
  }
}

public enum PetInstallSource: Equatable, Sendable {
  case folder(name: String)
  case archive(fileName: String)
  case url(URL)

  public var kind: String {
    switch self {
    case .folder: "folder"
    case .archive: "archive"
    case .url: "url"
    }
  }

  public var value: String {
    switch self {
    case .folder(let name): name
    case .archive(let fileName): fileName
    case .url(let url): url.absoluteString
    }
  }
}

extension PetInstallSource: Codable {
  private enum CodingKeys: String, CodingKey {
    case kind
    case value
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(String.self, forKey: .kind)
    let value = try container.decode(String.self, forKey: .value)
    switch kind {
    case "folder":
      self = .folder(name: value)
    case "archive":
      self = .archive(fileName: value)
    case "url":
      guard let url = URL(string: value) else {
        throw DecodingError.dataCorruptedError(
          forKey: .value, in: container, debugDescription: "invalid url")
      }
      self = .url(url)
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .kind, in: container, debugDescription: "unknown source kind")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind, forKey: .kind)
    try container.encode(value, forKey: .value)
  }
}

public struct PetLibraryRecord: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let recordID: String
  public let manifestID: String
  public let displayName: String
  public let description: String
  public let spriteVersion: Int
  public let spritesheetPath: String
  public let installedAt: Date
  public let source: PetInstallSource
  public let packageFingerprint: String
  public let spritesheetFingerprint: String
  public let license: PetLicenseDeclaration
  public let licenseStatus: PetLicenseStatus

  public init(
    schemaVersion: Int = PetLibraryPolicy.recordSchemaVersion,
    recordID: String,
    manifestID: String,
    displayName: String,
    description: String,
    spriteVersion: Int,
    spritesheetPath: String,
    installedAt: Date,
    source: PetInstallSource,
    packageFingerprint: String,
    spritesheetFingerprint: String,
    license: PetLicenseDeclaration,
    licenseStatus: PetLicenseStatus
  ) {
    self.schemaVersion = schemaVersion
    self.recordID = recordID
    self.manifestID = manifestID
    self.displayName = displayName
    self.description = description
    self.spriteVersion = spriteVersion
    self.spritesheetPath = spritesheetPath
    self.installedAt = installedAt
    self.source = source
    self.packageFingerprint = packageFingerprint
    self.spritesheetFingerprint = spritesheetFingerprint
    self.license = license
    self.licenseStatus = licenseStatus
  }

  static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
