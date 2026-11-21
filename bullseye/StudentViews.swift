import SwiftUI
import MapKit

struct RoomDetail: View {
    let map: BuildingMap
    let room: Room
    var practice = false
    var store: CampusStore?
    @State private var startID: UUID?
    @State private var stepFree = false
    @State private var manual = false

    var starts: [Waypoint] { map.startingPoints }
    var start: Waypoint? { startID.flatMap { map.point($0) } }
    var plan: [RouteLink]? { start.flatMap { map.route(from: $0.id, to: room.waypointID, stepFree: stepFree) } }
    var hasScan: Bool { map.zones.contains { $0.worldMap != nil } }

    var body: some View {
        Page {
            DestinationHeading(code: "\(map.code) \(room.number)", building: map.building,
                               floor: map.point(room.waypointID)?.floor ?? "—")
            Toggle("Step-free routes only", isOn: $stepFree).tint(CampusTheme.pine)
            if !practice && hasScan {
                StatusNote(text: "Point your camera at the surrounding hallway. Bullseye finds your position in the saved scan and guides you along recorded paths.", icon: "viewfinder")
                Toggle("Choose a starting location manually", isOn: $manual)
            }
            if manual || practice || !hasScan {
                Picker("Starting location", selection: $startID) {
                    Text("Choose a room or landmark").tag(Optional<UUID>.none)
                    ForEach(starts) { Text("\($0.name) · Floor \($0.floor)").tag(Optional($0.id)) }
                }
                if let start, let plan {
                    if !start.facing.isEmpty { Text(start.facing) }
                    RouteStops(map: map, start: start, links: plan)
                } else if startID != nil {
                    StatusNote(text: stepFree ? "No verified step-free route from this location." : "No verified route from this location.", isError: true)
                }
                StatusNote(text: practice ? "Practice guide · not a campus route." : "Manual guide. Use the named landmarks and room signs to advance.")
            }
            if !hasScan && !practice {
                StatusNote(text: "This map has no camera scan yet. A volunteer can scan it to enable automatic location.")
            }
        }
        .navigationTitle("Room & route").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomAction {
                if !manual && !practice && hasScan {
                    NavigationLink {
                        AutomaticGuidanceView(map: map, room: room, stepFree: stepFree)
                    } label: {
                        Label("Find my position & guide me", systemImage: "viewfinder")
                    }.buttonStyle(PrimaryButton())
                } else if let start, let plan {
                    NavigationLink {
                        GuidanceView(map: map, room: room, start: start, links: plan, practice: practice)
                    } label: {
                        Label("Start manual directions", systemImage: "arrow.up")
                    }.buttonStyle(PrimaryButton())
                }
            }
        }
        .onAppear {
            if practice && startID == nil { startID = starts.first?.id }
        }
    }
}

struct DestinationHeading: View {
    let code: String
    let building: String
    let floor: String
    @ScaledMetric(relativeTo: .title) private var titleSize = 28
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("YOUR DESTINATION", systemImage: "mappin.circle").font(.caption.bold()).tracking(1.4).foregroundStyle(CampusTheme.muted)
            Text(code).font(.system(size: titleSize, weight: .semibold)).monospacedDigit()
            Text("\(building)\nFloor \(floor)").font(.body).foregroundStyle(CampusTheme.muted)
        }
    }
}

struct ServiceDetail: View {
    let service: CampusService
    @State private var audio = AudioController()
    @State private var status: String?
    @State private var locating = false
    @State private var candidates: [MKMapItem] = []
    @State private var showCandidates = false
    var body: some View {
        Page {
            Image(systemName: service.icon).font(.system(size: 34)).padding(20)
                .background(CampusTheme.selected, in: RoundedRectangle(cornerRadius: 20)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text("CAMPUS RESOURCE").font(.caption.bold()).tracking(1.6).foregroundStyle(CampusTheme.muted)
                Text(service.name).font(.largeTitle.bold()).tracking(-0.8)
                Text(service.summary).font(.body).lineSpacing(5)
            }
            VStack(alignment: .leading, spacing: 14) {
                Label("LOCATION", systemImage: "mappin").font(.caption.bold()).tracking(1.5)
                Text("Student Services Building").font(.title3.weight(.semibold))
                Text(service.room).font(.title2.weight(.semibold)).monospacedDigit()
                Text("USF Tampa · Floor \(service.floor)").foregroundStyle(CampusTheme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
                .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            if let url = URL(string: service.source) {
                Link(destination: url) { Label(service.sourceName, systemImage: "arrow.up.right.square").frame(minHeight: 44) }
            }
            Button { audio.speak(service.summary) } label: { Label("Read answer aloud", systemImage: "speaker.wave.2").frame(minHeight: 44) }
            StatusNote(text: "Indoor coverage for SVC is not published. Keep this room number with you.", icon: "door.left.hand.open")
            if let status { StatusNote(text: status, isError: true) }
        }
        .navigationTitle("Campus service").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomAction {
                Text("Directions to the building · not a verified step-free route").font(.caption).foregroundStyle(CampusTheme.muted)
                Button { Task { await findBuilding() } } label: {
                    Label(locating ? "Finding the building…" : "Open walking directions", systemImage: "arrow.up.right")
                }.buttonStyle(PrimaryButton()).disabled(locating)
            }
        }
        .confirmationDialog("Confirm the Tampa Student Services Building", isPresented: $showCandidates, titleVisibility: .visible) {
            ForEach(Array(candidates.enumerated()), id: \.offset) { _, item in
                Button("\(item.name ?? "Building") · \(item.placemark.title ?? "")") {
                    let opened = item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                    if !opened { status = "Maps could not open. Your room and official source remain available here." }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Confirm the building name and Tampa campus location before opening Maps.") }
        .onDisappear { audio.stop() }
    }
    func findBuilding() async {
        audio.stop()
        locating = true
        defer { locating = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "University of South Florida Student Services Building SVC Tampa"
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 28.0625264, longitude: -82.4124365), latitudinalMeters: 2500, longitudinalMeters: 2500)
        do {
            let response = try await MKLocalSearch(request: request).start()
            candidates = response.mapItems.filter {
                let coordinate = $0.placemark.coordinate
                let name = ($0.name ?? "").lowercased()
                // Official USF Registrar's "Directions to SVC Building" destination,
                // checked 2026-11-21. Reject similarly named buildings elsewhere.
                let officialSVC = CLLocation(latitude: 28.0625264, longitude: -82.4124365)
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                return location.distance(from: officialSVC) < 120 &&
                    (name.contains("student services") || name.contains("student service"))
            }
            if candidates.isEmpty {
                status = "Maps did not return a clear SVC building match. Use the official source above; no uncertain pin was opened."
            } else if candidates.count == 1, let item = candidates.first {
                if !item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking]) {
                    status = "Maps could not open. Your room and official source remain available here."
                }
            } else { showCandidates = true }
        } catch { status = "Maps search is unavailable. Your SVC room and official source are still available." }
    }
}

#Preview("Room · Practice") {
    let map = Practice.map
    NavigationStack { RoomDetail(map: map, room: map.rooms[0], practice: true) }
}
#Preview("Suit-A-Bull") { NavigationStack { ServiceDetail(service: CampusService.catalog[0]) } }
