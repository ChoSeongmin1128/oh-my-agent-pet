import AgentPetLibrary
import AgentPetTestSupport
import Foundation
import XCTest

final class LibraryFixture {
  let root: URL
  let paths: PetLibraryPaths
  let fileSystem: FailingFileSystem
  let downloader: FakeDownloader
  private(set) var installedAt = Date(timeIntervalSince1970: 1_700_000_000)
  private var stageCounter = 0

  init() throws {
    root = try PetPackageFixture.temporaryDirectory(prefix: "omapet-library")
    paths = PetLibraryPaths(
      applicationSupportDirectory: root.appendingPathComponent("Application Support"))
    fileSystem = FailingFileSystem()
    downloader = FakeDownloader()
  }

  var service: PetLibraryService {
    let counter = StageCounter()
    return PetLibraryService(
      paths: paths,
      fileSystem: fileSystem,
      downloader: downloader,
      now: { [installedAt] in installedAt },
      makeStageIdentifier: { counter.next() }
    )
  }

  func advanceClock(_ seconds: TimeInterval = 60) {
    installedAt = installedAt.addingTimeInterval(seconds)
  }

  func sourceDirectory(_ name: String) -> URL {
    root.appendingPathComponent("sources", isDirectory: true)
      .appendingPathComponent(name, isDirectory: true)
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}

final class StageCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func next() -> String {
    lock.lock()
    defer { lock.unlock() }
    value += 1
    return "stage-\(value)"
  }
}

final class FailingFileSystem: PetLibraryFileSystem, @unchecked Sendable {
  enum Operation: Equatable {
    case copyFile
    case moveItem
    case writeData
    case createDirectory
    case removeItem
  }

  struct InjectedFailure: Error {}

  private let base = DefaultPetLibraryFileSystem()
  private let lock = NSLock()
  private var failures: [Operation: Int] = [:]
  private(set) var log: [Operation] = []

  func fail(_ operation: Operation, times: Int = 1) {
    lock.lock()
    failures[operation] = times
    lock.unlock()
  }

  private func check(_ operation: Operation) throws {
    lock.lock()
    defer { lock.unlock() }
    log.append(operation)
    if let remaining = failures[operation], remaining > 0 {
      failures[operation] = remaining - 1
      throw InjectedFailure()
    }
  }

  func itemType(at url: URL) -> PetLibraryItemType { base.itemType(at: url) }
  func fileSize(at url: URL) throws -> Int { try base.fileSize(at: url) }
  func contentsOfDirectory(at url: URL) throws -> [URL] { try base.contentsOfDirectory(at: url) }
  func createDirectory(at url: URL) throws {
    try check(.createDirectory)
    try base.createDirectory(at: url)
  }
  func copyFile(at source: URL, to destination: URL) throws {
    try check(.copyFile)
    try base.copyFile(at: source, to: destination)
  }
  func moveItem(at source: URL, to destination: URL) throws {
    try check(.moveItem)
    try base.moveItem(at: source, to: destination)
  }
  func removeItem(at url: URL) throws {
    try check(.removeItem)
    try base.removeItem(at: url)
  }
  func readData(at url: URL, maximumBytes: Int) throws -> Data {
    try base.readData(at: url, maximumBytes: maximumBytes)
  }
  func writeData(_ data: Data, to url: URL) throws {
    try check(.writeData)
    try base.writeData(data, to: url)
  }
}

final class FakeDownloader: PetPackageDownloader, @unchecked Sendable {
  private let lock = NSLock()
  private var responses: [String: PetDownloadResponse] = [:]
  private var failures: [String: PetDownloadError] = [:]
  private(set) var requests: [URL] = []

  func respond(to url: String, with response: PetDownloadResponse) {
    lock.lock()
    responses[url] = response
    lock.unlock()
  }

  func fail(_ url: String, with error: PetDownloadError) {
    lock.lock()
    failures[url] = error
    lock.unlock()
  }

  func fetch(_ url: URL, maximumBytes: Int) throws -> PetDownloadResponse {
    lock.lock()
    defer { lock.unlock() }
    requests.append(url)
    if let failure = failures[url.absoluteString] { throw failure }
    guard let response = responses[url.absoluteString] else {
      return PetDownloadResponse(statusCode: 404, body: Data(#"{"error":"pet not found"}"#.utf8))
    }
    if response.body.count > maximumBytes { throw PetDownloadError.bodyTooLarge }
    return response
  }
}

func directorySnapshot(_ directory: URL) throws -> [String: Data] {
  var snapshot: [String: Data] = [:]
  let root = directory.resolvingSymlinksInPath().path + "/"
  let enumerator = FileManager.default.enumerator(
    at: directory, includingPropertiesForKeys: [.isRegularFileKey])!
  for case let url as URL in enumerator {
    guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
      continue
    }
    let resolved = url.resolvingSymlinksInPath().path
    XCTAssertTrue(resolved.hasPrefix(root), "\(resolved) is outside \(root)")
    snapshot[String(resolved.dropFirst(root.count))] = try Data(contentsOf: url)
  }
  return snapshot
}

func assertLibraryError(
  _ expression: @autoclosure () throws -> some Any,
  _ code: PetLibraryError.Code,
  reason: String? = nil,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  do {
    _ = try expression()
    XCTFail("Expected \(code.rawValue)", file: file, line: line)
  } catch let error as PetLibraryError {
    XCTAssertEqual(error.code, code, "\(error.detail)", file: file, line: line)
    if let reason {
      XCTAssertEqual(error.detail["reason"], reason, file: file, line: line)
    }
  } catch {
    XCTFail("Unexpected error \(error)", file: file, line: line)
  }
}
