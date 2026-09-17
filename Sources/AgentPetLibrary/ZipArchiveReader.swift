import Compression
import Foundation

struct ZipArchiveEntry: Equatable, Sendable {
  let name: String
  let isDirectory: Bool
  let isSymbolicLink: Bool
  let isEncrypted: Bool
  let compressionMethod: UInt16
  let compressedSize: Int
  let uncompressedSize: Int
  let crc32: UInt32
  let localHeaderOffset: Int
}

enum ZipArchiveError: Error, Equatable, Sendable {
  case notAnArchive
  case unsupportedFeature(String)
  case corrupt(String)
}

struct ZipArchiveReader: Sendable {
  private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4b50
  private static let zip64LocatorSignature: UInt32 = 0x0706_4b50
  private static let centralDirectorySignature: UInt32 = 0x0201_4b50
  private static let localHeaderSignature: UInt32 = 0x0403_4b50
  private static let storedMethod: UInt16 = 0
  private static let deflateMethod: UInt16 = 8
  private static let unixSymbolicLinkMode: UInt32 = 0xA000
  private static let unixDirectoryMode: UInt32 = 0x4000

  let entries: [ZipArchiveEntry]
  private let bytes: [UInt8]

  init(data: Data) throws {
    bytes = [UInt8](data)
    let endRecord = try Self.locateEndOfCentralDirectory(in: bytes)
    let entryCount = Int(Self.readUInt16(bytes, at: endRecord + 10))
    let directorySize = Int(Self.readUInt32(bytes, at: endRecord + 12))
    let directoryOffset = Int(Self.readUInt32(bytes, at: endRecord + 16))
    guard entryCount != 0xFFFF, directorySize != 0xFFFF_FFFF, directoryOffset != 0xFFFF_FFFF
    else {
      throw ZipArchiveError.unsupportedFeature("zip64")
    }
    if endRecord >= 20, Self.readUInt32(bytes, at: endRecord - 20) == Self.zip64LocatorSignature {
      throw ZipArchiveError.unsupportedFeature("zip64")
    }
    guard directoryOffset + directorySize <= endRecord else {
      throw ZipArchiveError.corrupt("central_directory_bounds")
    }

    var parsed: [ZipArchiveEntry] = []
    var cursor = directoryOffset
    for _ in 0..<entryCount {
      guard cursor + 46 <= directoryOffset + directorySize,
        Self.readUInt32(bytes, at: cursor) == Self.centralDirectorySignature
      else {
        throw ZipArchiveError.corrupt("central_directory_entry")
      }
      let flags = Self.readUInt16(bytes, at: cursor + 8)
      let method = Self.readUInt16(bytes, at: cursor + 10)
      let crc = Self.readUInt32(bytes, at: cursor + 16)
      let compressedSize = Int(Self.readUInt32(bytes, at: cursor + 20))
      let uncompressedSize = Int(Self.readUInt32(bytes, at: cursor + 24))
      let nameLength = Int(Self.readUInt16(bytes, at: cursor + 28))
      let extraLength = Int(Self.readUInt16(bytes, at: cursor + 30))
      let commentLength = Int(Self.readUInt16(bytes, at: cursor + 32))
      let externalAttributes = Self.readUInt32(bytes, at: cursor + 38)
      let localOffset = Int(Self.readUInt32(bytes, at: cursor + 42))
      let nameStart = cursor + 46
      let nameEnd = nameStart + nameLength
      guard nameEnd + extraLength + commentLength <= directoryOffset + directorySize else {
        throw ZipArchiveError.corrupt("central_directory_name")
      }
      guard let name = String(bytes: bytes[nameStart..<nameEnd], encoding: .utf8) else {
        throw ZipArchiveError.corrupt("entry_name_encoding")
      }
      let unixMode = (externalAttributes >> 16) & 0xF000
      parsed.append(
        ZipArchiveEntry(
          name: name,
          isDirectory: name.hasSuffix("/") || unixMode == Self.unixDirectoryMode,
          isSymbolicLink: unixMode == Self.unixSymbolicLinkMode,
          isEncrypted: flags & 0x0001 != 0,
          compressionMethod: method,
          compressedSize: compressedSize,
          uncompressedSize: uncompressedSize,
          crc32: crc,
          localHeaderOffset: localOffset
        )
      )
      cursor = nameEnd + extraLength + commentLength
    }
    entries = parsed
  }

