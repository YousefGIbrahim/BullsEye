import Foundation

enum RouteTurnDirection: String, Equatable {
    case left, right, around

    var instruction: String {
        switch self {
        case .left: return "Turn left"
        case .right: return "Turn right"
        case .around: return "Turn around"
        }
    }

    var symbol: String {
        switch self {
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        case .around: return "arrow.uturn.down"
        }
    }
}

struct RouteTurn: Identifiable, Equatable {
    let id: Int
    let position: Position
    let distance: Double
    let direction: RouteTurnDirection
}

struct TurnRoutePlan {
    let path: [Position]
    let distances: [Double]
    let turns: [RouteTurn]
    var length: Double { distances.last ?? 0 }

    init(path: [Position]) {
        // Remove stationary duplicate samples. Keep the original walkway for
        // localization; simplification is used only to identify turn events.
        var clean: [Position] = []
        for point in path {
            if let last = clean.last, last.distance(to: point) < 0.02 { continue }
            clean.append(point)
        }
        self.path = clean
        var distances: [Double] = clean.isEmpty ? [] : [0]
        for pair in zip(clean, clean.dropFirst()) {
            distances.append((distances.last ?? 0) + pair.0.distance(to: pair.1))
        }
        self.distances = distances
        self.turns = Self.findTurns(path: clean, distances: distances)
    }

    func position(at distance: Double) -> Position? {
        Self.position(at: distance, path: path, distances: distances)
    }

    func nextTurn(after progress: Double) -> RouteTurn? {
        // Retain the turn through its corner, then retire it once on the exit.
        turns.first { progress <= $0.distance + 0.9 }
    }

    func project(_ position: Position, near progress: Double) -> (distance: Double, progress: Double)? {
        guard path.count >= 2 else { return nil }
        let lower = max(0, progress - 0.6)
        let upper = min(length, progress + 3)
        guard let first = self.position(at: lower), let last = self.position(at: upper) else { return nil }
        var window = [first]
        for (index, point) in path.enumerated() where distances[index] > lower && distances[index] < upper {
            window.append(point)
        }
        window.append(last)
        guard let projection = WalkedPath.project(position, onto: window) else { return nil }
        let along = lower + WalkedPath.length(window) - WalkedPath.length(projection.remaining)
        return (projection.distance, max(progress, along))
    }

    private static func position(at distance: Double, path: [Position], distances: [Double]) -> Position? {
        guard let first = path.first else { return nil }
        if distance <= 0 { return first }
        for index in 1..<path.count where distances[index] >= distance {
            let length = distances[index] - distances[index - 1]
            let fraction = Float(length > 0 ? (distance - distances[index - 1]) / length : 0)
            let a = path[index - 1], b = path[index]
            return Position(x: a.x + (b.x - a.x) * fraction, z: a.z + (b.z - a.z) * fraction)
        }
        return path.last
    }

    private static func findTurns(path: [Position], distances: [Double]) -> [RouteTurn] {
        guard path.count >= 3, let total = distances.last else { return [] }
        // Ramer–Douglas–Peucker removes sub-half-metre hand movement around
        // saved rooms. It never changes the path used to track the person.
        var kept: Set<Int> = [0, path.count - 1]
        var pending = [(0, path.count - 1)]
        while let (start, end) = pending.popLast() {
            guard end > start + 1 else { continue }
            var greatest = 0.45
            var split: Int?
            for index in (start + 1)..<end {
                let deviation = WalkedPath.project(path[index], onto: [path[start], path[end]])?.distance ?? 0
                if deviation > greatest { greatest = deviation; split = index }
            }
            if let split {
                kept.insert(split)
                pending.append((start, split))
                pending.append((split, end))
            }
        }
        var turns: [RouteTurn] = []
        let vertices = kept.sorted()
        for offset in 1..<(vertices.count - 1) {
            let index = vertices[offset]
            // A short sideways reach to mark a room, followed by a return to the
            // hallway, is not a hallway turn.
            guard path[vertices[offset - 1]].distance(to: path[index]) >= 0.9,
                  path[index].distance(to: path[vertices[offset + 1]]) >= 0.9 else { continue }
            let distance = distances[index]
            // Use metre-scale travel on both sides, rather than the direction of
            // a tiny sample or the phone's orientation at a marked stop.
            guard distance >= 1, total - distance >= 1,
                  let before = position(at: max(0, distance - 1.5), path: path, distances: distances),
                  let after = position(at: min(total, distance + 1.5), path: path, distances: distances) else { continue }
            let corner = path[index]
            let incoming = Position(x: corner.x - before.x, z: corner.z - before.z)
            let outgoing = Position(x: after.x - corner.x, z: after.z - corner.z)
            guard hypot(incoming.x, incoming.z) >= 0.7, hypot(outgoing.x, outgoing.z) >= 0.7 else { continue }
            let angle = atan2(Double(incoming.x * outgoing.z - incoming.z * outgoing.x),
                              Double(incoming.x * outgoing.x + incoming.z * outgoing.z))
            guard abs(angle) >= .pi / 4 else { continue }
            let direction: RouteTurnDirection = abs(angle) > 2.4 ? .around : angle > 0 ? .right : .left
            let turn = RouteTurn(id: index, position: corner, distance: distance, direction: direction)
            // Several samples rounding one corner should produce one maneuver.
            if let previous = turns.last, previous.direction == direction, distance - previous.distance < 1.5 {
                continue
            }
            turns.append(turn)
        }
        return turns
    }
}

