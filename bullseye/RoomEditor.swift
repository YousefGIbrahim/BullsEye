import SwiftUI

struct RoomEditor: View {
    let map: BuildingMap
    @State var room: Room
    let save: (Room) -> Void
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var message: String?
    var body: some View {
        Page {
            Field(title: "Room number", text: $room.number)
            Field(title: "Room label", text: $room.label)
            Field(title: "Aliases, separated by commas", text: $room.aliases)
            Picker("Stopping point", selection: $room.waypointID) {
                ForEach(map.points) { Text("\($0.name) · Floor \($0.floor)").tag($0.id) }
            }
            Button("Save correction") {
                guard !room.number.trimmed.isEmpty,
                      !map.rooms.contains(where: { $0.id != room.id && $0.number.searchKey == room.number.searchKey }) else {
                    message = "Enter a unique room number."; return
                }
                save(room)
                dismiss()
            }.buttonStyle(PrimaryButton())
            Button("Remove room label", role: .destructive) { confirmDelete = true }.frame(minHeight: 44)
            if let message { StatusNote(text: message, isError: true) }
        }.navigationTitle("Correct room")
            .confirmationDialog("Remove this destination from the map?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove room", role: .destructive) { delete(); dismiss() }
            }
    }
}
