import Compression
import Foundation

public struct ZipFixtureEntry: Sendable {
  public enum Method: Sendable {
    case stored
    case deflate
  }

  public let name: String
  public let data: Data
  public let method: Method
  public let isSymbolicLink: Bool
  public let isDirectory: Bool
  public let declaredUncompressedSize: Int?
  public let corruptCRC: Bool

  public init(
    name: String,
    data: Data = Data(),
    method: Method = .stored,
    isSymbolicLink: Bool = false,
    isDirectory: Bool = false,
    declaredUncompressedSize: Int? = nil,
    corruptCRC: Bool = false
  ) {
    self.name = name
    self.data = data
    self.method = method
    self.isSymbolicLink = isSymbolicLink
    self.isDirectory = isDirectory
    self.declaredUncompressedSize = declaredUncompressedSize
    self.corruptCRC = corruptCRC
  }

  public static func file(_ name: String, _ data: Data, method: Method = .stored) -> ZipFixtureEntry
  {
    ZipFixtureEntry(name: name, data: data, method: method)
  }

  public static func file(_ name: String, contentsOf url: URL, method: Method = .stored) throws
    -> ZipFixtureEntry
  {
    ZipFixtureEntry(name: name, data: try Data(contentsOf: url), method: method)
  }
}

public enum ZipFixtureWriter {
  public static func archive(_ entries: [ZipFixtureEntry]) -> Data {
    var body = Data()
    var central = Data()
    for entry in entries {
      let nameBytes = Data(entry.name.utf8)
      let compressed: Data
      let method: UInt16
      switch entry.method {
      case .stored:
        compressed = entry.data
        method = 0
      case .deflate:
        compressed = deflate(entry.data)
        method = 8
      }
      let crc = crc32([UInt8](entry.data)) ^ (entry.corruptCRC ? 0xFFFF_FFFF : 0)
      let uncompressedSize = UInt32(entry.declaredUncompressedSize ?? entry.data.count)
      let localOffset = UInt32(body.count)
      var local = Data()
      local.append(uint32: 0x0403_4b50)
      local.append(uint16: 20)
      local.append(uint16: 0x0800)
      local.append(uint16: method)
      local.append(uint16: 0)
      local.append(uint16: 0)
      local.append(uint32: crc)
      local.append(uint32: UInt32(compressed.count))
      local.append(uint32: uncompressedSize)
      local.append(uint16: UInt16(nameBytes.count))
      local.append(uint16: 0)
      local.append(nameBytes)
      local.append(compressed)
      body.append(local)

      let mode: UInt32 = entry.isSymbolicLink ? 0o120777 : (entry.isDirectory ? 0o040755 : 0o100644)
      central.append(uint32: 0x0201_4b50)
      central.append(uint16: (3 << 8) | 20)
      central.append(uint16: 20)
      central.append(uint16: 0x0800)
      central.append(uint16: method)
      central.append(uint16: 0)
      central.append(uint16: 0)
      central.append(uint32: crc)
      central.append(uint32: UInt32(compressed.count))
      central.append(uint32: uncompressedSize)
      central.append(uint16: UInt16(nameBytes.count))
      central.append(uint16: 0)
      central.append(uint16: 0)
      central.append(uint16: 0)
      central.append(uint16: 0)
      central.append(uint32: mode << 16)
      central.append(uint32: localOffset)
      central.append(nameBytes)
    }
    var archive = body
    archive.append(central)
    archive.append(uint32: 0x0605_4b50)
    archive.append(uint16: 0)
    archive.append(uint16: 0)
    archive.append(uint16: UInt16(entries.count))
    archive.append(uint16: UInt16(entries.count))
    archive.append(uint32: UInt32(central.count))
    archive.append(uint32: UInt32(body.count))
    archive.append(uint16: 0)
    return archive
  }

  public static func packageArchive(
    packageDirectory: URL,
    root: String = "",
    method: ZipFixtureEntry.Method = .stored,
    extraEntries: [ZipFixtureEntry] = []
  ) throws -> Data {
    let manifestURL = packageDirectory.appendingPathComponent("pet.json")
    let manifest = try Data(contentsOf: manifestURL)
    let object = try JSONSerialization.jsonObject(with: manifest) as! [String: Any]
    let spritesheetPath = object["spritesheetPath"] as! String
    var entries = [
      ZipFixtureEntry.file(root + "pet.json", manifest, method: method),
      try ZipFixtureEntry.file(
        root + spritesheetPath,
        contentsOf: packageDirectory.appendingPathComponent(spritesheetPath),
        method: method
      ),
    ]
    entries.append(contentsOf: extraEntries)
    return archive(entries)
  }

  private static func deflate(_ data: Data) -> Data {
    guard !data.isEmpty else { return Data([0x03, 0x00]) }
    let source = [UInt8](data)
    var destination = [UInt8](repeating: 0, count: source.count * 2 + 64)
    let written = destination.withUnsafeMutableBufferPointer { output in
      source.withUnsafeBufferPointer { input in
        compression_encode_buffer(
          output.baseAddress!, output.count, input.baseAddress!, input.count, nil,
          COMPRESSION_ZLIB)
      }
    }
    return Data(destination[..<written])
  }

  private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
    var value = UInt32(index)
    for _ in 0..<8 {
      value = value & 1 != 0 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
    }
    return value
  }

  private static func crc32(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
      crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
    }
    return crc ^ 0xFFFF_FFFF
  }
}

extension Data {
  fileprivate mutating func append(uint16 value: UInt16) {
    append(UInt8(value & 0xFF))
    append(UInt8(value >> 8))
  }

  fileprivate mutating func append(uint32 value: UInt32) {
    append(UInt8(value & 0xFF))
    append(UInt8((value >> 8) & 0xFF))
    append(UInt8((value >> 16) & 0xFF))
    append(UInt8((value >> 24) & 0xFF))
  }
}
