import SwiftUI
import UIKit

enum CampusTheme {
    static let pine = Color(red: 16/255, green: 59/255, blue: 51/255)
    static let gold = Color(red: 231/255, green: 197/255, blue: 104/255)
    static let paper = adaptive(0xF6F4EC, 0x101D19)
    static let surface = adaptive(0xFFFFFF, 0x1B3029)
    static let ink = adaptive(0x162823, 0xF6F4EC)
    static let muted = adaptive(0x51635B, 0xBBCDC2)
    static let border = adaptive(0xDCE3DC, 0x738C7F)
    static let selected = adaptive(0xE5F0E8, 0x284B3D)
    static let error = adaptive(0x9A2E1D, 0xFFB5A6)
    private static func adaptive(_ light: UInt, _ dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            var value = traits.userInterfaceStyle == .dark ? dark : light
            if traits.accessibilityContrast == .high {
                if value == 0x51635B { value = 0x162823 }
                if value == 0xBBCDC2 { value = 0xFFFFFF }
                if value == 0xDCE3DC { value = 0x51635B }
            }
            return UIColor(red: CGFloat((value >> 16) & 255)/255, green: CGFloat((value >> 8) & 255)/255, blue: CGFloat(value & 255)/255, alpha: 1)
        })
    }
}

struct BullseyeMark: View {
    var size: CGFloat = 36
    var body: some View {
        ZStack {
            Circle().fill(CampusTheme.pine)
            Circle().strokeBorder(Color(red: 246/255, green: 244/255, blue: 236/255), lineWidth: size * 0.09).padding(size * 0.2)
            Circle().fill(CampusTheme.gold).padding(size * 0.39)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(.white).background(CampusTheme.pine, in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct CampusRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))
        layout {
            Image(systemName: icon).font(.title3).frame(width: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline).foregroundStyle(CampusTheme.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(CampusTheme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.bold()).accessibilityHidden(true)
        }.multilineTextAlignment(.leading).foregroundStyle(CampusTheme.ink).padding(.vertical, 19).padding(.horizontal, 18)
            .background(CampusTheme.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(CampusTheme.border).frame(height: 0.5) }
            .contentShape(Rectangle())
    }
}

struct StatusNote: View {
    let text: String
    var icon = "info.circle"
    var isError = false
    var body: some View {
        Label(text, systemImage: icon).font(.subheadline)
            .foregroundStyle(isError ? CampusTheme.error : CampusTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SectionHeading: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title2.bold())
            if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(CampusTheme.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Field: View {
    let title: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.semibold))
            TextField(title, text: $text, axis: .vertical).textFieldStyle(.plain)
                .padding(14).background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(CampusTheme.border) }
        }
    }
}

struct Page<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) { content }
                .padding(.horizontal, 22).padding(.vertical, 20)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
        }.background(CampusTheme.paper).foregroundStyle(CampusTheme.ink)
            .scrollDismissesKeyboard(.interactively)
    }
}

struct BottomAction<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 12) { content }.padding(.horizontal, 22).padding(.vertical, 12)
            .background(CampusTheme.paper)
    }
}

struct RouteStops: View {
    let map: BuildingMap
    let start: Waypoint
    let links: [RouteLink]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ROUTE SCHEMATIC").font(.caption.weight(.bold)).tracking(2).foregroundStyle(CampusTheme.muted).padding(.bottom, 20)
            StopRow(name: start.name, detail: "Start · Floor \(start.floor)", icon: "circle", last: links.isEmpty)
            ForEach(links) { link in
                if let point = map.point(link.to) {
                    StopRow(name: point.name, detail: "\(link.kind.rawValue) · Floor \(point.floor)", icon: link.kind == .elevator ? "arrow.up.arrow.down" : "circle.fill", last: link.id == links.last?.id)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct StopRow: View {
    let name: String
    let detail: String
    let icon: String
    let last: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold)).frame(width: 24, height: 24)
                if !last { Rectangle().frame(width: 2, height: 38) }
            }.foregroundStyle(CampusTheme.ink).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(CampusTheme.muted)
            }.padding(.bottom, last ? 0 : 24)
        }.accessibilityElement(children: .combine)
    }
}
