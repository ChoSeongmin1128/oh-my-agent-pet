import AgentPetSprites
import Foundation

struct PetPackageStager {
  let fileSystem: PetLibraryFileSystem

  func createDirectory(_ url: URL) throws {
    do {
      try fileSystem.createDirectory(at: url)
    } catch {
      throw PetLibraryError(.writeFailed, detail: ["reason": "create_directory"])
    }
  }

  func copyFolderPackage(from sourceDirectory: URL, to packageDirectory: URL) throws {
    switch fileSystem.itemType(at: sourceDirectory) {
    case .directory:
      break
    case .missing:
      throw PetLibraryError(.sourceUnavailable, detail: ["reason": "missing"])
    case .regularFile, .symbolicLink, .other:
      throw PetLibraryError(.unsupportedSource, detail: ["reason": "not_a_directory"])
    }
    let manifestName = "pet.json"
    try copyRegularFile(
      at: sourceDirectory.appendingPathComponent(manifestName, isDirectory: false),
      to: packageDirectory.appendingPathComponent(manifestName, isDirectory: false),
      limit: PetSpritePackageLoader.maximumManifestBytes,
      missingReason: "missing_manifest"
    )
    let manifestData = try fileSystem.readData(
      at: packageDirectory.appendingPathComponent(manifestName, isDirectory: false),
      maximumBytes: PetSpritePackageLoader.maximumManifestBytes
    )
    guard let manifest = try? JSONDecoder().decode(PetSpriteManifest.self, from: manifestData)
    else {
      throw PetLibraryError(.invalidManifest, detail: ["reason": "undecodable"])
    }
    guard PetSpritePackageLoader.isSafeRelativePath(manifest.spritesheetPath) else {
      throw PetLibraryError(.unsafePackage, detail: ["reason": "unsafe_spritesheet_path"])
    }
    try copyRegularFile(
      at: sourceDirectory.appendingPathComponent(manifest.spritesheetPath, isDirectory: false),
      to: packageDirectory.appendingPathComponent(manifest.spritesheetPath, isDirectory: false),
      limit: PetSpritePackageLoader.maximumSpritesheetBytes,
      missingReason: "missing_spritesheet"
    )

    let siblings: [URL]
    do {
      siblings = try fileSystem.contentsOfDirectory(at: sourceDirectory)
    } catch {
      throw PetLibraryError(.sourceUnavailable, detail: ["reason": "unreadable_directory"])
    }
    var auxiliaryBytes = 0
    for item in siblings.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
      let name = item.lastPathComponent
      guard !name.hasPrefix("."), name != manifestName, name != manifest.spritesheetPath else {
        continue
      }
      switch fileSystem.itemType(at: item) {
      case .regularFile:
        let size = try fileSize(at: item)
        auxiliaryBytes += size
        guard auxiliaryBytes <= PetLibraryPolicy.auxiliaryFilesAllowanceBytes else {
          throw PetLibraryError(.oversizedPackage, detail: ["reason": "auxiliary_files_too_large"])
        }
        try copyRegularFile(
          at: item,
          to: packageDirectory.appendingPathComponent(name, isDirectory: false),
          limit: PetLibraryPolicy.auxiliaryFilesAllowanceBytes,
          missingReason: "missing_file"
        )
      case .symbolicLink:
        throw PetLibraryError(.unsafePackage, detail: ["reason": "symbolic_link"])
      case .directory, .missing, .other:
        continue
      }
    }
  }

  func copyRegularFile(
    at source: URL,
    to destination: URL,
    limit: Int,
    missingReason: String
  ) throws {
    switch fileSystem.itemType(at: source) {
    case .regularFile:
      break
    case .missing:
      throw PetLibraryError(.unsafePackage, detail: ["reason": missingReason])
    case .symbolicLink:
      throw PetLibraryError(.unsafePackage, detail: ["reason": "symbolic_link"])
    case .directory, .other:
      throw PetLibraryError(.unsafePackage, detail: ["reason": "not_regular_file"])
    }
    guard try fileSize(at: source) <= limit else {
      throw PetLibraryError(.oversizedPackage, detail: ["reason": "file_too_large"])
    }
    try createDirectory(destination.deletingLastPathComponent())
    do {
      try fileSystem.copyFile(at: source, to: destination)
    } catch {
      throw PetLibraryError(.writeFailed, detail: ["reason": "copy"])
    }
  }

  func fileSize(at url: URL) throws -> Int {
    do {
      return try fileSystem.fileSize(at: url)
    } catch {
      throw PetLibraryError(.sourceUnavailable, detail: ["reason": "unreadable_file"])
    }
  }

  func readArchiveFile(_ file: URL) throws -> Data {
    switch fileSystem.itemType(at: file) {
    case .regularFile:
      break
    case .missing:
      throw PetLibraryError(.sourceUnavailable, detail: ["reason": "missing"])
    case .symbolicLink:
      throw PetLibraryError(.unsafePackage, detail: ["reason": "symbolic_link"])
    case .directory, .other:
      throw PetLibraryError(.unsupportedSource, detail: ["reason": "not_a_package"])
    }
    guard try fileSize(at: file) <= PetLibraryPolicy.maximumArchiveBytes else {
      throw PetLibraryError(.oversizedPackage, detail: ["reason": "archive_too_large"])
    }
    do {
      return try fileSystem.readData(at: file, maximumBytes: PetLibraryPolicy.maximumArchiveBytes)
    } catch let error as PetLibraryError {
      throw error
    } catch {
      throw PetLibraryError(.sourceUnavailable, detail: ["reason": "unreadable_file"])
    }
  }

  func extractArchive(_ data: Data, to packageDirectory: URL) throws {
    let reader: ZipArchiveReader
    do {
      reader = try ZipArchiveReader(data: data)
    } catch ZipArchiveError.unsupportedFeature(let feature) {
      throw PetLibraryError(
        .unsafePackage, detail: ["reason": "unsupported_zip_feature", "feature": feature])
    } catch {
      throw PetLibraryError(.unsafePackage, detail: ["reason": "not_a_zip_archive"])
    }
    guard reader.entries.count <= PetLibraryPolicy.maximumArchiveEntries else {
      throw PetLibraryError(.oversizedPackage, detail: ["reason": "too_many_entries"])
    }

    var files: [ZipArchiveEntry] = []
    var seenNames = Set<String>()
    var unpackedBytes = 0
    for entry in reader.entries {
      guard !entry.isEncrypted else {
        throw PetLibraryError(.unsafePackage, detail: ["reason": "encrypted_entry"])
      }
      guard !entry.isSymbolicLink else {
        throw PetLibraryError(.unsafePackage, detail: ["reason": "symbolic_link"])
      }
      let name =
        entry.isDirectory && entry.name.hasSuffix("/") ? String(entry.name.dropLast()) : entry.name
      guard PetSpritePackageLoader.isSafeRelativePath(name) else {
        throw PetLibraryError(.unsafePackage, detail: ["reason": "unsafe_entry_path"])
      }
      guard !entry.isDirectory else { continue }
      let components = name.split(separator: "/").map(String.init)
      guard components.first != PetLibraryPolicy.ignoredArchiveDirectory,
        components.last?.hasPrefix(".") == false
      else {
        continue
      }
      guard seenNames.insert(name.lowercased()).inserted else {
        throw PetLibraryError(.unsafePackage, detail: ["reason": "duplicate_entry"])
      }
      guard entry.uncompressedSize <= PetSpritePackageLoader.maximumSpritesheetBytes else {
        throw PetLibraryError(.oversizedPackage, detail: ["reason": "entry_too_large"])
      }
      unpackedBytes += entry.uncompressedSize
      guard unpackedBytes <= PetLibraryPolicy.maximumUnpackedBytes else {
        throw PetLibraryError(.oversizedPackage, detail: ["reason": "unpacked_too_large"])
      }
      files.append(entry)
    }

    let root: String
    if files.contains(where: { $0.name == "pet.json" }) {
      root = ""
    } else {
      let firstComponents = Set(
        files.compactMap { $0.name.split(separator: "/").first.map(String.init) })
      guard firstComponents.count == 1, let only = firstComponents.first,
        files.contains(where: { $0.name == "\(only)/pet.json" })
      else {
        throw PetLibraryError(.unsafePackage, detail: ["reason": "package_root"])
      }
      root = only + "/"
    }

    for entry in files {
      let relativePath = String(entry.name.dropFirst(root.count))
      let destination = packageDirectory.appendingPathComponent(relativePath, isDirectory: false)
      let contents: Data
      do {
        contents = try reader.extract(entry)
      } catch ZipArchiveError.unsupportedFeature(let feature) {
        throw PetLibraryError(
          .unsafePackage, detail: ["reason": "unsupported_zip_feature", "feature": feature])
      } catch {
        throw PetLibraryError(.unsafePackage, detail: ["reason": "corrupt_entry"])
      }
      try createDirectory(destination.deletingLastPathComponent())
      do {
        try fileSystem.writeData(contents, to: destination)
      } catch {
        throw PetLibraryError(.writeFailed, detail: ["reason": "extract"])
      }
    }
  }

}
