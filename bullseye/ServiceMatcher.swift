import SwiftUI

enum ServiceMatcher {
    static func match(_ query: String) async -> [CampusService]? {
        #if DEBUG
        let configured = UserDefaults.standard.string(forKey: "proxyURL") ?? ""
        guard !configured.isEmpty else {
            UserDefaults.standard.set("Local directory · proxy not configured", forKey: "matcherStatus")
            return nil
        }
        guard query.count <= 300, let base = URL(string: configured),
              base.scheme == "https" || (base.scheme == "http" && (base.host?.hasSuffix(".local") == true || base.host == "localhost" || base.host?.hasPrefix("192.168.") == true || base.host?.hasPrefix("10.") == true)) else {
            UserDefaults.standard.set("Fallback · invalid proxy URL", forKey: "matcherStatus")
            return nil
        }
        do {
            var request = URLRequest(url: base.appending(path: "search"))
            request.httpMethod = "POST"
            request.timeoutInterval = 8
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["query": query])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 4096 else { throw DataIssue.message("Invalid response") }
            let result = try JSONDecoder().decode(MatchResult.self, from: data)
            guard ["match", "clarify", "no_match"].contains(result.status),
                  result.serviceID == nil || CampusService.catalog.contains(where: { $0.id == result.serviceID }),
                  (result.status == "match") == (result.serviceID != nil) else { throw DataIssue.message("Invalid match") }
            UserDefaults.standard.set(result.live ? "Live AI · validated response" : "Local fallback · proxy", forKey: "matcherStatus")
            if result.status == "match" { return CampusService.catalog.filter { $0.id == result.serviceID } }
            return result.status == "clarify" ? CampusService.catalog : []
        } catch {
            UserDefaults.standard.set("Local fallback · proxy unavailable", forKey: "matcherStatus")
            return nil
        }
        #else
        return nil
        #endif
    }
    struct MatchResult: Decodable {
        let status: String
        let serviceID: String?
        let live: Bool
        enum CodingKeys: String, CodingKey { case status, serviceID = "service_id", live }
    }
}

struct DebugSettings: View {
    @AppStorage("proxyURL") private var proxyURL = ""
    @AppStorage("matcherStatus") private var matcherStatus = "Local directory"
    @State private var health = ""
    var body: some View {
        Page {
            SectionHeading(title: "Service matching", detail: "Optional. No key is needed for maps, guidance or the local directory.")
            Field(title: "Mac proxy URL", text: $proxyURL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("Use https:// for hosted access, or http://Your-Mac.local:8787 on a trusted local network. Only the search text is sent. Never put an API key here.")
                .font(.subheadline)
            Button("Check proxy health") {
                Task {
                    guard let url = URL(string: proxyURL)?.appending(path: "health") else { health = "Enter a valid URL."; return }
                    do {
                        var request = URLRequest(url: url); request.timeoutInterval = 5
                        let (_, response) = try await URLSession.shared.data(for: request)
                        health = (response as? HTTPURLResponse)?.statusCode == 200 ? "Proxy reachable from this device." : "Proxy returned an error."
                    } catch { health = "Could not reach the proxy. Check the network and Mac address." }
                }
            }.frame(minHeight: 44)
            StatusNote(text: matcherStatus, icon: "gearshape")
            if !health.isEmpty { StatusNote(text: health) }
        }.navigationTitle("Debug settings")
    }
}
