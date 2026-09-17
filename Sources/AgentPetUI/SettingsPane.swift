import Foundation

public enum SettingsPane: String, CaseIterable, Sendable {
  case general
  case pet
  case card
  case connections
  case privacyDiagnostics = "privacy_diagnostics"

  // Panes with real controls today. The other identifiers stay reserved so a restored selection
  // keeps working once those panes gain content; nothing is shown as a placeholder.
  public static let available: [SettingsPane] = [.general, .pet, .card]

  public var title: String {
    switch self {
    case .general: "General"
    case .pet: "Pet"
    case .card: "Cards"
    case .connections: "Connections"
    case .privacyDiagnostics: "Privacy & Diagnostics"
    }
  }

  var symbolName: String {
    switch self {
    case .general: "gearshape"
    case .pet: "pawprint"
    case .card: "rectangle.on.rectangle"
    case .connections: "link"
    case .privacyDiagnostics: "hand.raised"
    }
  }
}
