import SwiftUI
import AVFoundation
import UIKit

struct CaptureView: View {
    @Binding var map: BuildingMap
    let zoneID: UUID
    let save: () throws -> Void
    @State private var tracker = TrackingController()
    @State private var lastPointID: UUID?
    @State private var walked: [Position] = []
    @State private var pathBroken = false
    @State private var marking = false
    @State private var markingRoom = true
    @State private var markedPosition: Position?
    @State private var name = ""
    @State private var number = ""
    @State private var existingID: UUID?
    @State private var stepFree = false
    @State private var returnAllowed = true
    @State private var saving = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var zone: CaptureZone? { map.zones.first { $0.id == zoneID } }
    var points: [Waypoint] { map.points.filter { $0.zoneID == zoneID } }
    var lastPoint: Waypoint? { lastPointID.flatMap { map.point($0) } }
    var nearbyPoints: [Waypoint] {
        guard let markedPosition else { return [] }
        return points.filter { ($0.position?.distance(to: markedPosition) ?? .infinity) < 0.85 }
    }

    var body: some View {
        TrackingCamera(tracker: tracker)
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(tracker.status, systemImage: "viewfinder").font(.headline)
                    Text("\(points.count) stops · \(tracker.lidar ? "LiDAR + camera" : "Camera tracking")")
                        .font(.caption)
                    Text(lastPoint.map { "Walking from \($0.name). Stop at the next room or turn." }
                         ?? "Look around slowly. Mark a room or hallway stop to begin.")
                        .font(.subheadline)
                    if pathBroken {
                        Text("Path recording interrupted. Return to a saved stop and select it to reconnect.")
                            .font(.subheadline).foregroundStyle(.yellow)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding()
                .foregroundStyle(.white).background(.black.opacity(0.75))
            }
            .safeAreaInset(edge: .bottom) {
                BottomAction {
                    if let message { Text(message).font(.caption).foregroundStyle(CampusTheme.ink) }
                    HStack {
                        Button { prepareMark(room: true) } label: {
                            Label("Mark room", systemImage: "door.left.hand.open")
                        }.buttonStyle(PrimaryButton())
                        Button { prepareMark(room: false) } label: {
                            Label("Hallway / turn", systemImage: "arrow.triangle.turn.up.right.diamond")
                        }.buttonStyle(PrimaryButton())
                    }.disabled(!tracker.stable || saving)
                    if !tracker.active {
                        Button("Enable camera / retry") { Task { await begin() } }
                        if tracker.cameraAuthorization == .denied {
                            Button("Open Camera Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                    }
                    Button(saving ? "Saving…" : "Finish scan & review") { Task { await finish() } }
                        .frame(minHeight: 44).disabled(saving)
                }
            }
            .navigationTitle("Scan · Floor \(zone?.floor ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { tracker.pause(); dismiss() }.disabled(saving)
                }
            }
            .sheet(isPresented: $marking) {
                NavigationStack {
                    Form {
                        Section(markingRoom ? "Destination at this position" : "Hallway stopping point") {
                            Text("Stay here while saving. Every room can also be a starting location.")
                            if markingRoom { TextField("Room number on the sign", text: $number) }
                            TextField(markingRoom ? "Room label (optional)" : "Hallway or turn name", text: $name)
                            if !nearbyPoints.isEmpty {
                                Picker("Use existing stop", selection: $existingID) {
                                    Text("Create a new stop").tag(Optional<UUID>.none)
                                    ForEach(nearbyPoints) { Text($0.name).tag(Optional($0.id)) }
                                }
                            }
                        }
                        if let lastPoint, !pathBroken {
                            Section("Walked path from \(lastPoint.name)") {
                                Text("The camera recorded this path. Mark stops at corners and junctions so directions follow the hallway.")
                                Toggle("This entire path is step-free", isOn: $stepFree)
                                Toggle("People may walk back the same way", isOn: $returnAllowed)
                            }
                        }
                        if let message { Section { Text(message) } }
                        Button(saving ? "Saving map…" : "Save stop & keep scanning") {
                            Task { await saveStop() }
                        }.disabled(saving || (markingRoom ? number.trimmed.isEmpty : name.trimmed.isEmpty && existingID == nil))
                    }
                    .navigationTitle(markingRoom ? "Mark room" : "Mark hallway / turn")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { marking = false }.disabled(saving)
                        }
                    }
                }.interactiveDismissDisabled(saving)
            }
            .onChange(of: marking) { _, presented in
                if !presented, let position = tracker.position,
                   let last = walked.last, position.distance(to: last) > 1.5 { pathBroken = true }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { tracker.pause(); pathBroken = lastPointID != nil }
                else { Task { await begin() } }
            }
            .onDisappear { tracker.pause() }
            .task {
                await begin()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
                    tracker.update()
                    recordPosition()
                }
            }
    }

    func begin() async {
        guard let zone, !saving else { return }
        await tracker.start(zone: zone, restore: zone.worldMap != nil)
    }

    func recordPosition() {
        guard lastPointID != nil, !marking, !saving, !pathBroken else { return }
        guard tracker.stable, let position = tracker.position else { pathBroken = true; return }
        if let last = walked.last {
            let distance = last.distance(to: position)
            if distance > 1.5 { pathBroken = true; return }
            if distance < 0.3 { return }
        }
        walked.append(position)
    }

    func prepareMark(room: Bool) {
        tracker.update()
        guard tracker.stable, let position = tracker.position else { return }
        recordPosition()
        markedPosition = position
        markingRoom = room
        name = ""; number = ""; existingID = nil; message = nil
        marking = true
    }

    func saveStop() async {
        guard let zone, let position = markedPosition, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            guard tracker.stable, let current = tracker.position, current.distance(to: position) < 0.75 else {
                throw DataIssue.message("Return to the position where you tapped Mark, or cancel and mark again.")
            }
            if markingRoom && map.rooms.contains(where: { $0.number.searchKey == number.searchKey }) {
                throw DataIssue.message("That room already exists. To continue a branch, use Hallway / turn and select its existing stop.")
            }
            let world = try await tracker.saveWorldMap()
            var next = map
            let point: Waypoint
            if let existingID, let existing = map.point(existingID) {
                point = existing
            } else {
                point = Waypoint(name: markingRoom ? "Room \(number.trimmed)" : name.trimmed,
                    floor: zone.floor, zoneID: zoneID, kind: markingRoom ? "Door stopping point" : "Hallway",
                    position: position, isStart: true)
                next.points.append(point)
            }
            if markingRoom {
                next.rooms.append(Room(number: number.trimmed, label: name.trimmed, waypointID: point.id))
            }
            if let previous = lastPoint, previous.id != point.id, !pathBroken,
               let a = previous.position, let b = point.position {
                var path = walked
                if path.isEmpty { path = [a] }
                path[0] = a
                path.append(position)
                path.append(b)
                let distance = WalkedPath.length(path)
                if distance >= 0.3 {
                    let forward = RouteLink(from: previous.id, to: point.id,
                        instruction: "Follow the recorded hallway to \(point.name).",
                        stepFree: stepFree, verifiedAt: Date(), cost: distance, path: path)
                    next.links.append(forward)
                    if returnAllowed {
                        next.links.append(RouteLink(from: point.id, to: previous.id,
                            instruction: "Follow the recorded hallway to \(previous.name).",
                            stepFree: stepFree, verifiedAt: Date(), cost: distance, path: Array(path.reversed())))
                    }
                }
            }
            guard let index = next.zones.firstIndex(where: { $0.id == zoneID }) else { return }
            next.zones[index].worldMap = world
            next.published = false
            try next.validate()
            let original = map
            map = next
            do { try save() } catch { map = original; throw error }
            lastPointID = point.id
            walked = [point.position ?? position]
            pathBroken = false
            marking = false
            message = "Saved \(point.name). Keep the camera facing the hallway as you walk."
        } catch { message = error.localizedDescription }
    }

    func finish() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            if tracker.active {
                let world = try await tracker.saveWorldMap()
                if let index = map.zones.firstIndex(where: { $0.id == zoneID }) {
                    map.zones[index].worldMap = world
                }
            }
            try save()
            tracker.pause()
            dismiss()
        } catch { message = "Not saved: \(error.localizedDescription)" }
    }
}
