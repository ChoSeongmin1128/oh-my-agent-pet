import AgentPetCore
import AgentPetProviders
import Foundation

public struct ClaudeConnectionInspector: ProviderConnectionInspecting {
  public let identifier = ProviderIdentifier.claude
  private let service: ClaudeSetupService

  public init(
    homeDirectory: URL,
    environment: [String: String],
    executableURL: URL
  ) {
    service = ClaudeSetupService(
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
        case .connectedButDisabled:
          return ProviderConnectionStatus(
            provider: identifier,
            state: .needsAttention,
            detailCode: "hooks_disabled"
          )
        case .needsRepair:
          return ProviderConnectionStatus(
            provider: identifier,
            state: .needsAttention,
            detailCode: "hooks_need_repair"
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
    let settingsURL = service.settingsURL
    return FileManager.default.fileExists(atPath: settingsURL.path)
      ? [settingsURL] : [settingsURL.deletingLastPathComponent()]
  }
}
