import XCTest

@testable import AgentPetSprites

final class PetAnimationTests: XCTestCase {
  func testContractRowsFrameCountsAndDurations() {
    let expected: [(PetAnimationState, Int, [Int])] = [
      (.idle, 0, [280, 110, 110, 140, 140, 320]),
      (.runningRight, 1, [120, 120, 120, 120, 120, 120, 120, 220]),
      (.runningLeft, 2, [120, 120, 120, 120, 120, 120, 120, 220]),
      (.waving, 3, [140, 140, 140, 280]),
      (.jumping, 4, [140, 140, 140, 140, 280]),
      (.failed, 5, [140, 140, 140, 140, 140, 140, 140, 240]),
      (.waiting, 6, [150, 150, 150, 150, 150, 260]),
      (.running, 7, [120, 120, 120, 120, 120, 220]),
      (.review, 8, [150, 150, 150, 150, 150, 280]),
    ]

    for (state, row, durations) in expected {
      let frames = PetAnimationTimeline.frames(for: state)
      XCTAssertEqual(frames.map(\.row), Array(repeating: row, count: durations.count))
      XCTAssertEqual(frames.map(\.column), Array(0..<durations.count))
      XCTAssertEqual(
        frames.map { Int(($0.duration * 1_000).rounded()) },
        durations,
        "Unexpected timing for \(state)"
      )
    }
  }

  func testIdleLoopsAtSixTimesContractSpeed() throws {
    let timeline = PetAnimationTimeline(state: .idle, reducedMotion: false)

    XCTAssertEqual(timeline.frames.count, 6)
    XCTAssertEqual(timeline.loopStartIndex, 0)
    XCTAssertEqual(try XCTUnwrap(timeline.sample(at: 0)).frame.column, 0)
    XCTAssertEqual(try XCTUnwrap(timeline.sample(at: 1.681)).frame.column, 1)
    XCTAssertEqual(try XCTUnwrap(timeline.sample(at: 6.601)).frame.column, 0)
  }

  func testActionPlaysThreeCyclesThenSettlesIntoSlowIdle() throws {
    let timeline = PetAnimationTimeline(state: .running, reducedMotion: false)

    XCTAssertEqual(timeline.frames.count, 24)
    XCTAssertEqual(timeline.loopStartIndex, 18)
    XCTAssertEqual(try XCTUnwrap(timeline.sample(at: 0)).frame.row, 7)
    XCTAssertEqual(try XCTUnwrap(timeline.sample(at: 2.461)).frame.row, 0)
    XCTAssertEqual(try XCTUnwrap(timeline.sample(at: 2.461 + 6.6)).frame.row, 0)
    XCTAssertEqual(try XCTUnwrap(timeline.sample(at: 2.461 + 6.6)).frame.column, 0)
  }

  func testReducedMotionStopsOnFirstStateFrame() throws {
    let timeline = PetAnimationTimeline(state: .failed, reducedMotion: true)

    XCTAssertEqual(timeline.frames.count, 1)
    XCTAssertNil(timeline.loopStartIndex)
    XCTAssertEqual(try XCTUnwrap(timeline.sample(at: 100)).frame.row, 5)
    XCTAssertNil(try XCTUnwrap(timeline.sample(at: 100)).remainingDuration)
  }

  func testGazeUsesAppKitCoordinatesAndOnlySupportedStates() {
    XCTAssertEqual(
      PetGazeResolver.pose(
        deltaX: 0,
        deltaY: 10,
        deadZoneRadius: 1,
        version: .v2,
        state: .idle
      ),
      PetGazePose(row: 9, column: 0, sector: 0)
    )
    XCTAssertEqual(
      PetGazeResolver.pose(
        deltaX: 10,
        deltaY: 0,
        deadZoneRadius: 1,
        version: .v2,
        state: .running
      ),
      PetGazePose(row: 9, column: 4, sector: 4)
    )
    XCTAssertEqual(
      PetGazeResolver.pose(
        deltaX: 0,
        deltaY: -10,
        deadZoneRadius: 1,
        version: .v2,
        state: .waving
      ),
      PetGazePose(row: 10, column: 0, sector: 8)
    )
    XCTAssertNil(
      PetGazeResolver.pose(
        deltaX: 0,
        deltaY: 10,
        deadZoneRadius: 1,
        version: .v1,
        state: .idle
      )
    )
    XCTAssertNil(
      PetGazeResolver.pose(
        deltaX: 0,
        deltaY: 10,
        deadZoneRadius: 1,
        version: .v2,
        state: .waiting
      )
    )
    XCTAssertNil(
      PetGazeResolver.pose(
        deltaX: 1,
        deltaY: 1,
        deadZoneRadius: 2,
        version: .v2,
        state: .idle
      )
    )
  }
}
