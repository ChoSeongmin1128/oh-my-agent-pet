import AgentPetSprites
import AppKit
import SwiftUI

// Reuses the production renderer with a simulated status. It never touches real task state.
struct PetPreviewView: NSViewRepresentable {
  let package: PetSpritePackage?
  let status: TaskVisualStatus

  func makeNSView(context: Context) -> PetView {
    let view = PetView(
      frame: NSRect(
        x: 0, y: 0, width: DesignTokens.settingsPreviewSize,
        height: DesignTokens.settingsPreviewSize))
    view.setAccessibilityLabel("Pet preview")
    return view
  }

  func updateNSView(_ view: PetView, context: Context) {
    view.setSpritePackage(package)
    view.update(with: .preview(status: status))
    view.onClick = nil
  }
}
