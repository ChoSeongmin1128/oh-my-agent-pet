import AgentPetCore
import AppKit
import XCTest

@testable import AgentPetUI

@MainActor
final class OverlayContainerViewTests: XCTestCase {
  func testPositionAnchorPreservesLegacyHorizontalAndVerticalPetLocation() {
    let anchor = NSPoint(x: 400, y: 300)
    let horizontalPetFrame = NSRect(origin: .zero, size: DesignTokens.petSize)
    let horizontalPanelOrigin = OverlayPositionGeometry.panelOrigin(
      anchorOrigin: anchor,
      petFrame: horizontalPetFrame,
      isPetHidden: false
    )
    XCTAssertEqual(horizontalPanelOrigin, anchor, "legacy horizontal panel origin was pet origin")
    XCTAssertEqual(
      OverlayPositionGeometry.anchorOrigin(
        panelOrigin: horizontalPanelOrigin,
        petFrame: horizontalPetFrame,
        isPetHidden: false
      ),
      anchor
    )

    let verticalPetFrame = NSRect(
      x: 95,
      y: DesignTokens.cardHeight + DesignTokens.spaceM,
      width: DesignTokens.petSize.width,
      height: DesignTokens.petSize.height
    )
    let verticalPanelOrigin = OverlayPositionGeometry.panelOrigin(
      anchorOrigin: anchor,
      petFrame: verticalPetFrame,
      isPetHidden: false
    )
    XCTAssertNotEqual(verticalPanelOrigin, anchor)
    XCTAssertEqual(
      OverlayPositionGeometry.anchorOrigin(
        panelOrigin: verticalPanelOrigin,
        petFrame: verticalPetFrame,
        isPetHidden: false
      ),
      anchor
    )
  }

  func testCardOnlyPositionAnchorIsPanelOrigin() {
    let panelOrigin = NSPoint(x: 120, y: 240)
    let arbitraryPetFrame = NSRect(x: 95, y: 70, width: 78, height: 78)

    XCTAssertEqual(
      OverlayPositionGeometry.anchorOrigin(
        panelOrigin: panelOrigin,
        petFrame: arbitraryPetFrame,
        isPetHidden: true
      ),
      panelOrigin
    )
    XCTAssertEqual(
      OverlayPositionGeometry.panelOrigin(
        anchorOrigin: panelOrigin,
        petFrame: arbitraryPetFrame,
        isPetHidden: true
      ),
      panelOrigin
    )
  }

  func testPetVisibilityTransitionKeepsPanelOriginAndConvertsStoredAnchorMeaning() {
    let panelOrigin = NSPoint(x: 120, y: 240)
    let visiblePetFrame = NSRect(x: 95, y: 70, width: 78, height: 78)
    let visibleAnchor = OverlayPositionGeometry.anchorOrigin(
      panelOrigin: panelOrigin,
      petFrame: visiblePetFrame,
      isPetHidden: false
    )
    let hiddenAnchor = OverlayPositionGeometry.anchorOrigin(
      panelOrigin: panelOrigin,
      petFrame: visiblePetFrame,
      isPetHidden: true
    )

    XCTAssertEqual(visibleAnchor, NSPoint(x: 215, y: 310))
    XCTAssertEqual(hiddenAnchor, panelOrigin)
    XCTAssertNotEqual(visibleAnchor, hiddenAnchor)
    XCTAssertEqual(
      OverlayPositionGeometry.panelOrigin(
        anchorOrigin: hiddenAnchor,
        petFrame: visiblePetFrame,
        isPetHidden: true
      ),
      panelOrigin
    )
  }

  func testVerticalIsDefaultAndSupportsZeroOneTwoAndSixTasks() {
    let container = OverlayContainerView(frame: .zero)

    update(container, tasks: [], mode: .one)
    XCTAssertEqual(container.layoutMode, .vertical)
    XCTAssertEqual(container.preferredSize, DesignTokens.petSize)

    update(container, tasks: tasks(1), mode: .one)
    XCTAssertEqual(
      container.preferredSize,
      NSSize(
        width: DesignTokens.cardWidth,
        height: DesignTokens.petSize.height + DesignTokens.spaceM + DesignTokens.cardHeight
      ))
    XCTAssertEqual(
      container.petView.frame,
      NSRect(
        x: (DesignTokens.cardWidth - DesignTokens.petSize.width) / 2,
        y: DesignTokens.cardHeight + DesignTokens.spaceM,
        width: DesignTokens.petSize.width,
        height: DesignTokens.petSize.height
      ))

    update(container, tasks: tasks(2), mode: .one)
    XCTAssertEqual(
      container.preferredSize.height,
      DesignTokens.petSize.height + DesignTokens.spaceM + DesignTokens.cardHeight
        + DesignTokens.cardDepthLayerOffset
    )
    XCTAssertEqual(container.cardDepthHintView.layerCount, 1)
    XCTAssertEqual(
      container.petView.frame.minY,
      DesignTokens.cardHeight + DesignTokens.cardDepthLayerOffset + DesignTokens.spaceM)

    update(container, tasks: tasks(6), mode: .many)
    XCTAssertEqual(
      container.preferredSize.height,
      DesignTokens.petSize.height + DesignTokens.spaceM
        + CGFloat(DesignTokens.maximumVisibleCards) * DesignTokens.cardHeight
        + CGFloat(DesignTokens.maximumVisibleCards - 1) * DesignTokens.spaceS
    )
    XCTAssertEqual(container.cardDepthHintView.layerCount, 0)
    XCTAssertEqual(
      container.petView.frame.minY,
      CGFloat(DesignTokens.maximumVisibleCards) * DesignTokens.cardHeight
        + CGFloat(DesignTokens.maximumVisibleCards - 1) * DesignTokens.spaceS
        + DesignTokens.spaceM)
  }

