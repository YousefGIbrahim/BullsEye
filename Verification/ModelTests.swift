import Foundation
import Testing
@testable import BullseyeCore

@Test @MainActor func diskRelaunchPreservesPublicationAndProtectsCorruption() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "bullseye-test-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = CampusStore(storageURL: url)
    var map = Practice.map
    map.published = true
    try store.save(map)
    let reopened = CampusStore(storageURL: url)
    #expect(reopened.published.first?.id == map.id)
    #expect(reopened.published.first?.rooms.first?.id == map.rooms.first?.id)
    let corrupt = Data("invalid package".utf8)
    try corrupt.write(to: url)
    let protected = CampusStore(storageURL: url)
    #expect(protected.loadFailed)
    #expect(throws: (any Error).self) { try protected.save(map) }
    #expect(try Data(contentsOf: url) == corrupt)
}

@Test func graphExcludesUnsafeLinksAndRespectsDirection() throws {
    var map = Practice.map
    let start = map.points[0].id
    let end = map.rooms[0].waypointID
    #expect(map.route(from: start, to: end, stepFree: true)?.count == 2)
    #expect(map.route(from: end, to: start, stepFree: false) == nil)
    map.links[0].closed = true
    #expect(map.route(from: start, to: end, stepFree: false) == nil)
    map.links[0].closed = false
    map.links[0].verifiedAt = nil
    #expect(map.route(from: start, to: end, stepFree: true) == nil)
    map.links[0].verifiedAt = Date()
    map.links[0].stepFree = false
    #expect(map.route(from: start, to: end, stepFree: true) == nil)
    map.links[0].kind = .stairs
    #expect(map.route(from: start, to: end, stepFree: true) == nil)
    #expect(map.route(from: start, to: end, stepFree: false)?.count == 2)
}

@Test func shortestPathAndFloorTransfers() throws {
    var map = Practice.map
    let start = map.points[0].id
    let end = map.rooms[0].waypointID
    let direct = RouteLink(from: start, to: end, instruction: "Observed direct route", stepFree: true, verifiedAt: Date(), cost: 10)
    map.links.append(direct)
    #expect(map.route(from: start, to: end, stepFree: true)?.count == 2)
    map.links[0].closed = true
    #expect(map.route(from: start, to: end, stepFree: true)?.first?.id == direct.id)
    let upstairs = CaptureZone(floor: "2", name: "Separate capture")
    map.zones.append(upstairs)
    map.points[2].zoneID = upstairs.id
    map.points[2].floor = "2"
    #expect(throws: (any Error).self) { try map.validate() }
    map.links.removeLast()
    map.links[1].kind = .elevator
    try map.validate()
}

@Test @MainActor func packageRoundTripAndAtomicConflictRejection() throws {
    let store = CampusStore(inMemory: true)
    var map = Practice.map
    map.published = true
    try store.save(map)
    let data = try store.exportData()
    let imported = CampusStore(inMemory: true)
    try imported.importData(data)
    #expect(imported.published.first?.id == map.id)
    #expect(imported.published.first?.rooms.first?.id == map.rooms.first?.id)
    #expect(throws: (any Error).self) { try imported.importData(data) }
    #expect(imported.archive.maps.count == 1)
    var incoming = CampusArchive(maps: [Practice.map, map])
    #expect(throws: (any Error).self) { try imported.importData(JSONEncoder().encode(incoming)) }
    #expect(imported.archive.maps.count == 1)
    incoming.version = 99
    #expect(throws: (any Error).self) { try imported.importData(JSONEncoder().encode(incoming)) }
    #expect(imported.archive.maps.count == 1)
}

@Test func invalidReferencesAndMissingWorldMapsAreRejected() throws {
    var map = Practice.map
    map.rooms[0].waypointID = UUID()
    #expect(throws: (any Error).self) { try map.validate() }
    map = Practice.map
    map.points[0].position = Position(x: 1, z: 1)
    #expect(throws: (any Error).self) { try map.validate() }
    map = Practice.map
    map.links[0].cost = .nan
    #expect(throws: (any Error).self) { try map.validate() }
}

@Test func serviceMatchingDoesNotInventRooms() {
    #expect(CampusService.matching("SVC2060").first?.id == "suit-a-bull")
    #expect(CampusService.matching("Where can I rent a suit?").first?.id == "suit-a-bull")
    #expect(CampusService.matching("groceries").first?.id == "feed-a-bull")
    #expect(CampusService.matching("ENB 999").isEmpty)
    #expect(" E N B  123 ".searchKey == "enb123")
    #expect("Engineering two".searchKey == "enb")
    #expect("Where is room S V C two zero six zero".searchKey == "svc2060")
    #expect(CampusService.matching("S V C two zero six zero").first?.id == "suit-a-bull")
}
