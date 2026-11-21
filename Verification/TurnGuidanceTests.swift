import Foundation
import Testing
@testable import BullseyeCore

private let cornerPath = [Position(x: 0, z: 0), Position(x: 0, z: -10), Position(x: 10, z: -10)]

@Test func turnDistancesFollowTheWalkwayAndReverseCorrectly() throws {
    let plan = TurnRoutePlan(path: cornerPath)
    let turn = try #require(plan.turns.first)
    #expect(plan.turns.count == 1)
    #expect(turn.direction == .right)
    #expect(turn.distance == 10)
    #expect(plan.length == 20)
    #expect(plan.nextTurn(after: 5)?.distance == 10)
    #expect(plan.nextTurn(after: 11) == nil)
    let reversed = TurnRoutePlan(path: Array(cornerPath.reversed()))
    #expect(reversed.turns.first?.direction == .left)
    #expect(reversed.turns.first?.distance == 10)
}

@Test func intermediateRoomMarkersAndRecordingNoiseAreNotTurns() {
    let path = [Position(x: 0, z: 0), Position(x: 0, z: -4), Position(x: 0.2, z: -4.1),
                Position(x: 0.1, z: -4.1), Position(x: 0.1, z: -4.1), Position(x: 0, z: -5),
                Position(x: -0.15, z: -7), Position(x: 0, z: -10)]
    #expect(TurnRoutePlan(path: path).turns.isEmpty)
    // A small sideways reach to record a room sign, then back to the hallway.
    let reach = [Position(x: 0, z: 0), Position(x: 0, z: -5), Position(x: 0.65, z: -5),
                 Position(x: 0, z: -5), Position(x: 0, z: -10)]
    let plan = TurnRoutePlan(path: reach)
    #expect(plan.turns.isEmpty)
    // Filtering turn events does not straighten the geometry used for tracking.
    #expect(plan.path == reach)
}

@Test func mergingThreeStopsCreatesNoTurnOnAStraightHallway() throws {
    var map = Practice.map
    map.points[0].position = Position(x: 0, z: 0)
    map.points[1].position = Position(x: 0, z: -5)
    map.points[2].position = Position(x: 0, z: -10)
    map.links[0].path = [Position(x: 0, z: 0), Position(x: 0.1, z: -4.7), Position(x: 0, z: -5)]
    map.links[1].path = [Position(x: 0, z: -5), Position(x: 0.1, z: -5.2), Position(x: 0, z: -10)]
    let merged = try #require(map.continuousWalkingRoute(map.links).first)
    let geometry = try #require(map.geometry(for: merged))
    #expect(merged.to == map.rooms[0].waypointID)
    #expect(TurnRoutePlan(path: geometry).turns.isEmpty)
}

@Test func eachCornerHasOnlyOneWarningAndOneImmediateTurnCue() throws {
    let turn = try #require(TurnRoutePlan(path: cornerPath).turns.first)
    var voice = TurnAnnouncements()
    let distant = voice.update(turn: turn, progress: 4.9, position: Position(x: 0, z: -4.9))
    #expect(distant == nil)
    let warning = voice.update(turn: turn, progress: 5, position: Position(x: 0, z: -5))
    #expect(warning?.phase == .warning)
    #expect(warning?.text == "In about 5 meters, turn right.")
    for distance in [5.1, 4.9, 5.2, 7, 8, 8.9] {
        let duplicate = voice.update(turn: turn, progress: distance, position: Position(x: 0, z: -Float(distance)))
        #expect(duplicate == nil)
    }
    let now = voice.update(turn: turn, progress: 9.4, position: Position(x: 0, z: -9.4))
    #expect(now?.phase == .turnNow)
    #expect(now?.text == "Turn right now.")
    for distance in [9.4, 9.8, 9.6, 10, 10.2] {
        let duplicate = voice.update(turn: turn, progress: distance, position: turn.position)
        #expect(duplicate == nil)
    }
}

@Test func startingAtACornerSkipsWarningAndPassedCornersStaySilent() throws {
    let turn = try #require(TurnRoutePlan(path: cornerPath).turns.first)
    var voice = TurnAnnouncements()
    let now = voice.update(turn: turn, progress: 10, position: turn.position)
    #expect(now?.phase == .turnNow)
    var missed = TurnAnnouncements()
    let old = missed.update(turn: turn, progress: 11, position: Position(x: 1, z: -10))
    #expect(old == nil)
    var outside = TurnAnnouncements()
    let away = outside.update(turn: turn, progress: 9.5, position: Position(x: -2, z: -9.5))
    #expect(away == nil)
}

@Test func closelySpacedCornersRemainSeparateAndDontShareACooldown() throws {
    let plan = TurnRoutePlan(path: [Position(x: 0, z: 0), Position(x: 0, z: -10),
                                    Position(x: 2, z: -10), Position(x: 2, z: -20)])
    #expect(plan.turns.count == 2)
    let first = try #require(plan.turns.first)
    let second = try #require(plan.turns.last)
    #expect(first.direction == .right)
    #expect(second.direction == .left)
    var voice = TurnAnnouncements()
    let firstCue = voice.update(turn: first, progress: 10, position: first.position)
    let secondCue = voice.update(turn: second, progress: 12, position: second.position)
    #expect(firstCue?.phase == .turnNow)
    #expect(secondCue?.phase == .turnNow)
}

