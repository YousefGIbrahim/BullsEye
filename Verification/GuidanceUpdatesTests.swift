import Foundation
import Testing
@testable import BullseyeCore

@Test @MainActor func deletingDraftPersistsAndProtectsPublishedMaps() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "draft-delete-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = CampusStore(storageURL: url)
    let draft = Practice.map
    var published = Practice.map
    published.published = true
    try store.save(draft)
    try store.save(published)
    #expect(throws: (any Error).self) { try store.deleteDraft(id: published.id) }
    #expect(store.archive.maps.count == 2)
    try store.deleteDraft(id: draft.id)
    #expect(store.archive.maps.map(\.id) == [published.id])
    let reopened = CampusStore(storageURL: url)
    #expect(reopened.archive.maps.map(\.id) == [published.id])
    #expect(throws: (any Error).self) { try store.deleteDraft(id: UUID()) }
    #expect(reopened.archive.maps[0].rooms == published.rooms)
}

@Test func walkingThroughIntermediateRoomsPreservesTurns() throws {
    var map = Practice.map
    map.points[0].position = Position(x: 0, z: 0)
    map.points[1].position = Position(x: 0, z: -5)
    map.points[2].position = Position(x: 5, z: -5)
    map.links[0].path = [Position(x: 0, z: 0), Position(x: 0, z: -2), Position(x: 0, z: -5)]
    map.links[0].cost = 5
    map.links[1].cost = 5
    let legs = map.continuousWalkingRoute(map.links)
    #expect(legs.count == 1)
    let leg = try #require(legs.first)
    #expect(leg.from == map.points[0].id)
    #expect(leg.to == map.points[2].id)
    #expect(leg.cost == 10)
    #expect(leg.path == [Position(x: 0, z: 0), Position(x: 0, z: -2), Position(x: 0, z: -5), Position(x: 5, z: -5)])
    // Starting partway along the first leg must not send the person back to its origin.
    map.links[0].path = [Position(x: 0, z: -2), Position(x: 0, z: -5)]
    #expect(map.continuousWalkingRoute(map.links).first?.path?.first == Position(x: 0, z: -2))
}

@Test func floorTransfersRemainSeparateFromWalking() {
    var map = Practice.map
    for index in map.points.indices { map.points[index].position = Position(x: Float(index), z: 0) }
    map.links[1].kind = .elevator
    #expect(map.continuousWalkingRoute(map.links).count == 2)
    map.links[1].kind = .stairs
    #expect(map.continuousWalkingRoute(map.links).count == 2)
}

@Test @MainActor func publicationMenuActionsPersistAndValidate() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "publish-menu-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = CampusStore(storageURL: url)
    let map = Practice.map
    try store.save(map)
    try store.setPublished(true, id: map.id)
    #expect(CampusStore(storageURL: url).published.first?.id == map.id)
    try store.setPublished(false, id: map.id)
    #expect(CampusStore(storageURL: url).published.isEmpty)
    try store.deleteDraft(id: map.id)
    #expect(CampusStore(storageURL: url).archive.maps.isEmpty)
    let empty = BuildingMap(building: "Empty", code: "EMPTY")
    try store.save(empty)
    #expect(throws: (any Error).self) { try store.setPublished(true, id: empty.id) }
    #expect(store.published.isEmpty)
}

