import AgentPetCore
import AppKit
import Foundation

public enum TaskNavigationResult: String, Codable, Equatable, Sendable {
  case exact
  case appOnly = "app_only"
  case failed
}

@MainActor
protocol TaskNavigationBackend: AnyObject {
  func open(_ url: URL) -> Bool
  func runAppleScript(_ source: String) -> Bool
  func activateApplication(bundleIdentifier: String) -> Bool
}

@MainActor
public final class TaskNavigator {
  private let backend: any TaskNavigationBackend
  private var inFlightTaskKeys: Set<String> = []

  public convenience init() {
    self.init(backend: WorkspaceNavigationBackend())
  }

  init(backend: any TaskNavigationBackend) {
    self.backend = backend
  }

  public func navigate(to task: AgentTaskSnapshot) -> TaskNavigationResult {
    let taskKey = task.identity.stableKey
    guard inFlightTaskKeys.insert(taskKey).inserted else { return .failed }
    defer { inFlightTaskKeys.remove(taskKey) }

    switch TaskNavigationPlanner.plan(for: task.navigationTarget) {
    case .openDeepLink(let url, let bundleIdentifier):
      if backend.open(url) { return .exact }
      return backend.activateApplication(bundleIdentifier: bundleIdentifier) ? .appOnly : .failed
    case .runAppleScript(let source, let bundleIdentifier):
      if backend.runAppleScript(source) { return .exact }
      return backend.activateApplication(bundleIdentifier: bundleIdentifier) ? .appOnly : .failed
    case .activateApplication(let bundleIdentifier):
      return backend.activateApplication(bundleIdentifier: bundleIdentifier) ? .appOnly : .failed
    case .unavailable:
      return .failed
    }
  }
}

@MainActor
private final class WorkspaceNavigationBackend: TaskNavigationBackend {
  func open(_ url: URL) -> Bool {
    NSWorkspace.shared.open(url)
  }

  func runAppleScript(_ source: String) -> Bool {
    guard let script = NSAppleScript(source: source) else { return false }
    var error: NSDictionary?
    let result = script.executeAndReturnError(&error)
    return error == nil && result.booleanValue
  }

  func activateApplication(bundleIdentifier: String) -> Bool {
    if let application = NSRunningApplication.runningApplications(
      withBundleIdentifier: bundleIdentifier
    ).first {
      return application.activate()
    }
    guard
      let applicationURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: bundleIdentifier
      )
    else { return false }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(
      at: applicationURL,
      configuration: configuration
    )
    return true
  }
}
