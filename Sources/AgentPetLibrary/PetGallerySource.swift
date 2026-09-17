import AgentPetSprites
import Foundation

public struct PetGalleryReference: Equatable, Sendable {
  public let petID: String
  public let pageURL: URL
  public let metadataURL: URL
}

struct PetGalleryDownload: Equatable, Sendable {
  let reference: PetGalleryReference
  let downloadURL: URL
  let ownerHandle: String?
}

enum PetGalleryURLParser {
  // Accepts the page link users copy (`https://codex-pets.net/#/pets/<id>`), the API metadata
  // link and the API download link. Anything else on the host is not a pet reference.
  static func parse(_ url: URL) -> PetGalleryReference? {
    guard PetURLPolicy.isAllowed(url),
      let host = url.host?.lowercased(),
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
      return nil
    }
    let route = components.percentEncodedFragment.map { "/" + $0 } ?? components.path
    let segments =
      route
      .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: true).first
      .map { $0.split(separator: "/").map(String.init) } ?? []
    let petsIndex = segments.firstIndex(of: "pets")
    guard let petsIndex, petsIndex + 1 < segments.count else { return nil }
    let leading = Array(segments[..<petsIndex])
    guard leading.isEmpty || leading == ["api"] else { return nil }
    let trailing = Array(segments[(petsIndex + 2)...])
    guard trailing.isEmpty || trailing == ["download"] else { return nil }
    let candidate = segments[petsIndex + 1].removingPercentEncoding ?? segments[petsIndex + 1]
    guard PetSpritePackageLoader.isValidPackageIdentifier(candidate),
      let pageURL = URL(string: "https://\(host)/#/pets/\(candidate)"),
      let metadataURL = URL(string: "https://\(host)/api/pets/\(candidate)")
    else {
      return nil
    }
    return PetGalleryReference(petID: candidate, pageURL: pageURL, metadataURL: metadataURL)
  }
}

enum PetURLPolicy {
  static func isAllowed(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == PetLibraryPolicy.allowedScheme,
      let host = url.host?.lowercased(),
      url.user == nil,
      url.password == nil,
      url.port == nil || url.port == 443
    else {
      return false
    }
    return PetLibraryPolicy.allowedHosts.contains(host)
  }
}

struct PetGalleryClient: Sendable {
  let downloader: PetPackageDownloader

  func fetchFollowingRedirects(_ initial: URL, maximumBytes: Int) throws -> PetDownloadResponse {
    var url = initial
    for _ in 0...PetLibraryPolicy.maximumRedirects {
      guard PetURLPolicy.isAllowed(url) else {
        throw PetLibraryError(.urlNotAllowed, detail: ["host": url.host ?? ""])
      }
      let response: PetDownloadResponse
      do {
        response = try downloader.fetch(url, maximumBytes: maximumBytes)
      } catch let error as PetDownloadError {
        throw Self.libraryError(for: error)
      }
      guard Self.redirectStatusCodes.contains(response.statusCode) else { return response }
      guard let location = response.location,
        let next = URL(string: location, relativeTo: url)?.absoluteURL
      else {
        throw PetLibraryError(.downloadFailed, detail: ["reason": "redirect_without_location"])
      }
      url = next
    }
    throw PetLibraryError(
      .redirectLimitExceeded,
      detail: ["limit": "\(PetLibraryPolicy.maximumRedirects)"]
    )
  }

  func resolveDownload(_ reference: PetGalleryReference) throws -> PetGalleryDownload {
    let response = try fetchFollowingRedirects(
      reference.metadataURL,
      maximumBytes: PetLibraryPolicy.maximumMetadataBytes
    )
    switch response.statusCode {
    case 200..<300:
      break
    case 404:
      throw PetLibraryError(.petNotFound, detail: ["petID": reference.petID])
    default:
      throw PetLibraryError(.downloadFailed, detail: ["statusCode": "\(response.statusCode)"])
    }
    guard let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any]
    else {
      throw PetLibraryError(.invalidGalleryResponse, detail: ["reason": "not_json_object"])
    }
    let pet = (object["pet"] as? [String: Any]) ?? object
    guard let downloadPath = pet["downloadUrl"] as? String,
      let downloadURL = URL(string: downloadPath, relativeTo: reference.metadataURL)?.absoluteURL
    else {
      throw PetLibraryError(.invalidGalleryResponse, detail: ["reason": "download_url_missing"])
    }
    guard PetURLPolicy.isAllowed(downloadURL) else {
      throw PetLibraryError(.urlNotAllowed, detail: ["host": downloadURL.host ?? ""])
    }
    return PetGalleryDownload(
      reference: reference,
      downloadURL: downloadURL,
      ownerHandle: pet["ownerHandle"] as? String
    )
  }

  func downloadArchive(_ download: PetGalleryDownload) throws -> Data {
    let response = try fetchFollowingRedirects(
      download.downloadURL,
      maximumBytes: PetLibraryPolicy.maximumArchiveBytes
    )
    guard (200..<300).contains(response.statusCode) else {
      throw PetLibraryError(.downloadFailed, detail: ["statusCode": "\(response.statusCode)"])
    }
    return response.body
  }

  private static let redirectStatusCodes: Set<Int> = [301, 302, 303, 307, 308]

  private static func libraryError(for error: PetDownloadError) -> PetLibraryError {
    switch error {
    case .transport(let code):
      PetLibraryError(.downloadFailed, detail: ["reason": "transport", "errorCode": "\(code)"])
    case .bodyTooLarge:
      PetLibraryError(.oversizedPackage, detail: ["reason": "download_too_large"])
    case .invalidResponse:
      PetLibraryError(.downloadFailed, detail: ["reason": "invalid_response"])
    }
  }
}