  func testHorizontalLayoutKeepsExistingSideBySideGeometry() {
    let container = OverlayContainerView(frame: .zero)

    update(container, tasks: tasks(1), mode: .one, layout: .horizontal)

    XCTAssertEqual(
      container.preferredSize.width,
      DesignTokens.petSize.width + DesignTokens.spaceM + DesignTokens.cardWidth)
    XCTAssertEqual(container.preferredSize.height, DesignTokens.petSize.height)
    container.layoutSubtreeIfNeeded()
    XCTAssertEqual(container.petView.frame.origin, .zero)
  }

  func testDepthHintOnlyAppearsForCollapsedOneModeWithAdditionalTasks() {
    let container = OverlayContainerView(frame: .zero)

    update(container, tasks: tasks(1), mode: .one)
    XCTAssertTrue(container.cardDepthHintView.isHidden)

    update(container, tasks: tasks(2), mode: .one)
    XCTAssertFalse(container.cardDepthHintView.isHidden)
    XCTAssertEqual(container.cardDepthHintView.layerCount, 1)

    update(container, tasks: tasks(6), mode: .one)
    XCTAssertEqual(container.cardDepthHintView.layerCount, 2)
    XCTAssertNil(container.cardDepthHintView.hitTest(NSPoint(x: 10, y: 10)))
    XCTAssertFalse(container.cardDepthHintView.isAccessibilityElement())

    update(container, tasks: tasks(6), mode: .one, isDepthHintEnabled: false)
    XCTAssertTrue(container.cardDepthHintView.isHidden)

    update(container, tasks: tasks(6), mode: .many)
    XCTAssertTrue(container.cardDepthHintView.isHidden)

    update(container, tasks: tasks(6), mode: .none)
    XCTAssertTrue(container.cardDepthHintView.isHidden)

    update(container, tasks: tasks(6), mode: .one, expanded: true)
    XCTAssertTrue(container.cardDepthHintView.isHidden)
  }

  func testHiddenPetRemovesPetSpaceAndDisclosureStillControlsExpansion() {
    let container = OverlayContainerView(frame: .zero)
    let two = tasks(2)

    container.setPetHidden(true)
    update(container, tasks: two, mode: .one)

    XCTAssertTrue(container.petView.isHidden)
    XCTAssertEqual(container.preferredSize.width, DesignTokens.cardWidth)
    XCTAssertEqual(
      container.preferredSize.height,
      DesignTokens.cardHeight + DesignTokens.cardDepthLayerOffset
        + DesignTokens.cardDisclosureHeight)
    XCTAssertFalse(container.disclosureButton.isHidden)
    XCTAssertEqual(container.disclosureButton.accessibilityLabel(), "Show all agent tasks")

    update(container, tasks: two, mode: .one, expanded: true)
    XCTAssertEqual(container.disclosureButton.accessibilityLabel(), "Show fewer agent tasks")
    XCTAssertEqual(
      container.preferredSize.height,
      2 * DesignTokens.cardHeight + DesignTokens.spaceS + DesignTokens.cardDisclosureHeight)
    XCTAssertTrue(container.cardDepthHintView.isHidden)

    update(container, tasks: tasks(1), mode: .one)
    XCTAssertTrue(container.disclosureButton.isHidden)
    XCTAssertEqual(container.preferredSize.height, DesignTokens.cardHeight)

    update(container, tasks: [], mode: .one)
    XCTAssertTrue(container.isEmpty)
    XCTAssertEqual(container.preferredSize, .zero)

    container.setPetHidden(false)
    XCTAssertFalse(container.petView.isHidden)
  }

  func testCornerRadiusIsIndependentOfContainerHeight() {
    XCTAssertEqual(CardShape.cornerRadius, DesignTokens.cornerCard)
    XCTAssertGreaterThan(CardShape.cornerRadius, 14)
    XCTAssertLessThan(CardShape.cornerRadius, DesignTokens.cardHeight / 2)
  }

  private func update(
    _ container: OverlayContainerView,
    tasks: [AgentTaskSnapshot],
    mode: CardDisplayMode,
    layout: OverlayLayout = .defaultValue,
    isDepthHintEnabled: Bool = OverlayPreferences.defaultCardDepthHintEnabled,
    expanded: Bool = false
  ) {
    let presenter = OverlayPresenter()
    container.update(
      presentation: presenter.makePresentation(
        tasks: tasks,
        representative: RepresentativeTaskSelector().select(from: tasks),
        savedMode: mode,
        isTemporarilyExpanded: expanded
      ),
      layout: layout,
      isCardDepthHintEnabled: isDepthHintEnabled,
      onOpen: { _ in },
      onPetClick: {},
      onDragEnded: {}
    )
    container.layoutSubtreeIfNeeded()
  }

  private func tasks(_ count: Int) -> [AgentTaskSnapshot] {
    (0..<count).map { task(id: "task-\($0)", prompt: TimeInterval(count - $0)) }
  }

  private func task(id: String, prompt: TimeInterval) -> AgentTaskSnapshot {
    let base = Date(timeIntervalSince1970: 1_000)
    return AgentTaskSnapshot(
      identity: TaskIdentity(
        provider: ProviderIdentifier("claude")!,
        profileID: "default",
        dataRoot: "/fixture",
        taskID: id,
        executionID: id,
        turnID: "turn"
      ),
      title: "Task \(id)",
      work: .running,
      result: .none,
      waiting: .none,
      lastPromptAt: base.addingTimeInterval(prompt),
      interventionRequestedAt: nil,
      completedAt: nil,
      updatedAt: base.addingTimeInterval(prompt),
      hasUnseenCompletion: false
    )
  }
}
