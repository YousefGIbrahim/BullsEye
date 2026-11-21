import Foundation
import SwiftUI
import Observation
import UniformTypeIdentifiers
#if os(iOS)
import ARKit
#endif

struct Position: Codable, Hashable {
    var x: Float
    var z: Float
    func distance(to other: Position) -> Double {
        Double(hypot(x - other.x, z - other.z))
    }
}

struct Waypoint: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var floor: String
    var zoneID: UUID
    var kind: String = "Hallway"
    var facing: String = ""
    var position: Position?
    var isStart = false
}

struct Room: Codable, Identifiable, Hashable {
    var id = UUID()
    var number: String
    var label: String
    var aliases: String = ""
    var waypointID: UUID
}

enum LinkKind: String, Codable, CaseIterable, Identifiable {
    case corridor = "Corridor", door = "Door", ramp = "Ramp", stairs = "Stairs", elevator = "Elevator"
    var id: String { rawValue }
}

struct RouteLink: Codable, Identifiable, Hashable {
    var id = UUID()
    var from: UUID
    var to: UUID
    var kind: LinkKind = .corridor
    var instruction: String
    var stepFree = false
    var verifiedAt: Date?
    var closed = false
    var cost: Double = 1
    var direction: String?
    // Ordered camera positions along the walked connection, in the owning zone.
    // Optional so maps created before path recording still decode.
    var path: [Position]?
}

struct CaptureZone: Codable, Identifiable, Hashable {
    var id = UUID()
    var floor: String
    var name: String
    // Each zone owns its coordinate system. Never compare coordinates between zones.
    var worldMap: Data?
}

struct BuildingMap: Codable, Identifiable, Hashable {
    var id = UUID()
    var building: String
    var code: String
    var published = false
    var updatedAt = Date()
    var zones: [CaptureZone] = []
    var points: [Waypoint] = []
    var rooms: [Room] = []
    var links: [RouteLink] = []
    func point(_ id: UUID) -> Waypoint? { points.first { $0.id == id } }
    func route(from start: UUID, to end: UUID, stepFree: Bool) -> [RouteLink]? {
        guard point(start) != nil, point(end) != nil else { return nil }
        if start == end { return [] }
        var distances: [UUID: Double] = [start: 0]
        var previous: [UUID: RouteLink] = [:]
        var remaining = Set(points.map(\.id))
        while let current = remaining.min(by: { distances[$0, default: .infinity] < distances[$1, default: .infinity] }) {
            guard let distance = distances[current] else { break }
            remaining.remove(current)
            if current == end { break }
            for link in links where link.from == current && !link.closed && link.verifiedAt != nil {
                if stepFree && (!link.stepFree || link.kind == .stairs) { continue }
                guard remaining.contains(link.to) else { continue }
                let next = distance + max(0.1, link.cost)
                if next < distances[link.to, default: .infinity] {
                    distances[link.to] = next
                    previous[link.to] = link
                }
            }
        }
        guard distances[end] != nil else { return nil }
        var result: [RouteLink] = []
        var cursor = end
        while cursor != start {
            guard let link = previous[cursor] else { return nil }
            result.insert(link, at: 0)
            cursor = link.from
        }
        return result
    }
    func validate() throws {
        guard !building.trimmed.isEmpty, !code.trimmed.isEmpty else { throw DataIssue.message("Add a building name and code.") }
        guard Set(points.map(\.id)).count == points.count,
              Set(rooms.map(\.id)).count == rooms.count,
              Set(links.map(\.id)).count == links.count,
              Set(zones.map(\.id)).count == zones.count else { throw DataIssue.message("Duplicate identifiers in this map.") }
        #if os(iOS)
        for zone in zones {
            if let data = zone.worldMap {
                guard (try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)) != nil else {
                    throw DataIssue.message("A zone contains an unreadable ARWorldMap. Nothing was imported.")
                }
            }
        }
        #endif
        for point in points {
            if point.position != nil && zones.first(where: { $0.id == point.zoneID })?.worldMap == nil {
                throw DataIssue.message("AR waypoints require their saved world map. Finish saving the capture first.")
            }
            guard zones.contains(where: { $0.id == point.zoneID && $0.floor == point.floor }),
                  !point.name.trimmed.isEmpty,
                  point.position.map({ $0.x.isFinite && $0.z.isFinite }) ?? true else {
                throw DataIssue.message("A waypoint has an invalid floor, zone or position.")
            }
        }
        for room in rooms {
            guard point(room.waypointID) != nil, !room.number.trimmed.isEmpty else { throw DataIssue.message("A room needs a valid stopping point and number.") }
        }
        for link in links {
            guard let a = point(link.from), let b = point(link.to), a.id != b.id,
                  !link.instruction.trimmed.isEmpty, link.cost.isFinite, link.cost > 0 else { throw DataIssue.message("A connection has invalid endpoints or instructions.") }
            if a.zoneID != b.zoneID && link.kind != .elevator && link.kind != .stairs {
                throw DataIssue.message("Separate captures must connect explicitly with an elevator or stairs.")
            }
            if let path = link.path {
                guard a.zoneID == b.zoneID, path.count >= 2,
                      path.allSatisfy({ $0.x.isFinite && $0.z.isFinite }),
                      let first = path.first, let last = path.last,
                      let start = a.position, let end = b.position,
                      first.distance(to: start) < 0.1, last.distance(to: end) < 0.1 else {
                    throw DataIssue.message("A recorded path must join its waypoints in the same capture.")
                }
            }
            if link.kind == .stairs && link.stepFree { throw DataIssue.message("Stairs cannot be step-free.") }
        }
    }
}

