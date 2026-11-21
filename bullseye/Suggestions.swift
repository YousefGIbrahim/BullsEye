import SwiftUI

struct SuggestionForm: View {
    let store: CampusStore
    @State private var building = ""
    @State private var floor = ""
    @State private var number = ""
    @State private var label = ""
    @State private var note = ""
    @State private var message: String?
    var body: some View {
        Page {
            SectionHeading(title: "Help fill in the map.", detail: "Suggestions stay pending until a volunteer checks the location and links a waypoint.")
            Field(title: "Building name or code", text: $building)
            Field(title: "Floor", text: $floor)
            Field(title: "Room number", text: $number)
            Field(title: "Optional label", text: $label)
            Field(title: "Public landmark or correction", text: $note)
            Button("Save pending suggestion") {
                do {
                    try store.addSuggestion(Suggestion(building: building.trimmed, floor: floor.trimmed, number: number.trimmed, label: label.trimmed, note: note.trimmed))
                    message = "Saved for volunteer review. Export from Map a building to share it."
                    number = ""; label = ""; note = ""
                } catch { message = error.localizedDescription }
            }.buttonStyle(PrimaryButton()).disabled(building.trimmed.isEmpty || floor.trimmed.isEmpty || number.trimmed.isEmpty)
            if let message { StatusNote(text: message) }
        }.navigationTitle("Suggest a location").navigationBarTitleDisplayMode(.inline)
    }
}

struct SuggestionReview: View {
    let store: CampusStore
    var body: some View {
        Page {
            SectionHeading(title: "Community suggestions", detail: "Verify the sign and public access before accepting. Accepted rooms remain drafts until you publish the map.")
            if store.archive.suggestions.isEmpty { StatusNote(text: "No suggestions yet. Import a package or use Suggest a location from Home.") }
            ForEach(store.archive.suggestions) { suggestion in
                NavigationLink { SuggestionDecision(store: store, suggestion: suggestion) } label: {
                    CampusRow(icon: "bubble.left", title: "\(suggestion.building) \(suggestion.number)", subtitle: "Floor \(suggestion.floor) · \(suggestion.status)")
                }
            }
        }.navigationTitle("Suggestions")
    }
}

struct SuggestionDecision: View {
    let store: CampusStore
    let suggestion: Suggestion
    @State private var mapID: UUID?
    @State private var pointID: UUID?
    @State private var message: String?
    var map: BuildingMap? { store.archive.maps.first { $0.id == mapID } }
    var body: some View {
        Page {
            SectionHeading(title: "\(suggestion.building) \(suggestion.number)", detail: "Floor \(suggestion.floor) · \(suggestion.label)")
            Text(suggestion.note)
            Picker("Building draft", selection: $mapID) {
                Text("Choose building").tag(Optional<UUID>.none)
                ForEach(store.archive.maps) { Text("\($0.code) · \($0.building)").tag(Optional($0.id)) }
            }
            Picker("Verified stopping point", selection: $pointID) {
                Text("Choose waypoint").tag(Optional<UUID>.none)
                ForEach(map?.points ?? []) { Text("\($0.name) · Floor \($0.floor)").tag(Optional($0.id)) }
            }
            Button("Accept & link to waypoint") {
                do {
                    guard var map, let pointID, let point = map.point(pointID) else { throw DataIssue.message("Choose a building and waypoint.") }
                    guard point.floor.searchKey == suggestion.floor.searchKey else { throw DataIssue.message("The waypoint floor differs from the suggestion. Review the location first.") }
                    guard !map.rooms.contains(where: { $0.number.searchKey == suggestion.number.searchKey }) else { throw DataIssue.message("This room exists. Correct its waypoint through the map review.") }
                    map.rooms.append(Room(number: suggestion.number, label: suggestion.label, waypointID: pointID))
                    map.published = false
                    var next = store.archive
                    if let index = next.maps.firstIndex(where: { $0.id == map.id }) { next.maps[index] = map }
                    if let index = next.suggestions.firstIndex(where: { $0.id == suggestion.id }) { next.suggestions[index].status = "Accepted" }
                    try store.commit(next)
                    message = "Accepted into the draft. Review and publish the map."
                } catch { message = error.localizedDescription }
            }.buttonStyle(PrimaryButton())
            Button("Reject suggestion", role: .destructive) {
                do {
                    var next = store.archive
                    if let index = next.suggestions.firstIndex(where: { $0.id == suggestion.id }) { next.suggestions[index].status = "Rejected" }
                    try store.commit(next)
                    message = "Suggestion rejected."
                } catch { message = error.localizedDescription }
            }.frame(minHeight: 44)
            if let message { StatusNote(text: message) }
        }.navigationTitle("Review suggestion")
            .onChange(of: mapID) { _, _ in pointID = nil }
    }
}
