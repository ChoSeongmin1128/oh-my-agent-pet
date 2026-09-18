import AgentPetClaude
import AgentPetCodex
import AgentPetCore
import AgentPetLibrary
import Foundation

struct OmapetDoctor {
  let claudeSetupService: ClaudeSetupService
  let codexSetupService: CodexSetupService
  let petService: PetLibraryService
  let eventsURL: URL

  func inspect(version: String) -> DoctorOutput {
    var checks = [DoctorCheck(id: "runtime", status: "pass", detail: nil)]
    checks.append(connectionCheck(provider: .claude))
    checks.append(connectionCheck(provider: .codex))

    let resolution = petService.resolveSelection()
    checks.append(
      DoctorCheck(
        id: "pet_selection",
        status: resolution.issue == nil ? "pass" : "warning",
        detail: diagnosticCode(for: resolution.issue)
      )
    )
    checks.append(eventLogCheck())

    let status =
      checks.contains(where: { $0.status == "fail" })
      ? "fail"
      : checks.contains(where: { $0.status == "warning" }) ? "warning" : "pass"
    return DoctorOutput(status: status, version: version, checks: checks)
  }

  private func connectionCheck(provider: ProviderIdentifier) -> DoctorCheck {
    do {
      if provider == .claude {
        switch try claudeSetupService.status().status {
        case .connected:
          return DoctorCheck(id: "claude_connection", status: "pass", detail: nil)
        case .notConfigured:
          return DoctorCheck(id: "claude_connection", status: "warning", detail: "not_configured")
        case .connectedButDisabled:
          return DoctorCheck(id: "claude_connection", status: "warning", detail: "hooks_disabled")
        case .needsRepair:
          return DoctorCheck(id: "claude_connection", status: "warning", detail: "needs_repair")
        }
      }
      switch try codexSetupService.status().status {
      case .connected:
        return DoctorCheck(id: "codex_connection", status: "pass", detail: nil)
      case .notConfigured:
        return DoctorCheck(id: "codex_connection", status: "warning", detail: "not_configured")
      case .needsTrust:
        return DoctorCheck(id: "codex_connection", status: "warning", detail: "needs_trust")
      case .needsRepair:
        return DoctorCheck(id: "codex_connection", status: "warning", detail: "needs_repair")
      case .codexUnavailable:
        return DoctorCheck(id: "codex_connection", status: "warning", detail: "unavailable")
      }
    } catch {
      return DoctorCheck(
        id: provider == .claude ? "claude_connection" : "codex_connection",
        status: "fail",
        detail: "status_failed"
      )
    }
  }

  private func eventLogCheck() -> DoctorCheck {
    guard FileManager.default.fileExists(atPath: eventsURL.path) else {
      return eventLockCheck()
    }
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: eventsURL.path)
      guard attributes[.type] as? FileAttributeType == .typeRegular else {
        return DoctorCheck(id: "event_log", status: "fail", detail: "unsafe_type")
      }
      let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
      guard permissions & 0o077 == 0 else {
        return DoctorCheck(id: "event_log", status: "warning", detail: "permissions_too_open")
      }
      let lock = eventLockCheck()
      return lock.status == "pass"
        ? DoctorCheck(id: "event_log", status: "pass", detail: nil)
        : lock
    } catch {
      return DoctorCheck(id: "event_log", status: "fail", detail: "read_failed")
    }
  }

  private func eventLockCheck() -> DoctorCheck {
    let lockURL = eventsURL.deletingLastPathComponent().appendingPathComponent(".events.lock")
    guard FileManager.default.fileExists(atPath: lockURL.path) else {
      return DoctorCheck(id: "event_log", status: "pass", detail: "not_created")
    }
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: lockURL.path)
      guard attributes[.type] as? FileAttributeType == .typeRegular else {
        return DoctorCheck(id: "event_log", status: "fail", detail: "unsafe_lock_type")
      }
      let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
      return permissions & 0o077 == 0
        ? DoctorCheck(id: "event_log", status: "pass", detail: nil)
        : DoctorCheck(id: "event_log", status: "warning", detail: "lock_permissions_too_open")
    } catch {
      return DoctorCheck(id: "event_log", status: "fail", detail: "lock_read_failed")
    }
  }

  private func diagnosticCode(for issue: PetSelectionIssue?) -> String? {
    switch issue {
    case .recordMissing?: "record_missing"
    case .packageDamaged?: "package_damaged"
    case .selectionFileCorrupt?: "selection_file_corrupt"
    case .selectionSchemaUnsupported?: "selection_schema_unsupported"
    case nil: nil
    }
  }
}

struct DoctorOutput: Encodable {
  let status: String
  let version: String
  let checks: [DoctorCheck]
}

struct DoctorCheck: Encodable {
  let id: String
  let status: String
  let detail: String?
}
