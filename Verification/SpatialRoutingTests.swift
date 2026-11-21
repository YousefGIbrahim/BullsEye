import Foundation
import Testing
@testable import BullseyeCore

private func scannedMap() -> BuildingMap {
    let zone = CaptureZone(floor: "1", name: "Hallway")
    let a = Waypoint(name: "Room A", floor: "1", zoneID: zone.id, position: Position(x: 0, z: 0))
    let b = Waypoint(name: "Room B", floor: "1", zoneID: zone.id, position: Position(x: 5, z: -5))
    let path = [Position(x: 0, z: 0), Position(x: 0, z: -5), Position(x: 5, z: -5)]
    return BuildingMap(building: "Building", code: "B", zones: [zone], points: [a, b],
        rooms: [Room(number: "A", label: "", waypointID: a.id), Room(number: "B", label: "", waypointID: b.id)],
        links: [RouteLink(from: a.id, to: b.id, instruction: "To B", stepFree: true, verifiedAt: Date(), cost: 10, path: path),
                RouteLink(from: b.id, to: a.id, instruction: "To A", stepFree: true, verifiedAt: Date(), cost: 10, path: Array(path.reversed()))])
}

@Test func cameraPositionJoinsTheMiddleOfAWalkedPath() throws {
    let map = scannedMap()
    let route = try #require(map.locatedRoute(at: Position(x: 0, z: -2), zoneID: map.zones[0].id,
                                             to: map.points[1].id, stepFree: true))
    #expect(abs(route.cost - 8) < 0.001)
    #expect(route.links.count == 1)
    #expect(route.links[0].path == [Position(x: 0, z: -2), Position(x: 0, z: -5), Position(x: 5, z: -5)])
    // A diagonal shortcut through the inside of the bend must not be inferred.
    #expect(map.locatedRoute(at: Position(x: 2.5, z: -2.5), zoneID: map.zones[0].id,
                            to: map.points[1].id, stepFree: false) == nil)
}

@Test func roomsAreStartsAndReturnRoutesUseReversedGeometry() throws {
    let map = scannedMap()
    #expect(map.startingPoints.count == 2)
    let route = try #require(map.locatedRoute(at: Position(x: 3, z: -5), zoneID: map.zones[0].id,
                                             to: map.points[0].id, stepFree: false))
    #expect(route.links.first?.to == map.points[0].id)
    #expect(abs(route.cost - 8) < 0.001)
    #expect(route.links.first?.path?.last == Position(x: 0, z: 0))
}

@Test func automaticRoutingRespectsAccessAndCoordinateSpaces() {
    var map = scannedMap()
    let position = Position(x: 0, z: -2)
    let destination = map.points[1].id
    #expect(map.locatedRoute(at: position, zoneID: UUID(), to: destination, stepFree: false) == nil)
    map.links[0].closed = true
    #expect(map.locatedRoute(at: position, zoneID: map.zones[0].id, to: destination, stepFree: false) == nil)
    map.links[0].closed = false
    map.links[0].stepFree = false
    #expect(map.locatedRoute(at: position, zoneID: map.zones[0].id, to: destination, stepFree: true) == nil)
    #expect(map.locatedRoute(at: position, zoneID: map.zones[0].id, to: destination, stepFree: false) != nil)
    map.links[0].verifiedAt = nil
    #expect(map.locatedRoute(at: position, zoneID: map.zones[0].id, to: destination, stepFree: false) == nil)
}

@Test func liveTurnsFollowCameraHeading() {
    let origin = Position(x: 0, z: 0)
    let north = Position(x: 0, z: -1)
    #expect(WalkedPath.turn(from: origin, forward: north, toward: Position(x: 3, z: 0)).text == "Turn right")
    #expect(WalkedPath.turn(from: origin, forward: north, toward: Position(x: -3, z: 0)).text == "Turn left")
    #expect(WalkedPath.turn(from: origin, forward: north, toward: Position(x: 0, z: 3)).text == "Turn around")
    #expect(WalkedPath.turn(from: origin, forward: north, toward: Position(x: 0, z: -3)).text == "Continue straight")
    #expect(WalkedPath.turn(from: origin, forward: Position(x: 1, z: 0), toward: north).text == "Turn left")
}

@Test func pathProjectionAndLookAheadPreserveCorners() throws {
    let path = [Position(x: 0, z: 0), Position(x: 0, z: -5), Position(x: 5, z: -5)]
    let projected = try #require(WalkedPath.project(Position(x: 0.2, z: -4), onto: path))
    #expect(abs(projected.distance - 0.2) < 0.001)
    #expect(projected.segment == 0)
    #expect(WalkedPath.lookAhead(on: projected.remaining, meters: 1) == Position(x: 0, z: -5))
    #expect(WalkedPath.lookAhead(on: projected.remaining, meters: 3) == Position(x: 0, z: -5))
    #expect(WalkedPath.project(Position(x: 0, z: 0), onto: []) == nil)
}

@Test func olderMapsStillDecodeAndRecordedPathsRoundTrip() throws {
    let old = Practice.map
    let oldData = try JSONEncoder().encode(old)
    #expect(try JSONDecoder().decode(BuildingMap.self, from: oldData) == old)
    let map = scannedMap()
    #expect(try JSONDecoder().decode(BuildingMap.self, from: JSONEncoder().encode(map)) == map)
}
