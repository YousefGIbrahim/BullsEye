import SwiftUI
import UniformTypeIdentifiers

struct MapLibrary: View {
    let store: CampusStore
    @State private var creating = false
    @State private var importing = false
    @State private var exporting = false
    @State private var document = MapDocument(data: Data())
    @State private var message: String?
    var body: some View {
        Page {
            SectionHeading(title: "Map your campus.", detail: "Capture a public route, name its landmarks, then review before publishing.")
            StatusNote(text: "Scan authorized public areas only. Camera video and microphone audio are never included in exports.", icon: "lock.shield")
            Button { creating = true } label: { Label("New building draft", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButton())
            VStack(spacing: 0) {
                ForEach(store.archive.maps) { map in
                    HStack(spacing: 0) {
                        NavigationLink { MapEditor(store: store, initial: map) } label: {
                            CampusRow(icon: map.published ? "checkmark.circle" : "pencil", title: "\(map.code) · \(map.building)", subtitle: "\(map.published ? "Published" : "Draft") · \(map.rooms.count) rooms · \(map.zones.count) zones")
                        }
                        Menu {
                            Button {
                                do {
                                    try store.setPublished(!map.published, id: map.id)
                                    message = map.published ? "Unpublished \(map.code)." : "Published \(map.code)."
                                } catch { message = error.localizedDescription }
                            } label: {
                                Label(map.published ? "Unpublish" : "Publish", systemImage: map.published ? "eye.slash" : "checkmark.circle")
                            }
                            Button(role: .destructive) {
                                do {
                                    try store.deleteDraft(id: map.id)
                                    message = "Deleted \(map.code) draft."
                                } catch { message = error.localizedDescription }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }.disabled(map.published)
                            if map.published {
                                Text("Unpublish before deleting")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.title3)
                                .frame(width: 48, height: 48)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Options for \(map.code) · \(map.building)")
                        .padding(.trailing, 6)
                    }
                    .background(CampusTheme.surface)
                }
            }
            if store.archive.maps.isEmpty {
                StatusNote(text: "No saved maps yet. Start with one recognizable entrance and one real room.")
            }
            NavigationLink { SuggestionReview(store: store) } label: {
                CampusRow(icon: "bubble.left", title: "Location suggestions", subtitle: "\(store.archive.suggestions.filter { $0.status == "Pending" }.count) pending review")
            }
            HStack {
                Button { importing = true } label: { Label("Import", systemImage: "square.and.arrow.down").frame(minHeight: 44) }
                Spacer()
                Button {
                    do { document = MapDocument(data: try store.exportData()); exporting = true }
                    catch { message = error.localizedDescription }
                } label: { Label("Export all", systemImage: "square.and.arrow.up").frame(minHeight: 44) }
            }
            NavigationLink {
                let map = Practice.map
                RoomDetail(map: map, room: map.rooms[0], practice: true)
            } label: { Label("Try a clearly labeled practice guide", systemImage: "testtube.2").frame(minHeight: 44) }
            if let message { StatusNote(text: message) }
        }
        .navigationTitle("Volunteer maps").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $creating) { NavigationStack { NewMapView(store: store) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 100_000_000 else { throw DataIssue.message("Package exceeds 100 MB. Nothing was imported.") }
                    try store.importData(Data(contentsOf: url))
                    message = "Imported successfully. Published rooms are searchable now."
                } catch { message = error.localizedDescription }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Bullseye-campus-package") { result in
                switch result { case .success: message = "Export saved. Share it through Files or AirDrop."
                case .failure(let error): message = error.localizedDescription }
            }
    }
}

struct NewMapView: View {
    let store: CampusStore
    @Environment(\.dismiss) private var dismiss
    @State private var building = ""
    @State private var code = ""
    @State private var floor = "1"
    @State private var message: String?
    var body: some View {
        Page {
            SectionHeading(title: "Start with a real place.", detail: "Use the building name and room signs you observe on site.")
            Field(title: "Building name", text: $building)
            Field(title: "Building code", text: $code)
            Field(title: "First floor", text: $floor)
            Button("Create draft") {
                do {
                    guard !floor.trimmed.isEmpty else { throw DataIssue.message("Enter the floor.") }
                    let map = BuildingMap(building: building.trimmed, code: code.trimmed.uppercased(), zones: [CaptureZone(floor: floor.trimmed, name: "First capture")])
                    try store.save(map)
                    dismiss()
                } catch { message = error.localizedDescription }
            }.buttonStyle(PrimaryButton())
            if let message { StatusNote(text: message, isError: true) }
        }.navigationTitle("New building")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}

struct MapEditor: View {
    let store: CampusStore
    @State private var map: BuildingMap
    @State private var capture = false
    @State private var addingLink = false
    @State private var addingZone = false
    @State private var newFloor = ""
    @State private var message: String?
    @State private var editingLink: RouteLink?
    @State private var editingPoint: Waypoint?
    @State private var editingRoom: Room?
    @State private var zoneID: UUID?
    @State private var confirmPublish = false
    init(store: CampusStore, initial: BuildingMap) { self.store = store; _map = State(initialValue: initial) }
    var body: some View {
        Page {
            SectionHeading(title: "\(map.code) · \(map.building)", detail: map.published ? "Published · edit a connection to close or correct it." : "Draft · visible only to volunteers")
            VStack(alignment: .leading, spacing: 12) {
                Text("CAPTURE CHECKLIST").font(.caption.bold()).tracking(1.5)
                Text("1. Scan the hallway with the camera.\n2. Stop beside a room sign and tap Mark room.\n3. Keep scanning as you walk; mark every turn or junction.\n4. To add a branch, return to a stop and select it under Hallway / turn.\n5. Finish scanning, review connections, and publish.")
                    .lineSpacing(6)
            }.padding(20).background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            Picker("Capture zone", selection: $zoneID) {
                ForEach(map.zones) { zone in Text("Floor \(zone.floor) · \(zone.name)").tag(Optional(zone.id)) }
            }
            Button { map.published = false; persist("Map returned to draft for capture."); capture = true } label: { Label("Capture or add waypoints", systemImage: "viewfinder") }.buttonStyle(PrimaryButton())
            Button("Add a separate floor / capture zone") { addingZone = true }.frame(minHeight: 44)
            SectionHeading(title: "Waypoints", detail: "Rooms also work as starting locations. Tap a stop to rename or delete it.")
            VStack(spacing: 0) {
                ForEach(map.points) { point in
                    Button { editingPoint = point } label: {
                        CampusRow(icon: point.isStart ? "flag" : "mappin", title: point.name, subtitle: "Floor \(point.floor) · \(point.position == nil ? "Manual" : "AR position")\(point.isStart ? " · Start" : "")")
                    }
                }
            }
            SectionHeading(title: "Connections", detail: "Scanning records walked paths in both permitted directions. Review access and step-free status here; add floor transfers explicitly.")
            VStack(spacing: 0) {
                ForEach(map.links) { link in
                    Button { editingLink = link } label: {
                        CampusRow(icon: link.closed ? "xmark.circle" : link.stepFree ? "figure.roll" : "arrow.right", title: "\(map.point(link.from)?.name ?? "?") → \(map.point(link.to)?.name ?? "?")", subtitle: "\(link.kind.rawValue) · \(link.closed ? "Closed" : link.verifiedAt == nil ? "Unverified" : "Verified")")
                    }
                }
            }
            Button("Add directed connection") { addingLink = true }.disabled(map.points.count < 2).frame(minHeight: 44)
            SectionHeading(title: "Room labels", detail: "\(map.rooms.count) destinations linked to stopping points")
            ForEach(map.rooms) { room in
                VStack(alignment: .leading, spacing: 4) {
                    NavigationLink { RoomDetail(map: map, room: room) } label: {
                        CampusRow(icon: "door.left.hand.open", title: "\(map.code) \(room.number)", subtitle: "\(room.label) · Test route")
                    }
                    Button("Edit \(map.code) \(room.number) label") { editingRoom = room }.frame(minHeight: 44)
                }
            }
            if map.published {
                Button("Unpublish this map", role: .destructive) { map.published = false; persist("Unpublished. Rooms are no longer in student search.") }.frame(minHeight: 44)
            }
            if let message { StatusNote(text: message) }
        }.navigationTitle("Review map").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                BottomAction {
                    Button(map.published ? "Save reviewed changes" : "Publish reviewed map") { confirmPublish = true }.buttonStyle(PrimaryButton())
                }
            }
            .onAppear { if zoneID == nil { zoneID = map.zones.first?.id } }
            .fullScreenCover(isPresented: $capture) {
                if let zoneID {
                    NavigationStack { CaptureView(map: $map, zoneID: zoneID, save: { try store.save(map) }) }
                }
            }
            .sheet(isPresented: $addingLink) { NavigationStack { LinkEditor(map: map) { link in map.links.append(link); persist("Connection saved.") } } }
            .sheet(item: $editingLink) { link in
                NavigationStack { LinkEditor(map: map, existing: link) { updated in
                    if let index = map.links.firstIndex(where: { $0.id == updated.id }) { map.links[index] = updated }
                    persist("Connection updated.")
                } }
            }
            .sheet(item: $editingRoom) { room in
                NavigationStack { RoomEditor(map: map, room: room, save: { updated in
                    if let index = map.rooms.firstIndex(where: { $0.id == updated.id }) { map.rooms[index] = updated }
                    persist("Room label corrected.")
                }, delete: {
                    map.rooms.removeAll { $0.id == room.id }
                    persist("Room label removed.")
                }) }
            }
            .sheet(item: $editingPoint) { point in
                NavigationStack { PointEditor(point: point, save: { updated in
                    if let index = map.points.firstIndex(where: { $0.id == point.id }) { map.points[index] = updated }
                    persist("Waypoint saved.")
                }, delete: {
                    map.points.removeAll { $0.id == point.id }
                    map.rooms.removeAll { $0.waypointID == point.id }
                    map.links.removeAll { $0.from == point.id || $0.to == point.id }
                    map.published = false
                    persist("Waypoint and dependent connections removed. Review before republishing.")
                }) }
            }
            .alert("New floor or capture zone", isPresented: $addingZone) {
                TextField("Floor label", text: $newFloor)
                Button("Add") {
                    guard !newFloor.trimmed.isEmpty else { return }
                    let zone = CaptureZone(floor: newFloor.trimmed, name: "Capture \(map.zones.count + 1)")
                    map.zones.append(zone); zoneID = zone.id; newFloor = ""
                    persist("New zone saved. Connect floors explicitly after capture.")
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Every independent capture gets its own AR coordinate system.") }
            .confirmationDialog("Publish only observed, reviewed data?", isPresented: $confirmPublish, titleVisibility: .visible) {
                Button("Publish reviewed map") {
                    do {
                        try map.validate()
                        guard !map.rooms.isEmpty else { throw DataIssue.message("Mark at least one room before publication.") }
                        map.published = true
                        try store.save(map)
                        message = "Published. Search these rooms from Home, or tap a room above to test."
                    } catch { map.published = false; message = error.localizedDescription }
                }
                Button("Keep draft", role: .cancel) {}
            }
    }
    func persist(_ success: String) {
        do { try store.save(map); message = success }
        catch { message = "Not saved: \(error.localizedDescription)" }
    }
}

struct LinkEditor: View {
    let map: BuildingMap
    let save: (RouteLink) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var link: RouteLink
    @State private var verified: Bool
    @State private var message: String?
    init(map: BuildingMap, existing: RouteLink? = nil, save: @escaping (RouteLink) -> Void) {
        self.map = map; self.save = save
        _link = State(initialValue: existing ?? RouteLink(from: map.points.first?.id ?? UUID(), to: map.points.dropFirst().first?.id ?? UUID(), instruction: ""))
        _verified = State(initialValue: existing?.verifiedAt != nil)
    }
    var body: some View {
        Page {
            Picker("From", selection: $link.from) { ForEach(map.points) { Text("\($0.name) · \($0.floor)").tag($0.id) } }
            Picker("To", selection: $link.to) { ForEach(map.points) { Text("\($0.name) · \($0.floor)").tag($0.id) } }
            Picker("Connection type", selection: $link.kind) { ForEach(LinkKind.allCases) { Text($0.rawValue).tag($0) } }
            Picker("Direction symbol", selection: $link.direction) {
                Text("Continue").tag(Optional<String>.none)
                Text("Turn left").tag(Optional("arrow.turn.up.left"))
                Text("Turn right").tag(Optional("arrow.turn.up.right"))
                Text("Turn around").tag(Optional("arrow.uturn.down"))
            }
            Field(title: "Landmark instruction in this direction", text: $link.instruction)
            Toggle("Observed and verified on site today", isOn: $verified)
            Toggle("Verified step-free", isOn: $link.stepFree).disabled(link.kind == .stairs)
            Toggle("Closed / blocked", isOn: $link.closed)
            if let date = link.verifiedAt { Text("Last verified \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
            StatusNote(text: "Enable step-free only after observing the full connection, including doors and elevator operation.")
            Button("Save connection") {
                do {
                    link.verifiedAt = verified ? Date() : nil
                    if link.kind == .stairs { link.stepFree = false }
                    if let a = map.point(link.from), let b = map.point(link.to), a.zoneID == b.zoneID,
                       let p = a.position, let q = b.position {
                        link.cost = max(0.1, link.path.map { WalkedPath.length($0) } ?? p.distance(to: q))
                    }
                    var candidate = map
                    candidate.links.removeAll { $0.id == link.id }
                    candidate.links.append(link)
                    try candidate.validate()
                    save(link); dismiss()
                } catch { message = error.localizedDescription }
            }.buttonStyle(PrimaryButton())
            if let message { StatusNote(text: message, isError: true) }
        }.navigationTitle("Directed connection")
            .onChange(of: link.kind) { _, kind in if kind == .stairs { link.stepFree = false } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}

struct PointEditor: View {
    @State var point: Waypoint
    let save: (Waypoint) -> Void
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    var body: some View {
        Page {
            Field(title: "Landmark name", text: $point.name)
            Field(title: "Facing direction", text: $point.facing)
            Toggle("Offer as a named start", isOn: $point.isStart)
            Button("Save waypoint") { save(point); dismiss() }.buttonStyle(PrimaryButton()).disabled(point.name.trimmed.isEmpty)
            Button("Delete waypoint", role: .destructive) { confirmingDelete = true }.frame(minHeight: 44)
        }.navigationTitle("Edit waypoint")
            .confirmationDialog("Delete this point, its room labels and connections?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete(); dismiss() }
            }
    }
}
