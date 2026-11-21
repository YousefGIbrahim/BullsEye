import SwiftUI
import Security

enum GeminiKeyStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Bullseye.Gemini",
         kSecAttrAccount as String: "api-key"]
    }

    static func read() throws -> String? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw DataIssue.message("Could not read the saved Gemini key.")
        }
        return key
    }

    static func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else {
            throw DataIssue.message("Enter an API key without spaces.")
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(trimmed.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let addition = query.merging(attributes) { _, new in new }
            guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else {
                throw DataIssue.message("Could not save the Gemini key.")
            }
        } else if status != errSecSuccess {
            throw DataIssue.message("Could not update the Gemini key.")
        }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DataIssue.message("Could not remove the Gemini key.")
        }
    }
}

enum ServiceMatcher {
    static func search(_ query: String) async -> GeminiClient.WebAnswer? {
        do {
            guard let key = try GeminiKeyStore.read() else {
                UserDefaults.standard.set("Local directory · add a Gemini key in AI settings", forKey: "matcherStatus")
                return nil
            }
            let model = UserDefaults.standard.string(forKey: "geminiModel") ?? GeminiClient.defaultModel
            let matches = try await GeminiClient.search(query: query, key: key, model: model)
            UserDefaults.standard.set("Gemini · web sources verified", forKey: "matcherStatus")
            return matches
        } catch {
            guard !Task.isCancelled else { return nil }
            let reason = (error as? GeminiClient.Failure)?.errorDescription ?? "Check your connection or API settings."
            UserDefaults.standard.set("Local fallback · " + reason, forKey: "matcherStatus")
            return nil
        }
    }
}

struct AISettings: View {
    @AppStorage("geminiModel") private var model = GeminiClient.defaultModel
    @AppStorage("matcherStatus") private var matcherStatus = "Local directory"
    @State private var keyInput = ""
    @State private var hasKey = false
    @State private var message = ""
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?

    var body: some View {
        Page {
            SectionHeading(title: "Gemini web search", detail: "Connect directly from this phone. No Mac server is needed.")
            Text("Gemini uses Google Search to answer campus questions and look up rooms. Your search text goes to Google, including room numbers. Maps and camera scans stay on your phone.")
                .font(.subheadline)
            SecureField(hasKey ? "Enter a replacement API key" : "Gemini API key", text: $keyInput)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder).accessibilityLabel("Gemini API key")
            Text(hasKey ? "A key is saved on this device." : "No key saved. Search uses the local directory.")
                .font(.subheadline)
            HStack {
                Button("Save key") {
                    do {
                        try GeminiKeyStore.save(keyInput)
                        keyInput = ""
                        hasKey = true
                        message = "Key saved. Tap Test connection to verify it."
                    } catch { message = error.localizedDescription }
                }.disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testing)
                Spacer()
                Button("Remove key", role: .destructive) {
                    do {
                        try GeminiKeyStore.remove()
                        keyInput = ""
                        hasKey = false
                        message = "Key removed. Local directory search remains available."
                        matcherStatus = "Local directory"
                    } catch { message = error.localizedDescription }
                }.disabled(!hasKey || testing)
            }.frame(minHeight: 44)
            Field(title: "Gemini model ID", text: $model)
                .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(testing)
            Button(testing ? "Testing…" : "Test connection") {
                testing = true
                message = ""
                testTask = Task {
                    defer { testing = false }
                    do {
                        guard let key = try GeminiKeyStore.read() else { throw GeminiClient.Failure.missingKey }
                        _ = try await GeminiClient.search(query: "Where is the USF Tampa Feed-A-Bull food pantry?", key: key, model: model)
                        guard !Task.isCancelled else { return }
                        message = "Gemini web search verified. Answers with sources are ready."
                        matcherStatus = "Gemini · connection verified"
                    } catch {
                        guard !Task.isCancelled else { return }
                        message = (error as? GeminiClient.Failure)?.errorDescription ?? "Could not connect to Gemini. Check your internet connection."
                    }
                }
            }.frame(minHeight: 44).disabled(!hasKey || testing || !keyInput.isEmpty)
            if let keyURL = URL(string: "https://aistudio.google.com/apikey") {
                Link("Get a Gemini API key", destination: keyURL).frame(minHeight: 44)
            }
            Text("Keys are stored in this phone’s Keychain, not in source files or map exports. Testing sends a sample search and may use your API quota.")
                .font(.caption)
            StatusNote(text: matcherStatus, icon: "sparkles")
            if !message.isEmpty { StatusNote(text: message) }
        }
        .navigationTitle("AI settings")
        .task {
            do { hasKey = try GeminiKeyStore.read() != nil }
            catch { message = error.localizedDescription }
        }
        .onDisappear { keyInput = ""; testTask?.cancel() }
    }
}
