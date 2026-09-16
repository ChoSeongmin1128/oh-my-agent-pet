import Foundation

public enum PetAnimationState: String, CaseIterable, Equatable, Sendable {
  case idle
  case runningRight
  case runningLeft
  case waving
  case jumping
  case failed
  case waiting
  case running
  case review
}

public struct PetAnimationFrame: Equatable, Sendable {
  public let row: Int
  public let column: Int
  public let duration: TimeInterval

  public init(row: Int, column: Int, duration: TimeInterval) {
    self.row = row
    self.column = column
    self.duration = duration
  }
}

public struct PetAnimationSample: Equatable, Sendable {
  public let frame: PetAnimationFrame
  public let remainingDuration: TimeInterval?

  public init(frame: PetAnimationFrame, remainingDuration: TimeInterval?) {
    self.frame = frame
    self.remainingDuration = remainingDuration
  }
}

public struct PetAnimationTimeline: Equatable, Sendable {
  public let frames: [PetAnimationFrame]
  public let loopStartIndex: Int?

  public init(state: PetAnimationState, reducedMotion: Bool) {
    let action = Self.frames(for: state)
    if reducedMotion {
      frames = Array(action.prefix(1))
      loopStartIndex = nil
    } else if state == .idle {
      frames = Self.slowIdleFrames
      loopStartIndex = 0
    } else {
      let burst = Array(repeating: action, count: 3).flatMap { $0 }
      frames = burst + Self.slowIdleFrames
      loopStartIndex = burst.count
    }
  }

  public func sample(at elapsed: TimeInterval) -> PetAnimationSample? {
    guard !frames.isEmpty else { return nil }
    let clampedElapsed = max(0, elapsed)
    let initialDuration = frames.reduce(0) { $0 + $1.duration }
    var position = clampedElapsed
    if let loopStartIndex {
      let loopStart = frames[..<loopStartIndex].reduce(0) { $0 + $1.duration }
      let loopDuration = frames[loopStartIndex...].reduce(0) { $0 + $1.duration }
      if position >= loopStart, loopDuration > 0 {
        position = loopStart + (position - loopStart).truncatingRemainder(dividingBy: loopDuration)
      }
    } else if position >= initialDuration {
      return PetAnimationSample(frame: frames[frames.count - 1], remainingDuration: nil)
    }

    for frame in frames {
      if position < frame.duration {
        return PetAnimationSample(frame: frame, remainingDuration: frame.duration - position)
      }
      position -= frame.duration
    }
    return PetAnimationSample(frame: frames[frames.count - 1], remainingDuration: nil)
  }

  public static func frames(for state: PetAnimationState) -> [PetAnimationFrame] {
    switch state {
    case .idle: makeFrames(row: 0, durations: [280, 110, 110, 140, 140, 320])
    case .runningRight: makeFrames(row: 1, durations: [120, 120, 120, 120, 120, 120, 120, 220])
    case .runningLeft: makeFrames(row: 2, durations: [120, 120, 120, 120, 120, 120, 120, 220])
    case .waving: makeFrames(row: 3, durations: [140, 140, 140, 280])
    case .jumping: makeFrames(row: 4, durations: [140, 140, 140, 140, 280])
    case .failed: makeFrames(row: 5, durations: [140, 140, 140, 140, 140, 140, 140, 240])
    case .waiting: makeFrames(row: 6, durations: [150, 150, 150, 150, 150, 260])
    case .running: makeFrames(row: 7, durations: [120, 120, 120, 120, 120, 220])
    case .review: makeFrames(row: 8, durations: [150, 150, 150, 150, 150, 280])
    }
  }

  private static let slowIdleFrames = frames(for: .idle).map {
    PetAnimationFrame(row: $0.row, column: $0.column, duration: $0.duration * 6)
  }

  private static func makeFrames(row: Int, durations: [Int]) -> [PetAnimationFrame] {
    durations.enumerated().map {
      PetAnimationFrame(row: row, column: $0.offset, duration: TimeInterval($0.element) / 1_000)
    }
  }
}

public struct PetGazePose: Equatable, Sendable {
  public let row: Int
  public let column: Int
  public let sector: Int

  public init(row: Int, column: Int, sector: Int) {
    self.row = row
    self.column = column
    self.sector = sector
  }
}

public enum PetGazeResolver {
  public static func pose(
    deltaX: Double,
    deltaY: Double,
    deadZoneRadius: Double,
    version: PetSpriteVersion,
    state: PetAnimationState
  ) -> PetGazePose? {
    guard version.supportsGaze,
      [.idle, .running, .waving].contains(state),
      hypot(deltaX, deltaY) > max(0, deadZoneRadius)
    else {
      return nil
    }
    var angle = atan2(deltaX, deltaY)
    if angle < 0 { angle += 2 * .pi }
    let sector = Int((angle / (.pi / 8)).rounded()) % 16
    return PetGazePose(row: 9 + sector / 8, column: sector % 8, sector: sector)
  }
}