  func extract(_ entry: ZipArchiveEntry) throws -> Data {
    guard !entry.isEncrypted else { throw ZipArchiveError.unsupportedFeature("encryption") }
    let header = entry.localHeaderOffset
    guard header + 30 <= bytes.count,
      Self.readUInt32(bytes, at: header) == Self.localHeaderSignature
    else {
      throw ZipArchiveError.corrupt("local_header")
    }
    let nameLength = Int(Self.readUInt16(bytes, at: header + 26))
    let extraLength = Int(Self.readUInt16(bytes, at: header + 28))
    let dataStart = header + 30 + nameLength + extraLength
    let dataEnd = dataStart + entry.compressedSize
    guard dataEnd <= bytes.count else { throw ZipArchiveError.corrupt("entry_data_bounds") }
    let compressed = Array(bytes[dataStart..<dataEnd])

    let output: [UInt8]
    switch entry.compressionMethod {
    case Self.storedMethod:
      guard entry.compressedSize == entry.uncompressedSize else {
        throw ZipArchiveError.corrupt("stored_size")
      }
      output = compressed
    case Self.deflateMethod:
      output = try Self.inflate(compressed, expectedSize: entry.uncompressedSize)
    default:
      throw ZipArchiveError.unsupportedFeature("compression_method_\(entry.compressionMethod)")
    }
    guard CRC32.checksum(output) == entry.crc32 else { throw ZipArchiveError.corrupt("crc32") }
    return Data(output)
  }

  private static func inflate(_ compressed: [UInt8], expectedSize: Int) throws -> [UInt8] {
    guard expectedSize > 0 else {
      return []
    }
    guard !compressed.isEmpty else { throw ZipArchiveError.corrupt("deflate_empty") }
    var output = [UInt8](repeating: 0, count: expectedSize + 1)
    let written = output.withUnsafeMutableBufferPointer { destination in
      compressed.withUnsafeBufferPointer { source in
        compression_decode_buffer(
          destination.baseAddress!,
          destination.count,
          source.baseAddress!,
          source.count,
          nil,
          COMPRESSION_ZLIB
        )
      }
    }
    guard written == expectedSize else { throw ZipArchiveError.corrupt("deflate_size") }
    output.removeLast()
    return output
  }

  private static func locateEndOfCentralDirectory(in bytes: [UInt8]) throws -> Int {
    guard bytes.count >= 22 else { throw ZipArchiveError.notAnArchive }
    let earliest = max(0, bytes.count - 22 - 0xFFFF)
    var cursor = bytes.count - 22
    while cursor >= earliest {
      if readUInt32(bytes, at: cursor) == endOfCentralDirectorySignature {
        let commentLength = Int(readUInt16(bytes, at: cursor + 20))
        if cursor + 22 + commentLength == bytes.count {
          return cursor
        }
      }
      cursor -= 1
    }
    throw ZipArchiveError.notAnArchive
  }

  private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
  }

  private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    UInt32(bytes[offset])
      | UInt32(bytes[offset + 1]) << 8
      | UInt32(bytes[offset + 2]) << 16
      | UInt32(bytes[offset + 3]) << 24
  }
}

enum CRC32 {
  private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
    var value = UInt32(index)
    for _ in 0..<8 {
      value = value & 1 != 0 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
    }
    return value
  }

  static func checksum(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
      crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
    }
    return crc ^ 0xFFFF_FFFF
  }
}
