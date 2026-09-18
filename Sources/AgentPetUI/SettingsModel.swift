import AgentPetLibrary
import AppKit
import Combine

@MainActor
public final class SettingsModel: ObservableObject {
  @Published public private(set) var pane: SettingsPane
  @Published public private(set) var overlayState: OverlayMenuState
  public let petLibrary: PetLibraryViewModel
  private var overlayActionHandler: ((OverlayControlAction) -> Void)?

  public init(petLibrary: PetLibraryViewModel, initialPane: SettingsPane = .general) {
    self.petLibrary = petLibrary
    pane = initialPane
    overlayState = OverlayMenuState(
      isVisible: true,
      cardMode: .one,
      layout: .defaultValue,
      isCardDepthHintEnabled: OverlayPreferences.defaultCardDepthHintEnabled
    )
  }

  public func setOverlayActionHandler(_ handler: @escaping (OverlayControlAction) -> Void) {
    overlayActionHandler = handler
  }

  public func updateOverlayState(_ state: OverlayMenuState) {
    overlayState = state
  }

  func perform(_ action: OverlayControlAction) {
    overlayActionHandler?(action)
  }

  func showPane(_ pane: SettingsPane) {
    self.pane = SettingsPane.available.contains(pane) ? pane : .general
  }
}
