import AgentPetLibrary
import AgentPetSprites
import AppKit
import SwiftUI

struct SettingsRootView: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.settingsSectionSpacing) {
        switch model.pane {
        case .general:
          GeneralSettingsPane(model: model)
        case .pet:
          PetSettingsPane(model: model.petLibrary)
        case .card:
          CardSettingsPane(model: model)
        case .connections, .privacyDiagnostics:
          GeneralSettingsPane(model: model)
        }
      }
      .padding(DesignTokens.settingsPaneInset)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(
      minWidth: DesignTokens.settingsWindowSize.width,
      minHeight: DesignTokens.settingsWindowSize.height
    )
  }
}
