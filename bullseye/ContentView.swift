import SwiftUI

struct ContentView: View {
    @State private var store = CampusStore()
    @State private var audio = AudioController()
    @State private var query = ""
    @State private var submitted = ""
    @State private var services: [CampusService] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            Page {
                Masthead()
                SearchPanel(query: $query, focused: $searchFocused, audio: audio, searching: searching, search: search)
                if let message = audio.message { StatusNote(text: message, isError: true) }
                if let message = store.message { StatusNote(text: message, isError: true) }
                if submitted.isEmpty {
                    SectionHeading(title: "A good place to start.", detail: "Rooms and resources, one clear route at a time.")
                    VStack(spacing: 0) {
                        if let map = store.published.first, let room = map.rooms.first {
                            NavigationLink { RoomDetail(map: map, room: room, store: store) } label: {
                                CampusRow(icon: "door.left.hand.open", title: "\(map.code) \(room.number)", subtitle: "\(map.building) · Published room")
                            }
                        }
                        NavigationLink { ServiceDetail(service: CampusService.catalog[0]) } label: {
                            CampusRow(icon: "tshirt", title: "Suit-A-Bull", subtitle: "Free professional clothing · SVC 2060")
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 16))
                    if store.published.isEmpty {
                        StatusNote(text: "Indoor coverage grows with your campus. Publish a mapped room to make it searchable.", icon: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                } else {
                    SearchResults(store: store, query: submitted, services: services)
                }
                NavigationLink { MapLibrary(store: store) } label: {
                    Label("Map a building", systemImage: "viewfinder").font(.headline).frame(minHeight: 44)
                }
                NavigationLink { SuggestionForm(store: store) } label: {
                    Label("Suggest a location", systemImage: "plus.bubble").frame(minHeight: 44)
                }
                #if DEBUG
                NavigationLink("Debug settings") { DebugSettings() }.font(.footnote).frame(minHeight: 44)
                #endif
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: audio.transcript) { _, value in if !value.isEmpty { query = value } }
            .onDisappear { audio.stop(); searchTask?.cancel() }
        }.tint(CampusTheme.ink)
    }

    func search() {
        audio.stop()
        searchFocused = false
        let text = query.trimmed
        submitted = text
        services = CampusService.matching(text)
        searchTask?.cancel()
        guard !text.isEmpty else { searching = false; return }
        // Exact room queries never leave the phone.
        guard !text.searchKey.contains(where: { $0.isNumber }) else { searching = false; return }
        searching = true
        searchTask = Task {
            let result = await ServiceMatcher.match(text)
            guard !Task.isCancelled, submitted == text else { return }
            if let result { services = result }
            searching = false
        }
    }
}

struct Masthead: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            BullseyeMark()
            Text("BULLSEYE").font(.system(.title3, design: .rounded, weight: .black)).tracking(-0.7)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(typeSize.isAccessibilitySize ? "USF Tampa" : "USF\nTAMPA").font(.caption.weight(.bold)).tracking(1.2).multilineTextAlignment(.trailing)
        }.padding(.bottom, 6).accessibilityElement(children: .combine)
    }
}

struct SearchPanel: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    let audio: AudioController
    let searching: Bool
    let search: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 34
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !typeSize.isAccessibilitySize { HStack {
                Text("YOUR CAMPUS, CONNECTED").font(.caption2.bold()).tracking(1.8)
                Spacer()
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.title2).accessibilityHidden(true)
            }.foregroundStyle(CampusTheme.gold).accessibilityHidden(true) }
            Text("Find a room or\ncampus service")
                .font(.system(size: titleSize, weight: .bold)).tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").accessibilityHidden(true)
                    TextField("Room, building or a need", text: $query, prompt: Text("Room, building or a need").foregroundStyle(Color(red: 81/255, green: 99/255, blue: 91/255)))
                        .focused(focused).submitLabel(.search).onSubmit(search)
                        .autocorrectionDisabled().accessibilityLabel("Room, building or campus service")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                            .accessibilityLabel("Clear search")
                    }
                }.foregroundStyle(Color(red: 22/255, green: 40/255, blue: 35/255))
                    .padding(.leading, 16).padding(.trailing, 6).frame(minHeight: 58)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                Button {
                    if audio.recording { audio.stopRecording() }
                    else { Task { await audio.startRecording() } }
                } label: {
                    Label(audio.preparing ? "Preparing microphone…" : audio.recording ? "Listening · Tap to stop" : "Ask with your voice", systemImage: audio.recording ? "stop.circle.fill" : "mic.fill")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }.disabled(audio.preparing)
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.65)) }
                if !query.trimmed.isEmpty {
                    Button(action: search) {
                        Label(searching ? "Searching…" : "Search", systemImage: "arrow.right")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Color(red: 22/255, green: 40/255, blue: 35/255))
                            .background(CampusTheme.gold, in: RoundedRectangle(cornerRadius: 14))
                    }.disabled(searching)
                }
            }
        }.foregroundStyle(.white).padding(24)
            .background(CampusTheme.pine, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct SearchResults: View {
    let store: CampusStore
    let query: String
    let services: [CampusService]
    var matches: [(BuildingMap, Room)] {
        store.published.flatMap { map in
            map.rooms.filter {
                let key = query.searchKey
                return $0.number.searchKey == key ||
                    "\(map.code)\($0.number)".searchKey == key ||
                    "\(map.building)\($0.number)".searchKey == key ||
                    map.code.searchKey == key || map.building.searchKey.contains(key) ||
                    (!$0.label.isEmpty && $0.label.searchKey.contains(key)) ||
                    (!$0.aliases.isEmpty && $0.aliases.split(separator: ",").contains { String($0).searchKey == key })
            }.map { (map, $0) }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Search results", detail: matches.count + services.count > 1 ? "Choose the building, room or service you need." : "For “\(query)”")
            VStack(spacing: 0) {
                ForEach(matches, id: \.1.id) { map, room in
                    NavigationLink { RoomDetail(map: map, room: room, store: store) } label: {
                        CampusRow(icon: "door.left.hand.open", title: "\(map.code) \(room.number)", subtitle: "Room · \(map.building) · Floor \(map.point(room.waypointID)?.floor ?? "—")")
                    }
                }
                ForEach(services) { service in
                    NavigationLink { ServiceDetail(service: service) } label: {
                        CampusRow(icon: service.icon, title: service.name, subtitle: "Service · \(service.room) · Floor \(service.floor)")
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 16))
            if matches.isEmpty && services.isEmpty {
                StatusNote(text: "No published room or matching service found. Try a building code and room number, or suggest the location.", icon: "magnifyingglass")
            }
        }
    }
}

#Preview("Home") { ContentView() }
#Preview("Home · Dark") { ContentView().preferredColorScheme(.dark) }
#Preview("Home · Large text") { ContentView().environment(\.dynamicTypeSize, .accessibility3) }
