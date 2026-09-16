import AgentPetCore
import Foundation

public enum TaskNavigationPlan: Equatable, Sendable {
  case openDeepLink(URL, fallbackBundleIdentifier: String)
  case runAppleScript(String, fallbackBundleIdentifier: String)
  case activateApplication(bundleIdentifier: String)
  case unavailable
}

public enum TaskNavigationPlanner {
  public static func plan(for target: TaskNavigationTarget?) -> TaskNavigationPlan {
    guard let target else { return .unavailable }
    switch target.surface {
    case .desktop:
      if let deepLink = validatedDesktopDeepLink(target) {
        return .openDeepLink(
          deepLink,
          fallbackBundleIdentifier: target.applicationBundleIdentifier
        )
      }
      return supportedBundleIdentifiers.contains(target.applicationBundleIdentifier)
        ? .activateApplication(bundleIdentifier: target.applicationBundleIdentifier)
        : .unavailable
    case .terminal:
      return terminalPlan(target)
    }
  }

  private static func terminalPlan(_ target: TaskNavigationTarget) -> TaskNavigationPlan {
    switch target.applicationBundleIdentifier {
    case "com.googlecode.iterm2":
      if let sessionID = validatedTerminalSessionID(target.terminalSessionID),
        let url = iTermRevealURL(sessionID: sessionID)
      {
        return .openDeepLink(url, fallbackBundleIdentifier: target.applicationBundleIdentifier)
      }
      if let tty = validatedTTY(target.tty) {
        return .runAppleScript(
          iTermTTYScript(tty: tty),
          fallbackBundleIdentifier: target.applicationBundleIdentifier
        )
      }
      return .activateApplication(bundleIdentifier: target.applicationBundleIdentifier)
    case "com.apple.Terminal":
      guard let tty = validatedTTY(target.tty) else {
        return .activateApplication(bundleIdentifier: target.applicationBundleIdentifier)
      }
      return .runAppleScript(
        terminalTTYScript(tty: tty),
        fallbackBundleIdentifier: target.applicationBundleIdentifier
      )
    default:
      return .unavailable
    }
  }

  private static func validatedDesktopDeepLink(_ target: TaskNavigationTarget) -> URL? {
    guard let rawValue = target.deepLink,
      let components = URLComponents(string: rawValue),
      components.user == nil,
      components.password == nil,
      components.port == nil,
      components.fragment == nil
    else { return nil }
    switch target.applicationBundleIdentifier {
    case "com.openai.codex":
      guard components.scheme == "codex", components.host == "threads",
        components.query == nil,
        UUID(uuidString: String(components.path.dropFirst())) != nil
      else { return nil }
    case "com.anthropic.claudefordesktop":
      guard components.scheme == "claude", components.host == "code",
        components.path == "/continue",
        components.queryItems?.count == 1,
        let sessionID = components.queryItems?.first(where: { $0.name == "session" })?.value,
        sessionID.hasPrefix("local_"),
        UUID(uuidString: String(sessionID.dropFirst(6))) != nil
      else { return nil }
    default:
      return nil
    }
    return components.url
  }

  private static func iTermRevealURL(sessionID: String) -> URL? {
    var components = URLComponents()
    components.scheme = "iterm2"
    components.path = "reveal"
    components.queryItems = [URLQueryItem(name: "sessionid", value: sessionID)]
    return components.url
  }

  private static func validatedTerminalSessionID(_ value: String?) -> String? {
    guard let value, !value.isEmpty, value.utf8.count <= 256,
      let separator = value.lastIndex(of: ":"),
      UUID(uuidString: String(value[value.index(after: separator)...])) != nil,
      value.unicodeScalars.allSatisfy({ safeSessionCharacters.contains($0) })
    else { return nil }
    return value
  }

  private static func validatedTTY(_ value: String?) -> String? {
    guard let value, value.utf8.count <= 128, value.hasPrefix("/dev/tty") else {
      return nil
    }
    let suffix = value.dropFirst(8)
    guard !suffix.isEmpty,
      suffix.allSatisfy({ $0.isLetter || $0.isNumber })
    else { return nil }
    return value
  }

  private static func iTermTTYScript(tty: String) -> String {
    """
    tell application id "com.googlecode.iterm2"
      repeat with targetWindow in windows
        repeat with targetTab in tabs of targetWindow
          repeat with targetSession in sessions of targetTab
            if tty of targetSession is "\(tty)" then
              select targetSession
              select targetTab
              tell targetWindow to select
              activate
              return true
            end if
          end repeat
        end repeat
      end repeat
      return false
    end tell
    """
  }

  private static func terminalTTYScript(tty: String) -> String {
    """
    tell application id "com.apple.Terminal"
      repeat with targetWindow in windows
        repeat with targetTab in tabs of targetWindow
          if tty of targetTab is "\(tty)" then
            set selected tab of targetWindow to targetTab
            set index of targetWindow to 1
            activate
            return true
          end if
        end repeat
      end repeat
      return false
    end tell
    """
  }

  private static let supportedBundleIdentifiers: Set<String> = [
    "com.openai.codex",
    "com.anthropic.claudefordesktop",
  ]
  private static let safeSessionCharacters = CharacterSet.alphanumerics.union(
    CharacterSet(charactersIn: "-_:.")
  )
}
