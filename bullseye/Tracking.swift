import SwiftUI
import ARKit
import RealityKit
import AVFoundation
import Observation

@MainActor @Observable final class TrackingController {
    @ObservationIgnored private var cameraView: ARView?
    var view: ARView {
        if let cameraView { return cameraView }
        let camera = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        cameraView = camera
        return camera
    }
    var cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
    var starting = false
    var status = "Camera is off"
    var active = false
    var normal = false
    var mapReady = false
    var position: Position?
    var forward: Position?
    private var sessionStartedAt: TimeInterval = 0
    private var generation = 0
    var lidar = false
    var meshes = 0
    var restored = false
    var zoneID: UUID?
    private var stableSince: Date?
    private var lastFrameTime: TimeInterval = -1
    var stable: Bool { normal && (stableSince.map { Date().timeIntervalSince($0) >= 2 } ?? false) }

    func start(zone: CaptureZone, restore: Bool) async {
        guard !starting else { return }
        starting = true
        defer { starting = false }
        pause()
        let token = generation
        cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraAuthorization == .notDetermined {
            status = "Allow camera access to start mapping"
            _ = await AVCaptureDevice.requestAccess(for: .video)
            cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        }
        guard !Task.isCancelled, token == generation else { return }
        guard cameraAuthorization == .authorized else {
            status = cameraAuthorization == .restricted
                ? "Camera is restricted by device settings. Check Screen Time or device management."
                : "Camera access is off. Open Settings and enable Camera for Bullseye."
            return
        }
        guard ARWorldTrackingConfiguration.isSupported else { status = "Camera mapping requires an AR-capable iPhone or iPad."; return }
        let configuration = ARWorldTrackingConfiguration()
        lidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        if lidar {
            configuration.sceneReconstruction = .mesh
            view.debugOptions.insert(.showSceneUnderstanding)
        }
        restored = false
        if restore {
            guard let data = zone.worldMap else { status = "No saved AR map for this zone. Use manual guidance."; return }
            do {
                guard let world = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
                    throw DataIssue.message("Unreadable AR map.")
                }
                configuration.initialWorldMap = world
                restored = true
            } catch { status = "Saved AR map could not load. Use manual guidance."; return }
        }
        zoneID = zone.id
        status = restore ? "Finding your position · scan the surrounding hallway" : "Preparing tracking · move slowly"
        sessionStartedAt = ProcessInfo.processInfo.systemUptime
        active = true
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    func update() {
        guard active, let frame = cameraView?.session.currentFrame else { return }
        guard frame.timestamp >= sessionStartedAt else { return }
        guard ProcessInfo.processInfo.systemUptime - frame.timestamp < 1 else {
            normal = false; mapReady = false; stableSince = nil; position = nil; forward = nil
            status = "Tracking paused · look toward a known landmark or continue manually"
            return
        }
        guard frame.timestamp != lastFrameTime else { return }
        lastFrameTime = frame.timestamp
        if case .normal = frame.camera.trackingState {
            normal = true
            if stableSince == nil { stableSince = Date() }
            let p = frame.camera.transform.columns.3
            position = Position(x: p.x, z: p.z)
            let axis = frame.camera.transform.columns.2
            let magnitude = hypot(axis.x, axis.z)
            forward = magnitude > 0.25 ? Position(x: -axis.x / magnitude, z: -axis.z / magnitude) : nil
            mapReady = frame.worldMappingStatus == .mapped || frame.worldMappingStatus == .extending
            meshes = frame.anchors.filter { $0 is ARMeshAnchor }.count
            status = stable ? (restored ? "Tracking" : mapReady ? "Ready to capture" : "Mapping · look around slowly") : "Stabilizing tracking"
        } else {
            normal = false; mapReady = false; stableSince = nil
            position = nil; forward = nil
            status = restored ? "Finding your position · scan nearby walls and signs" : "Tracking limited · move slowly in good light"
        }
    }
    func saveWorldMap() async throws -> Data {
        guard active, stable, mapReady else { throw DataIssue.message("Keep scanning until tracking is stable and mapping is ready, then save again.") }
        return try await withCheckedThrowingContinuation { continuation in
            view.session.getCurrentWorldMap { map, error in
                do {
                    if let error { throw error }
                    guard let map else { throw DataIssue.message("ARKit did not return a map. Keep scanning and retry.") }
                    continuation.resume(returning: try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func pause() {
        generation += 1
        cameraView?.session.pause()
        active = false; normal = false; mapReady = false; position = nil; forward = nil
        lidar = false; meshes = 0
        stableSince = nil; lastFrameTime = -1
    }
}

struct TrackingCamera: UIViewRepresentable {
    let tracker: TrackingController
    func makeUIView(context: Context) -> ARView { tracker.view }
    func updateUIView(_ uiView: ARView, context: Context) {}
}

struct GuidanceView: View {
    let map: BuildingMap
    let room: Room
    let start: Waypoint
    let links: [RouteLink]
    var practice = false
    @State private var index = 0
    @State private var arrived = false
    @State private var confirmEnd = false
    @State private var audio = AudioController()
    @AppStorage("voiceGuidanceEnabled") private var voiceEnabled = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var directionSize = 32
    var link: RouteLink? { links.indices.contains(index) ? links[index] : nil }
    var currentPoint: Waypoint { link.flatMap { map.point($0.from) } ?? map.point(room.waypointID) ?? start }
    var instruction: String {
        if arrived { return "You’ve arrived." }
        guard let link else { return "Confirm the room sign: \(map.code) \(room.number)." }
        if link.kind == .elevator {
            return "\(link.instruction) Confirm floor \(map.point(link.to)?.floor ?? "") after you exit."
        }
        return link.instruction
    }
    var body: some View {
        Page {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(map.code) \(room.number)").font(.title2.bold()).monospacedDigit()
                    Text("Floor \(currentPoint.floor)").foregroundStyle(CampusTheme.muted)
                }
                Spacer()
                Button(role: .destructive) { confirmEnd = true } label: { Text("End route").frame(minWidth: 44, minHeight: 44) }
            }
            VStack(alignment: .leading, spacing: 24) {
                Text(arrived ? "DESTINATION REACHED" : "Step \(min(index + 1, links.count + 1)) of \(links.count + 1)")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(CampusTheme.gold)
                Image(systemName: arrived ? "checkmark.circle" : link?.kind == .elevator ? "arrow.up.arrow.down" : link == nil ? "mappin.circle" : link?.direction ?? "arrow.up")
                    .font(.system(size: 56, weight: .medium)).accessibilityHidden(true)
                Text(instruction).font(.system(size: directionSize, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                if arrived { Text("\(map.code) \(room.number) · Floor \(map.point(room.waypointID)?.floor ?? "")").font(.title3) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
                .foregroundStyle(.white).background(CampusTheme.pine, in: RoundedRectangle(cornerRadius: 22))
            if !arrived {
                if let link, let next = map.point(link.to) {
                    Label("Next stop · \(next.name)", systemImage: link.kind == .elevator ? "arrow.up.arrow.down.circle" : "smallcircle.filled.circle")
                        .font(.headline)
                }
                if practice { StatusNote(text: "Practice guide · not a real campus route", icon: "testtube.2") }
                StatusNote(text: "Manual guide · advance when you reach the named landmark", icon: "hand.tap")
            }
        }.navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                BottomAction {
                    if arrived {
                        Button("Done") { audio.stop(); dismiss() }.buttonStyle(PrimaryButton())
                    } else {
                        Toggle("Voice directions", isOn: $voiceEnabled)
                        Button(link?.kind == .elevator ? "I’m on floor \(link.flatMap { map.point($0.to)?.floor } ?? "") · exited elevator" : link == nil ? "Confirm arrival" : "Next step") { advance() }.buttonStyle(PrimaryButton())
                        Button { speakInstruction() } label: { Label("Repeat instruction", systemImage: "speaker.wave.2").font(.headline).frame(minHeight: 44) }.disabled(!voiceEnabled)
                    }
                }
            }
            .confirmationDialog("End this route?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End route", role: .destructive) { audio.stop(); dismiss() }
                Button("Keep guiding", role: .cancel) {}
            }
            .onAppear { speakInstruction() }
            .onChange(of: voiceEnabled) { _, enabled in
                if enabled { speakInstruction() } else { audio.stop() }
            }
            .onDisappear { audio.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { audio.stop() }
            }
    }
    func advance() {
        guard !arrived else { return }
        if index < links.count { index += 1 } else { arrived = true }
        speakInstruction()
    }

    private func speakInstruction() {
        if voiceEnabled { audio.speak(instruction) }
    }

}

#Preview("Guidance · Practice") {
    let map = Practice.map
    GuidanceView(map: map, room: map.rooms[0], start: map.points[0], links: map.links, practice: true)
}