enum DataIssue: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct Suggestion: Codable, Identifiable {
    var id = UUID()
    var building: String
    var floor: String
    var number: String
    var label: String
    var note: String
    var status = "Pending"
}

struct CampusArchive: Codable {
    var version = 1
    var maps: [BuildingMap] = []
    var suggestions: [Suggestion] = []
}

struct MapDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw DataIssue.message("Unreadable package.") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor @Observable final class CampusStore {
    var archive = CampusArchive()
    var message: String?
    var loadFailed = false
    private let url: URL?
    init(inMemory: Bool = false, storageURL: URL? = nil) {
        url = inMemory ? nil : (storageURL ?? URL.documentsDirectory.appending(path: "bullseye-v1.json"))
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            archive = try JSONDecoder().decode(CampusArchive.self, from: Data(contentsOf: url))
            try Self.validate(archive)
        } catch {
            loadFailed = true
            message = "Saved data could not be read. It has not been overwritten. Export or recover the original file before making changes. \(error.localizedDescription)"
        }
    }
    var published: [BuildingMap] { archive.maps.filter(\.published) }
    func commit(_ next: CampusArchive) throws {
        guard !loadFailed else { throw DataIssue.message("Saved data needs recovery before changes can be saved.") }
        try Self.validate(next)
        if let url { try JSONEncoder().encode(next).write(to: url, options: .atomic) }
        archive = next
    }
    func save(_ map: BuildingMap) throws {
        var next = archive
        var updated = map
        updated.updatedAt = Date()
        if let index = next.maps.firstIndex(where: { $0.id == map.id }) { next.maps[index] = updated }
        else { next.maps.append(updated) }
        try commit(next)
    }
    func setPublished(_ published: Bool, id: UUID) throws {
        guard var map = archive.maps.first(where: { $0.id == id }) else {
            throw DataIssue.message("This map no longer exists.")
        }
        if published && map.rooms.isEmpty {
            throw DataIssue.message("Mark at least one room before publication.")
        }
        map.published = published
        try save(map)
    }
    func deleteDraft(id: UUID) throws {
        guard let map = archive.maps.first(where: { $0.id == id }) else {
            throw DataIssue.message("This map no longer exists.")
        }
        guard !map.published else {
            throw DataIssue.message("Unpublish this map before deleting it.")
        }
        var next = archive
        next.maps.removeAll { $0.id == id }
        try commit(next)
    }
    func addSuggestion(_ suggestion: Suggestion) throws {
        var next = archive
        next.suggestions.append(suggestion)
        try commit(next)
    }
    func exportData() throws -> Data { try JSONEncoder().encode(archive) }
    func importData(_ data: Data) throws {
        guard data.count <= 100_000_000 else { throw DataIssue.message("Package exceeds 100 MB. Export fewer captures.") }
        let incoming = try JSONDecoder().decode(CampusArchive.self, from: data)
        try Self.validate(incoming)
        guard !incoming.maps.contains(where: { map in archive.maps.contains { $0.id == map.id } }),
              !incoming.suggestions.contains(where: { suggestion in archive.suggestions.contains { $0.id == suggestion.id } }) else {
            throw DataIssue.message("This package contains an existing map or suggestion. Nothing was replaced. Import into a fresh installation or keep the existing version.")
        }
        var next = archive
        next.maps += incoming.maps
        next.suggestions += incoming.suggestions
        try commit(next)
    }
    static func validate(_ archive: CampusArchive) throws {
        guard archive.version == 1 else { throw DataIssue.message("Unsupported package version. Update Bullseye before importing.") }
        guard Set(archive.maps.map(\.id)).count == archive.maps.count,
              Set(archive.suggestions.map(\.id)).count == archive.suggestions.count else { throw DataIssue.message("Duplicate package identifiers.") }
        for map in archive.maps { try map.validate() }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var searchKey: String {
        let cleaned = lowercased().replacingOccurrences(of: "engineering two", with: "enb")
            .replacingOccurrences(of: "engineering ii", with: "enb")
            .replacingOccurrences(of: "engineering 2", with: "enb")
            .replacingOccurrences(of: "s v c", with: "svc")
            .replacingOccurrences(of: "e n b", with: "enb")
            .replacingOccurrences(of: "e and b", with: "enb")
            .replacingOccurrences(of: "take me to", with: "")
            .replacingOccurrences(of: "where is", with: "")
        let digits = ["zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3",
                      "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
                      "twenty": "20", "sixty": "60"]
        return cleaned.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0 != "room" && $0 != "number" }
            .map { digits[String($0)] ?? String($0) }.joined()
    }
}

