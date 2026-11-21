import SwiftUI
import Observation
import UIKit
import AVFoundation

@MainActor @Observable final class AutomaticNavigator {
    let tracker = TrackingController()
    let audio = AudioController()
    var instruction = "Look around slowly to find your position."
    var symbol = "viewfinder"
    var detail = "Scan nearby walls, room signs and hallway features."
    var route: [RouteLink]?
    var atDestination = false
    var arrived = false
    var transfer: RouteLink?
    var zoneName = ""
    var loading = false
    var voiceEnabled = true {
        didSet { if !voiceEnabled { audio.stop() } }
    }
    private var zoneIndex = -1
    private var searchStarted = Date()
    private var offRouteSince: Date?
    private var hasLocated = false
    private var searchZones: [CaptureZone] = []
    private var plan: TurnRoutePlan?
    private var progress = 0.0
    private var turnAnnouncements = TurnAnnouncements()
    private var destinationAnnouncements = DestinationAnnouncements()
    private var lastStatus: String?
    private var needsAlignment = true
    private var alignedSince: Date?

    func start(map: BuildingMap, preferredZone: UUID? = nil) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        route = nil; plan = nil; transfer = nil; atDestination = false
        hasLocated = false; offRouteSince = nil
        needsAlignment = true; alignedSince = nil; lastStatus = nil
        audio.stop()
        searchZones = map.zones.filter { $0.worldMap != nil }
        if let preferredZone, let index = searchZones.firstIndex(where: { $0.id == preferredZone }) {
            zoneIndex = index
        } else {
            zoneIndex = (zoneIndex + 1) % max(1, searchZones.count)
        }
        guard searchZones.indices.contains(zoneIndex) else {
            showStatus("missingMap", instruction: "This map has no saved camera scan.",
                       detail: "Ask a volunteer to scan this route, or use the manual guide.")
            return
        }
        let zone = searchZones[zoneIndex]
        zoneName = "Floor \(zone.floor) · \(zone.name)"
        instruction = "Finding your position"
        symbol = "viewfinder"
        detail = "Look around slowly. You can begin anywhere along a scanned path."
        await tracker.start(zone: zone, restore: true)
        searchStarted = Date()
    }

    func tick(map: BuildingMap, room: Room, stepFree: Bool) async {
        guard !loading, !arrived else { return }
        tracker.update()
        guard tracker.stable, tracker.restored, let position = tracker.position, let zoneID = tracker.zoneID else {
            atDestination = false; alignedSince = nil
            if hasLocated {
                showStatus("tracking", instruction: "Pause while tracking recovers", detail: tracker.status)
            } else {
                detail = tracker.status
                if tracker.active && searchZones.count > 1 && Date().timeIntervalSince(searchStarted) > 25 {
                    await start(map: map)
                }
            }
            return
        }
        hasLocated = true
        if let transfer {
            showStatus("transfer", instruction: transfer.instruction,
                       detail: "Confirm floor \(map.point(transfer.to)?.floor ?? "") after completing this transfer.",
                       symbol: transfer.kind == .elevator ? "arrow.up.arrow.down" : "figure.stairs")
            return
        }
        if route == nil {
            guard let located = map.locatedRoute(at: position, zoneID: zoneID, to: room.waypointID, stepFree: stepFree) else {
                showStatus("noRoute", instruction: "Position found · no nearby permitted route",
                           detail: stepFree
                           ? "Move back to a scanned stop. Step-free connections must be verified by a volunteer."
                           : "Move back to a scanned stop or hallway that connects to the destination.",
                           symbol: "location.slash")
                return
            }
            route = map.continuousWalkingRoute(located.links)
            prepareLeg(map: map, approach: located.approach)
            needsAlignment = true
        }
        if route?.isEmpty == true {
            updateArrival(map: map, room: room, position: position, zoneID: zoneID)
            return
        }
        guard let first = route?.first else { return }
        guard map.point(first.to)?.zoneID == zoneID,
              first.kind != .elevator && first.kind != .stairs else {
            transfer = first
            return
        }
        guard let plan, let projection = plan.project(position, near: progress) else {
            showStatus("missingPath", instruction: "This connection needs a camera scan.",
                       detail: "Use the manual guide or ask a volunteer to recapture it.")
            return
        }
        if projection.distance > 1.25 {
            if offRouteSince == nil { offRouteSince = Date() }
            showStatus("offRoute", instruction: "Pause · you have left the recorded path",
                       detail: "Scan the surrounding hallway to find another mapped connection.")
            if Date().timeIntervalSince(offRouteSince ?? Date()) > 2 {
                route = nil; self.plan = nil; offRouteSince = nil
            }
            return
        }
        offRouteSince = nil
        progress = projection.progress
        let remaining = max(0, plan.length - progress)
        let finalLeg = route?.count == 1 && first.to == room.waypointID
        let arrivalRadius = finalLeg ? 1.2 : 0.9
        let legComplete = finalLeg
            ? remaining <= arrivalRadius && plan.nextTurn(after: progress) == nil
            : remaining < 1
        if let end = plan.path.last, legComplete, position.distance(to: end) <= arrivalRadius {
            route?.removeFirst()
            prepareLeg(map: map)
            if finalLeg { updateArrival(map: map, room: room, position: position, zoneID: zoneID) }
            return
        }

        // Heading is used only for initial orientation, never to invent a
        // spoken turn while passing a room or moving the phone.
        let starting = needsAlignment
        if needsAlignment && !alignForStart(plan: plan, position: position) { return }
        lastStatus = nil
        if let turn = plan.nextTurn(after: progress) {
            let presentation = TurnPresentation(turn: turn, progress: progress, position: position)
            instruction = presentation.instruction
            symbol = presentation.symbol
            detail = presentation.detail
        } else {
            instruction = "Continue straight"
            symbol = "arrow.up"
            let target = first.to == room.waypointID ? "\(map.code) \(room.number)" : "the floor transfer"
            detail = "No more turns · about \(max(1, Int(remaining.rounded()))) m to \(target)"
        }
        let turnAnnouncement = turnAnnouncements.announcement(plan: plan, progress: progress, position: position, starting: starting)
        let destinationAnnouncement = destinationAnnouncements.update(
            remaining: remaining, isFinalLeg: route?.count == 1 && first.to == room.waypointID)
        // Speak one combined message so the destination warning cannot cut off
        // a simultaneous turn instruction. Immediate directions come first.
        let announcements = [turnAnnouncement, destinationAnnouncement].compactMap { $0 }
        if !announcements.isEmpty, voiceEnabled {
            audio.speak(announcements.joined(separator: " "))
        }
    }

    private func prepareLeg(map: BuildingMap, approach: [Position] = []) {
        progress = 0
        turnAnnouncements = TurnAnnouncements()
        plan = route?.first.flatMap { link in
            map.geometry(for: link).map { TurnRoutePlan(path: approach + $0) }
        }
    }

    private func alignForStart(plan: TurnRoutePlan, position: Position) -> Bool {
        guard let forward = tracker.forward, let target = plan.position(at: min(plan.length, progress + 1.5)) else {
            showStatus("phone", instruction: "Hold the phone upright, facing the hallway",
                       detail: "Keep the camera facing the direction you will walk.", symbol: "iphone")
            return false
        }
        let orientation = WalkedPath.turn(from: position, forward: forward, toward: target)
        if orientation.symbol == "arrow.up" {
            if alignedSince == nil { alignedSince = Date() }
            if Date().timeIntervalSince(alignedSince ?? Date()) >= 0.6 {
                needsAlignment = false
                return true
            }
            instruction = "Ready to follow the hallway"
            symbol = "arrow.up"
            detail = "Keep the phone facing forward."
        } else {
            alignedSince = nil
            showStatus("alignment-\(orientation.symbol)",
                       instruction: "\(orientation.text) to face along the route.",
                       detail: "Hold the phone facing the direction you will walk.", symbol: orientation.symbol)
        }
        return false
    }

    private func updateArrival(map: BuildingMap, room: Room, position: Position, zoneID: UUID) {
        guard let destination = map.point(room.waypointID), destination.zoneID == zoneID,
              let target = destination.position else {
            showStatus("sign", instruction: "Use the room sign to confirm your destination.", detail: "\(map.code) \(room.number)")
            return
        }
        if position.distance(to: target) <= 1.2 {
            atDestination = true
            showStatus("arrival", instruction: "Your destination is here. Confirm the room sign.",
                       detail: "\(map.code) \(room.number) · \(room.label)", symbol: "mappin.circle")
            return
        }
        atDestination = false
        if position.distance(to: target) > 1.5 {
            route = nil; plan = nil
            return
        }
        instruction = "Check the destination sign"
        detail = "\(map.code) \(room.number)"
        symbol = "mappin.circle"
    }

    private func showStatus(_ id: String, instruction: String, detail: String, symbol: String = "viewfinder") {
        self.instruction = instruction
        self.detail = detail
        self.symbol = symbol
        if lastStatus != id {
            lastStatus = id
            if voiceEnabled { audio.speak(instruction) }
        }
    }

    func repeatInstruction() {
        if voiceEnabled { audio.speak("\(instruction). \(detail)") }
    }

    func completeTransfer(map: BuildingMap) async {
        guard let transfer, let next = map.point(transfer.to) else { return }
        await start(map: map, preferredZone: next.zoneID)
    }

    func stop() {
        tracker.pause()
        audio.stop()
    }
}

