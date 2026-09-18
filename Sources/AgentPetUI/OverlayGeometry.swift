import CoreGraphics

struct OverlayGeometryMetrics: Equatable, Sendable {
  let petSize: CGSize
  let cardWidth: CGFloat
  let cardHeight: CGFloat
  let petCardSpacing: CGFloat
  let disclosureHeight: CGFloat
  let depthLayerOffset: CGFloat

  @MainActor
  static var designTokens: OverlayGeometryMetrics {
    OverlayGeometryMetrics(
      petSize: DesignTokens.petSize,
      cardWidth: DesignTokens.cardWidth,
      cardHeight: DesignTokens.cardHeight,
      petCardSpacing: DesignTokens.spaceM,
      disclosureHeight: DesignTokens.cardDisclosureHeight,
      depthLayerOffset: DesignTokens.cardDepthLayerOffset
    )
  }
}

struct OverlayGeometryInput: Equatable, Sendable {
  let layout: OverlayLayout
  let isPetHidden: Bool
  let hasCards: Bool
  let cardsHeight: CGFloat
  let depthLayerCount: Int
  let showsDisclosure: Bool
}

struct OverlayGeometryResult: Equatable, Sendable {
  let preferredSize: CGSize
  let petFrame: CGRect
  let depthHintFrame: CGRect
  let cardsFrame: CGRect
  let disclosureFrame: CGRect
}

enum OverlayGeometry {
  static func resolve(
    _ input: OverlayGeometryInput,
    metrics: OverlayGeometryMetrics
  ) -> OverlayGeometryResult {
    let depthHeight = CGFloat(max(0, input.depthLayerCount)) * metrics.depthLayerOffset
    let disclosureHeight = input.showsDisclosure ? metrics.disclosureHeight : 0
    let cardContentHeight = input.hasCards ? input.cardsHeight + depthHeight : 0
    let cardRegionHeight = cardContentHeight + disclosureHeight

    let preferredSize: CGSize
    if input.isPetHidden {
      preferredSize =
        input.hasCards
        ? CGSize(width: metrics.cardWidth, height: cardRegionHeight)
        : .zero
    } else {
      switch input.layout {
      case .vertical:
        preferredSize = CGSize(
          width: input.hasCards
            ? max(metrics.petSize.width, metrics.cardWidth)
            : metrics.petSize.width,
          height: metrics.petSize.height
            + (input.hasCards ? metrics.petCardSpacing + cardRegionHeight : 0)
        )
      case .horizontal:
        preferredSize = CGSize(
          width: metrics.petSize.width
            + (input.hasCards ? metrics.petCardSpacing + metrics.cardWidth : 0),
          height: max(metrics.petSize.height, cardRegionHeight)
        )
      }
    }

    let petFrame: CGRect
    if input.isPetHidden || input.layout == .horizontal {
      petFrame = CGRect(origin: .zero, size: metrics.petSize)
    } else {
      petFrame = CGRect(
        x: (preferredSize.width - metrics.petSize.width) / 2,
        y: cardContentHeight
          + disclosureHeight
          + (input.hasCards ? metrics.petCardSpacing : 0),
        width: metrics.petSize.width,
        height: metrics.petSize.height
      )
    }

    guard input.hasCards else {
      return OverlayGeometryResult(
        preferredSize: preferredSize,
        petFrame: petFrame,
        depthHintFrame: .zero,
        cardsFrame: .zero,
        disclosureFrame: .zero
      )
    }

    let cardsX: CGFloat
    switch input.layout {
    case .vertical:
      cardsX = (preferredSize.width - metrics.cardWidth) / 2
    case .horizontal:
      cardsX = input.isPetHidden ? 0 : metrics.petSize.width + metrics.petCardSpacing
    }

    return OverlayGeometryResult(
      preferredSize: preferredSize,
      petFrame: petFrame,
      depthHintFrame: CGRect(
        x: cardsX,
        y: 0,
        width: metrics.cardWidth,
        height: metrics.cardHeight + depthHeight
      ),
      cardsFrame: CGRect(
        x: cardsX,
        y: depthHeight,
        width: metrics.cardWidth,
        height: input.cardsHeight
      ),
      disclosureFrame: input.showsDisclosure
        ? CGRect(
          x: cardsX,
          y: cardContentHeight,
          width: metrics.cardWidth,
          height: metrics.disclosureHeight
        )
        : .zero
    )
  }
}