struct CampusService: Identifiable, Hashable {
    let id: String
    let name: String
    let room: String
    let floor: String
    let summary: String
    let source: String
    let sourceName: String
    let aliases: [String]
    let icon: String
    static let catalog = [
        CampusService(id: "suit-a-bull", name: "Suit-A-Bull", room: "SVC 2060", floor: "2",
          summary: "Suit-A-Bull offers free professional clothing you can keep. It’s in the Student Services Building, room SVC 2060. Would you like directions to the building?",
          source: "https://careers.usf.edu/resources/suit-a-bull/", sourceName: "USF Career Services",
          aliases: ["suit", "professional clothing", "interview clothes", "rent a suit", "suitabull"], icon: "tshirt"),
        CampusService(id: "feed-a-bull", name: "Feed-A-Bull", room: "SVC 0002", floor: "Ground",
          summary: "Feed-A-Bull provides food assistance to USF students. The Tampa pantry is on the ground floor of the Student Services Building, SVC 0002.",
          source: "https://www.usf.edu/student-affairs/student-health-services/services/feed-a-bull-food-pantry.aspx",
          sourceName: "USF Student Health Services", aliases: ["food pantry", "groceries", "food assistance", "feedabull", "hungry"], icon: "basket")
    ]
    static func matching(_ query: String) -> [CampusService] {
        let key = query.searchKey
        guard !key.isEmpty else { return [] }
        return catalog.filter { service in
            service.room.searchKey == key || service.name.searchKey.contains(key) ||
            service.aliases.contains { key.contains($0.searchKey) }
        }
    }
}

// Only previews and the explicitly labeled practice flow use this fixture.
enum Practice {
    static var map: BuildingMap {
        let zone = CaptureZone(floor: "1", name: "Practice hallway")
        let start = Waypoint(name: "Entrance landmark", floor: "1", zoneID: zone.id, facing: "Face the hallway", isStart: true)
        let turn = Waypoint(name: "Hallway junction", floor: "1", zoneID: zone.id)
        let door = Waypoint(name: "Practice doorway", floor: "1", zoneID: zone.id)
        return BuildingMap(building: "Practice building · not ENB", code: "DEMO", zones: [zone], points: [start, turn, door],
          rooms: [Room(number: "101", label: "Practice room", waypointID: door.id)],
          links: [RouteLink(from: start.id, to: turn.id, instruction: "Continue along the hallway to the junction.", stepFree: true, verifiedAt: Date()),
                  RouteLink(from: turn.id, to: door.id, kind: .door, instruction: "Turn right. Stop beside the practice room sign.", stepFree: true, verifiedAt: Date(), direction: "arrow.turn.up.right")])
    }
}


// Geometry is kept independent of ARKit so route selection can be verified without a camera.
struct PathProjection {
    var position: Position
    var distance: Double
    var segment: Int
    var remaining: [Position]
}