struct DestinationAnnouncements {
    private var warned = false

    mutating func update(remaining: Double, isFinalLeg: Bool) -> String? {
        // Use walked distance on the final leg, not proximity through a wall.
        guard isFinalLeg, !warned, remaining > 1, remaining <= 3 else { return nil }
        warned = true
        let meters = max(1, Int(remaining.rounded()))
        return "Your destination is in about \(meters) \(meters == 1 ? "meter" : "meters"). Check the room sign as you approach."
    }
}

struct TurnPresentation {
    let instruction: String
    let symbol: String
    let detail: String

    init(turn: RouteTurn, progress: Double, position: Position) {
        let remaining = turn.distance - progress
        let atTurn = remaining >= -0.5 && remaining <= 1
            && position.distance(to: turn.position) <= 1.1
        if atTurn {
            instruction = "\(turn.direction.instruction) now"
            symbol = turn.direction.symbol
            detail = "Follow the hallway around the corner."
        } else if remaining <= 1 {
            instruction = "Follow the hallway around the corner"
            symbol = turn.direction.symbol
            detail = "Continue onto the outgoing hallway."
        } else {
            let meters = max(1, Int(remaining.rounded()))
            instruction = remaining <= 5 ? "\(turn.direction.instruction) in about \(meters) m" : "Continue straight"
            symbol = remaining <= 5 ? turn.direction.symbol : "arrow.up"
            detail = remaining <= 5 ? "Upcoming turn · follow the scanned hallway."
                : "\(turn.direction.instruction) in about \(meters) m"
        }
    }
}

struct TurnCue: Equatable {
    enum Phase { case warning, turnNow }
    let turnID: Int
    let phase: Phase
    let text: String
}

struct TurnAnnouncements {
    private var warned: Set<Int> = []
    private var instructed: Set<Int> = []
    private var completed: Set<Int> = []

    mutating func announcement(plan: TurnRoutePlan, progress: Double, position: Position, starting: Bool = false) -> String? {
        // Consume completed corners even when a more urgent maneuver takes
        // priority, so a delayed straight cue cannot interrupt a later turn.
        var justCompleted = false
        for turn in plan.turns where progress > turn.distance + 0.9 {
            if completed.insert(turn.id).inserted { justCompleted = true }
        }
        let next = plan.nextTurn(after: progress)
        let cue = next.flatMap { update(turn: $0, progress: progress, position: position) }
        if cue?.phase == .turnNow { return cue?.text }
        if justCompleted || starting {
            // Do not say straight while already entering the next corner.
            if let next, next.distance - progress <= 1 { return cue?.text }
            return ["Continue straight.", cue?.text].compactMap { $0 }.joined(separator: " ")
        }
        return cue?.text
    }

    mutating func update(turn: RouteTurn, progress: Double, position: Position) -> TurnCue? {
        let remaining = turn.distance - progress
        // Turn-now always wins if both thresholds were crossed between frames.
        // A missed/old corner must never tell someone to turn after passing it.
        if remaining >= -0.5, remaining <= 1, position.distance(to: turn.position) <= 1.1 {
            guard instructed.insert(turn.id).inserted else { return nil }
            warned.insert(turn.id)
            return TurnCue(turnID: turn.id, phase: .turnNow, text: "\(turn.direction.instruction) now.")
        }
        if remaining > 1, remaining <= 5, !instructed.contains(turn.id), warned.insert(turn.id).inserted {
            let meters = max(1, Int(remaining.rounded()))
            return TurnCue(turnID: turn.id, phase: .warning,
                           text: "In about \(meters) meters, \(turn.direction.instruction.lowercased()).")
        }
        return nil
    }
}
