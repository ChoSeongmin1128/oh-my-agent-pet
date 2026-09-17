import AgentPetCore
import AppKit
import XCTest

@testable import AgentPetUI

@MainActor
final class OverlayContainerViewTests: XCTestCase {
  func testHiddenPetRemovesPetSpaceAndShowsDisclosureOnlyForMultipleTasks() {
    let container = OverlayContainerView(frame: .zero)
    let presenter = OverlayPresenter()
    let one = [task(id: "a", prompt: 10)]
    let two = one + [task(id: "b", prompt: 5)]

    container.update(
      presentation: presenter.makePresentation(
        tasks: two, representative: RepresentativeTaskSelector().select(from: two), savedMode: .one,
        isTemporarilyExpanded: false),
      onOpen: { _ in }, onPetClick: {}, onDragEnded: {})
    XCTAssertEqual(
      container.preferredSize.width,
      DesignTokens.petSize.width + DesignTokens.spaceM + DesignTokens.cardWidth)
    XCTAssertTrue(container.disclosureButton.isHidden, "pet present: pet click expands")
    XCTAssertFalse(container.isEmpty)

    container.setPetHidden(true)
    container.update(
      presentation: presenter.makePresentation(
        tasks: two, representative: RepresentativeTaskSelector().select(from: two), savedMode: .one,
        isTemporarilyExpanded: false),
      onOpen: { _ in }, onPetClick: {}, onDragEnded: {})
    XCTAssertTrue(container.petView.isHidden)
    XCTAssertEqual(container.preferredSize.width, DesignTokens.cardWidth)
    XCTAssertEqual(
      container.preferredSize.height, DesignTokens.cardHeight + DesignTokens.cardDisclosureHeight)
    XCTAssertFalse(container.disclosureButton.isHidden)
    XCTAssertEqual(container.disclosureButton.accessibilityLabel(), "Show all agent tasks")

    container.update(
      presentation: presenter.makePresentation(
        tasks: two, representative: RepresentativeTaskSelector().select(from: two), savedMode: .one,
        isTemporarilyExpanded: true),
      onOpen: { _ in }, onPetClick: {}, onDragEnded: {})
    XCTAssertEqual(container.disclosureButton.accessibilityLabel(), "Show fewer agent tasks")
    XCTAssertEqual(
      container.preferredSize.height,
      2 * DesignTokens.cardHeight + DesignTokens.spaceS + DesignTokens.cardDisclosureHeight)

    container.update(
      presentation: presenter.makePresentation(
        tasks: one, representative: RepresentativeTaskSelector().select(from: one), savedMode: .one,
        isTemporarilyExpanded: false),
      onOpen: { _ in }, onPetClick: {}, onDragEnded: {})
    XCTAssertTrue(container.disclosureButton.isHidden, "single task: no disclosure")
    XCTAssertEqual(container.preferredSize.height, DesignTokens.cardHeight)

    container.update(
      presentation: presenter.makePresentation(
        tasks: [], representative: nil, savedMode: .one, isTemporarilyExpanded: false),
      onOpen: { _ in }, onPetClick: {}, onDragEnded: {})
    XCTAssertTrue(container.isEmpty)
    XCTAssertEqual(container.preferredSize, .zero)

    container.setPetHidden(false)
    XCTAssertFalse(container.petView.isHidden)
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