enum WalkedPath {
    static func length(_ points: [Position]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    static func project(_ position: Position, onto path: [Position]) -> PathProjection? {
        guard path.count >= 2 else { return nil }
        var best: PathProjection?
        for i in 0..<(path.count - 1) {
            let a = path[i], b = path[i + 1]
            let dx = b.x - a.x, dz = b.z - a.z
            let squared = dx * dx + dz * dz
            let t = squared > 0 ? max(0, min(1, ((position.x - a.x) * dx + (position.z - a.z) * dz) / squared)) : 0
            let nearest = Position(x: a.x + t * dx, z: a.z + t * dz)
            let distance = position.distance(to: nearest)
            if best == nil || distance < (best?.distance ?? .infinity) {
                best = PathProjection(position: nearest, distance: distance, segment: i,
                                      remaining: [nearest] + Array(path.dropFirst(i + 1)))
            }
        }
        return best
    }

    static func lookAhead(on path: [Position], meters: Double = 1.2) -> Position? {
        guard var a = path.first else { return nil }
        var remaining = meters
        for (index, b) in path.enumerated().dropFirst() {
            let distance = a.distance(to: b)
            if distance > remaining {
                let fraction = Float(remaining / distance)
                return Position(x: a.x + (b.x - a.x) * fraction, z: a.z + (b.z - a.z) * fraction)
            }
            remaining -= distance
            if index + 1 < path.count, distance > 0.05 {
                let c = path[index + 1]
                let ux = b.x - a.x, uz = b.z - a.z
                let vx = c.x - b.x, vz = c.z - b.z
                let nextDistance = b.distance(to: c)
                if nextDistance > 0.05 {
                    let cosine = Double(ux * vx + uz * vz) / (distance * nextDistance)
                    // Aim at a sharp corner before looking past it into the next hall.
                    if cosine < 0.8 { return b }
                }
            }
            a = b
        }
        return path.last
    }

    // Camera forward is -Z. Positive signed angles mean a right turn.
    static func turn(from position: Position, forward: Position, toward target: Position) -> (text: String, symbol: String) {
        let dx = target.x - position.x, dz = target.z - position.z
        let angle = atan2(Double(forward.x * dz - forward.z * dx), Double(forward.x * dx + forward.z * dz))
        if abs(angle) > 2.4 { return ("Turn around", "arrow.uturn.down") }
        if angle > 0.5 { return ("Turn right", "arrow.turn.up.right") }
        if angle < -0.5 { return ("Turn left", "arrow.turn.up.left") }
        return ("Continue straight", "arrow.up")
    }
}

struct LocatedRoute {
    var links: [RouteLink]
    var approach: [Position]
    var joinID: UUID
    var distanceFromPath: Double
    var cost: Double
}

extension BuildingMap {
    var startingPoints: [Waypoint] {
        points.filter { point in point.isStart || rooms.contains { $0.waypointID == point.id } }
    }

    func geometry(for link: RouteLink) -> [Position]? {
        guard let a = point(link.from), let b = point(link.to), a.zoneID == b.zoneID,
              let start = a.position, let end = b.position else { return nil }
        // Legacy connections were explicitly authored as straight waypoint segments.
        return link.path ?? [start, end]
    }

    func locatedRoute(at position: Position, zoneID: UUID, to destination: UUID, stepFree: Bool) -> LocatedRoute? {
        var candidates: [LocatedRoute] = []
        for point in points where point.zoneID == zoneID {
            guard let p = point.position, position.distance(to: p) <= 0.85,
                  let route = route(from: point.id, to: destination, stepFree: stepFree) else { continue }
            candidates.append(LocatedRoute(links: route, approach: [p], joinID: point.id,
                distanceFromPath: position.distance(to: p), cost: route.reduce(0) { $0 + $1.cost }))
        }
        for link in links where !link.closed && link.verifiedAt != nil {
            guard point(link.from)?.zoneID == zoneID,
                  !stepFree || (link.stepFree && link.kind != .stairs),
                  let path = geometry(for: link),
                  let projection = WalkedPath.project(position, onto: path), projection.distance <= 0.85,
                  let tail = route(from: link.to, to: destination, stepFree: stepFree) else { continue }
            var partial = link
            partial.path = projection.remaining
            partial.cost = max(0.1, WalkedPath.length(projection.remaining))
            candidates.append(LocatedRoute(links: [partial] + tail, approach: [projection.position], joinID: link.from,
                distanceFromPath: projection.distance, cost: partial.cost + tail.reduce(0) { $0 + $1.cost }))
        }
        // Prefer the closest observed corridor, then the shortest permitted direction.
        // A distant parallel corridor must not win just because it has a shorter route.
        guard let nearest = candidates.map(\.distanceFromPath).min() else { return nil }
        return candidates.filter { $0.distanceFromPath <= nearest + 0.15 }
            .min { $0.cost + $0.distanceFromPath < $1.cost + $1.distanceFromPath }
    }
}


extension BuildingMap {
    // Intermediate rooms remain geometry along the route, not required stops.
    // Floor transfers stay separate because they need explicit confirmation.
    func continuousWalkingRoute(_ links: [RouteLink]) -> [RouteLink] {
        var result: [RouteLink] = []
        for link in links {
            guard link.kind != .stairs, link.kind != .elevator,
                  let linkPath = geometry(for: link) else {
                result.append(link)
                continue
            }
            if var previous = result.last,
               previous.kind != .stairs, previous.kind != .elevator,
               previous.to == link.from,
               point(previous.from)?.zoneID == point(link.to)?.zoneID,
               let previousPath = geometry(for: previous) {
                previous.to = link.to
                previous.path = previousPath + linkPath.dropFirst()
                previous.cost += link.cost
                previous.stepFree = previous.stepFree && link.stepFree
                previous.instruction = "Follow the recorded walkway to \(point(link.to)?.name ?? "your destination")."
                result[result.count - 1] = previous
            } else {
                result.append(link)
            }
        }
        return result
    }
}