@Test func routeProgressDoesNotJumpToNearbyLaterSections() throws {
    let plan = TurnRoutePlan(path: [Position(x: 0, z: 0), Position(x: 0, z: -10),
                                    Position(x: 1, z: -10), Position(x: 1, z: 0)])
    let projection = try #require(plan.project(Position(x: 0.7, z: -1), near: 0))
    #expect(projection.progress <= 3)
    #expect(abs(projection.progress - 1) < 0.01)
    #expect(abs(projection.distance - 0.7) < 0.01)
    let empty = TurnRoutePlan(path: [])
    #expect(empty.turns.isEmpty)
    #expect(empty.position(at: 1) == nil)
    let stationary = TurnRoutePlan(path: [Position(x: 0, z: 0), Position(x: 0, z: 0)])
    #expect(stationary.turns.isEmpty)
    #expect(stationary.project(Position(x: 0, z: 0), near: 0) == nil)
}

@Test func screenShowsUpcomingTurnWithinFiveMeters() throws {
    let turn = try #require(TurnRoutePlan(path: cornerPath).turns.first)
    let far = TurnPresentation(turn: turn, progress: 4, position: Position(x: 0, z: -4))
    #expect(far.symbol == "arrow.up")
    #expect(far.detail == "Turn right in about 6 m")
    let approaching = TurnPresentation(turn: turn, progress: 5, position: Position(x: 0, z: -5))
    #expect(approaching.symbol == "arrow.turn.up.right")
    #expect(approaching.instruction == "Turn right in about 5 m")
    let now = TurnPresentation(turn: turn, progress: 10, position: turn.position)
    #expect(now.instruction == "Turn right now")
    let exiting = TurnPresentation(turn: turn, progress: 10.8, position: Position(x: 0.8, z: -10))
    #expect(exiting.instruction == "Follow the hallway around the corner")
}

@Test func continueStraightIsSpokenOnceAfterTurning() {
    let plan = TurnRoutePlan(path: cornerPath)
    var voice = TurnAnnouncements()
    let turn = voice.announcement(plan: plan, progress: 10, position: Position(x: 0, z: -10))
    #expect(turn == "Turn right now.")
    let straight = voice.announcement(plan: plan, progress: 11, position: Position(x: 1, z: -10))
    #expect(straight == "Continue straight.")
    for progress in [11.1, 12, 15] {
        let repeated = voice.announcement(plan: plan, progress: progress, position: Position(x: Float(progress - 10), z: -10))
        #expect(repeated == nil)
    }
}

@Test func closeTurnsCombineWarningAndPrioritizeImmediateDirection() {
    let plan = TurnRoutePlan(path: [Position(x: 0, z: 0), Position(x: 0, z: -10),
                                    Position(x: 2, z: -10), Position(x: 2, z: -20)])
    var voice = TurnAnnouncements()
    let combined = voice.announcement(plan: plan, progress: 10.95, position: Position(x: 0.95, z: -10))
    #expect(combined == "Continue straight. In about 1 meters, turn left.")
    let next = TurnPresentation(turn: plan.turns[1], progress: 11, position: Position(x: 1, z: -10))
    #expect(next.symbol == "arrow.turn.up.left")
    var skippedFrame = TurnAnnouncements()
    let urgent = skippedFrame.announcement(plan: plan, progress: 12, position: Position(x: 2, z: -10))
    #expect(urgent == "Turn left now.")
    let repeated = skippedFrame.announcement(plan: plan, progress: 12, position: Position(x: 2, z: -10))
    #expect(repeated == nil)
}

@Test func turnInstructionStartsOneMeterBeforeCorner() throws {
    let turn = try #require(TurnRoutePlan(path: cornerPath).turns.first)
    var voice = TurnAnnouncements()
    let cue = voice.update(turn: turn, progress: 9, position: Position(x: 0, z: -9))
    #expect(cue?.phase == .turnNow)
    let screen = TurnPresentation(turn: turn, progress: 9, position: Position(x: 0, z: -9))
    #expect(screen.instruction == "Turn right now")
    let duplicate = voice.update(turn: turn, progress: 9.5, position: Position(x: 0, z: -9.5))
    #expect(duplicate == nil)
}

@Test func destinationWarningUsesFinalLegAndOnlySpeaksOnce() {
    var voice = DestinationAnnouncements()
    let transfer = voice.update(remaining: 3, isFinalLeg: false)
    #expect(transfer == nil)
    let distant = voice.update(remaining: 3.1, isFinalLeg: true)
    #expect(distant == nil)
    let warning = voice.update(remaining: 3, isFinalLeg: true)
    #expect(warning == "Your destination is in about 3 meters. Check the room sign as you approach.")
    for remaining in [3.1, 3, 2, 1, 0] {
        let repeated = voice.update(remaining: remaining, isFinalLeg: true)
        #expect(repeated == nil)
    }
    var atDestination = DestinationAnnouncements()
    let late = atDestination.update(remaining: 0.5, isFinalLeg: true)
    #expect(late == nil)
}

@Test func initialGuidanceSpeaksStraightAndKeepsUrgentTurnPriority() {
    let plan = TurnRoutePlan(path: cornerPath)
    var voice = TurnAnnouncements()
    let start = voice.announcement(plan: plan, progress: 0, position: Position(x: 0, z: 0), starting: true)
    #expect(start == "Continue straight.")
    let repeatFrame = voice.announcement(plan: plan, progress: 0, position: Position(x: 0, z: 0))
    #expect(repeatFrame == nil)
    var nearTurn = TurnAnnouncements()
    let warning = nearTurn.announcement(plan: plan, progress: 5, position: Position(x: 0, z: -5), starting: true)
    #expect(warning == "Continue straight. In about 5 meters, turn right.")
    var atTurn = TurnAnnouncements()
    let urgent = atTurn.announcement(plan: plan, progress: 9, position: Position(x: 0, z: -9), starting: true)
    #expect(urgent == "Turn right now.")
}
