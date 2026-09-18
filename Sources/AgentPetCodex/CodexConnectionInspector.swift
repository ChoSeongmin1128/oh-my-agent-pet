import AgentPetCore
import AgentPetProviders
import Foundation

public struct CodexConnectionInspector: ProviderConnectionInspecting {
  public let identifier = ProviderIdentifier.codex
  private let service: CodexSetupService

  public init(
    homeDirectory: URL,
    environment: [String: String],
    executableURL: URL
  ) {
    service = CodexSetupService(
      homeDirectory: homeDirectory,
      environment: environment,
      executableURL: executableURL
    )
  }

  public func connectionStatus() async -> ProviderConnectionStatus {
    await Task.detached {
      do {
        let status = try service.status().status
        switch status {
        case .connected:
          return ProviderConnectionStatus(provider: identifier, state: .connected)
        case .notConfigured:
          return ProviderConnectionStatus(provider: identifier, state: .notConfigured)
        case .needsTrust:
          return ProviderConnectionStatus(
            provider: identifier,
            state: .needsAttention,
            detailCode: "hooks_need_trust"
          )
        case .needsRepair:
          return ProviderConnectionStatus(
            provider: identifier,
            state: .needsAttention,
            detailCode: "hooks_need_repair"
          )
        case .codexUnavailable:
          return ProviderConnectionStatus(
            provider: identifier,
            state: .unavailable,
            detailCode: "codex_unavailable"
          )
        }
      } catch {
        return ProviderConnectionStatus(
          provider: identifier,
          state: .unavailable,
          detailCode: "status_failed"
        )
      }
    }.value
  }

  public func watchedURLs() -> [URL] {
    let hooksURL = service.hooksURL
    return FileManager.default.fileExists(atPath: hooksURL.path)
      ? [hooksURL] : [hooksURL.deletingLastPathComponent()]
  }
}