struct AutomaticGuidanceView: View {
    let map: BuildingMap
    let room: Room
    let stepFree: Bool
    @State private var navigator = AutomaticNavigator()
    @AppStorage("voiceGuidanceEnabled") private var voiceEnabled = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        TrackingCamera(tracker: navigator.tracker)
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(map.code) \(room.number)").font(.title2.bold())
                    Text(navigator.zoneName).font(.caption)
                    Label(navigator.instruction, systemImage: navigator.symbol).font(.title2.bold())
                        .accessibilityAddTraits(.updatesFrequently)
                    Text(navigator.loading ? navigator.tracker.status : navigator.detail).font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding()
                .foregroundStyle(.white).background(.black.opacity(0.8))
            }
            .safeAreaInset(edge: .bottom) {
                BottomAction {
                    if navigator.arrived {
                        Button("Done") { dismiss() }.buttonStyle(PrimaryButton())
                    } else if navigator.atDestination && navigator.tracker.stable {
                        Button("Confirm arrival · \(map.code) \(room.number)") {
                            navigator.arrived = true
                            navigator.instruction = "You’ve arrived."
                            navigator.stop()
                        }.buttonStyle(PrimaryButton())
                    } else if navigator.transfer != nil && navigator.tracker.stable {
                        Button("I’ve completed the floor transfer") {
                            Task { await navigator.completeTransfer(map: map) }
                        }.buttonStyle(PrimaryButton())
                    }
                    if !navigator.arrived {
                        Toggle("Voice directions", isOn: $voiceEnabled)
                        HStack {
                            Button("Repeat") { navigator.repeatInstruction() }.disabled(!voiceEnabled)
                                .frame(maxWidth: .infinity, minHeight: 44)
                            Button("Locate again") { Task { await navigator.start(map: map) } }
                                .frame(maxWidth: .infinity, minHeight: 44).disabled(navigator.loading)
                        }
                        if navigator.tracker.cameraAuthorization == .denied {
                            Button("Open Camera Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                        Text("Follow the scanned walkway and check your surroundings. Live obstacles are not routed around.")
                            .font(.caption).foregroundStyle(CampusTheme.muted)
                    }
                }
            }
            .navigationTitle("Camera directions").navigationBarTitleDisplayMode(.inline)
            .onDisappear { navigator.stop() }
            .onChange(of: voiceEnabled) { _, enabled in navigator.voiceEnabled = enabled }
            .onChange(of: scenePhase) { _, phase in
                // Temporary inactive states (permission prompts, Control Center)
                // must not discard localization and restart the saved map.
                if phase == .background { navigator.stop() }
                else if phase == .active && !navigator.loading && !navigator.tracker.active {
                    Task { await navigator.start(map: map, preferredZone: navigator.tracker.zoneID) }
                }
            }
            .task {
                navigator.voiceEnabled = voiceEnabled
                await navigator.start(map: map, preferredZone: map.point(room.waypointID)?.zoneID)
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
                    guard scenePhase == .active else { continue }
                    await navigator.tick(map: map, room: room, stepFree: stepFree)
                }
            }
    }
}
