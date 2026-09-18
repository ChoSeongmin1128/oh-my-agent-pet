import AgentPetLibrary
import AgentPetSprites
import AppKit
import SwiftUI

struct GeneralSettingsPane: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    SettingsSection("Display") {
      SettingsRow(
        "Show pet and cards",
        description: "Hides the desktop pet and its cards. The menu bar keeps collecting status."
      ) {
        Toggle(
          "",
          isOn: Binding(
            get: { model.overlayState.isVisible },
            set: { _ in model.perform(.toggleVisibility) }
          )
        )
        .labelsHidden()
        .toggleStyle(.switch)
      }
      Divider()
      SettingsRow("Pet position", description: "Moves the pet back to the default corner.") {
        Button("Reset Position") { model.perform(.resetPosition) }
      }
    }
  }
}

struct CardSettingsPane: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    SettingsSection("Cards") {
      SettingsRow(
        "Cards shown",
        description: "One card follows the most urgent task. All cards list every task."
      ) {
        Picker(
          "",
          selection: Binding(
            get: { model.overlayState.cardMode },
            set: { model.perform(.setCardMode($0)) }
          )
        ) {
          Text("One").tag(CardDisplayMode.one)
          Text("All").tag(CardDisplayMode.many)
          Text("None").tag(CardDisplayMode.none)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 200)
      }
      Divider()
      SettingsRow(
        "Layout",
        description: "Places the pet above the cards by default, or beside them."
      ) {
        Picker(
          "",
          selection: Binding(
            get: { model.overlayState.layout },
            set: { model.perform(.setLayout($0)) }
          )
        ) {
          Text("Vertical").tag(OverlayLayout.vertical)
          Text("Side by Side").tag(OverlayLayout.horizontal)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 200)
      }
      Divider()
      SettingsRow(
        "Stack other tasks",
        description: "In One mode, shows a shallow decorative stack when more tasks exist."
      ) {
        Toggle(
          "",
          isOn: Binding(
            get: { model.overlayState.isCardDepthHintEnabled },
            set: { model.perform(.setCardDepthHintEnabled($0)) }
          )
        )
        .labelsHidden()
        .toggleStyle(.switch)
      }
    }
  }
}
