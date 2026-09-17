import Foundation

public struct PetDownloadResponse: Equatable, Sendable {
  public let statusCode: Int
  public let location: String?
  public let body: Data

  public init(statusCode: Int, location: String? = nil, body: Data = Data()) {
    self.statusCode = statusCode
    self.location = location
    self.body = body
  }
}

public enum PetDownloadError: Error, Equatable, Sendable {
  case transport(code: Int)
  case bodyTooLarge
  case invalidResponse
}

public protocol PetPackageDownloader: Sendable {
  // Performs one GET without following redirects; a 3xx comes back as the response.
  func fetch(_ url: URL, maximumBytes: Int) throws -> PetDownloadResponse
}

public struct URLSessionPetPackageDownloader: PetPackageDownloader {
  public init() {}

  public func fetch(_ url: URL, maximumBytes: Int) throws -> PetDownloadResponse {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.timeoutIntervalForRequest = PetLibraryPolicy.requestTimeout
    configuration.timeoutIntervalForResource = PetLibraryPolicy.resourceTimeout
    let collector = ResponseCollector(maximumBytes: maximumBytes)
    let session = URLSession(configuration: configuration, delegate: collector, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    session.dataTask(with: request).resume()
    return try collector.wait()
  }
}

private final class ResponseCollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private let completion = DispatchSemaphore(value: 0)
  private let maximumBytes: Int
  private var statusCode = 0
  private var location: String?
  private var body = Data()
  private var failure: PetDownloadError?

  init(maximumBytes: Int) {
    self.maximumBytes = maximumBytes
  }

  func wait() throws -> PetDownloadResponse {
    completion.wait()
    lock.lock()
    defer { lock.unlock() }
    if let failure { throw failure }
    return PetDownloadResponse(statusCode: statusCode, location: location, body: body)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    guard let http = response as? HTTPURLResponse else {
      record(failure: .invalidResponse)
      completionHandler(.cancel)
      return
    }
    lock.lock()
    statusCode = http.statusCode
    location = http.value(forHTTPHeaderField: "Location")
    lock.unlock()
    if http.expectedContentLength > Int64(maximumBytes) {
      record(failure: .bodyTooLarge)
      completionHandler(.cancel)
      return
    }
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    lock.lock()
    body.append(data)
    let tooLarge = body.count > maximumBytes
    if tooLarge { failure = .bodyTooLarge }
    lock.unlock()
    if tooLarge { dataTask.cancel() }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error {
      lock.lock()
      if failure == nil { failure = .transport(code: (error as NSError).code) }
      lock.unlock()
    }
    completion.signal()
  }

  private func record(failure: PetDownloadError) {
    lock.lock()
    if self.failure == nil { self.failure = failure }
    lock.unlock()
  }
}
