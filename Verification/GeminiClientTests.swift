import Foundation
import Testing
@testable import BullseyeCore

private func geminiResponse(_ text: String, finish: String = "STOP") throws -> Data {
    try JSONSerialization.data(withJSONObject: ["candidates": [[
        "finishReason": finish,
        "content": ["parts": [["text": text]]]
    ]]])
}

@Test func geminiRequestUsesHeaderAndBoundedDirectorySchema() throws {
    let request = try GeminiClient.request(query: "I need groceries", key: "test-placeholder", model: GeminiClient.defaultModel)
    #expect(request.url?.host == "generativelanguage.googleapis.com")
    #expect(request.url?.query == nil)
    #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-placeholder")
    let body = try #require(request.httpBody)
    #expect(!String(decoding: body, as: UTF8.self).contains("test-placeholder"))
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let config = try #require(object["generationConfig"] as? [String: Any])
    #expect(config["responseMimeType"] as? String == "application/json")
    #expect(config["responseJsonSchema"] != nil)
    #expect(request.timeoutInterval == 15)
}

@Test func geminiRejectsInvalidInputBeforeNetworking() {
    #expect(throws: (any Error).self) { try GeminiClient.request(query: "", key: "test", model: GeminiClient.defaultModel) }
    #expect(throws: (any Error).self) { try GeminiClient.request(query: String(repeating: "x", count: 301), key: "test", model: GeminiClient.defaultModel) }
    #expect(throws: (any Error).self) { try GeminiClient.request(query: "food", key: "", model: GeminiClient.defaultModel) }
    #expect(throws: (any Error).self) { try GeminiClient.request(query: "food", key: "test", model: "../other?key=oops") }
}

@Test func geminiOnlyAcceptsKnownConsistentDirectoryMatches() throws {
    let match = try geminiResponse(#"{"status":"match","service_id":"feed-a-bull"}"#)
    #expect(try GeminiClient.services(data: match, statusCode: 200).map(\.id) == ["feed-a-bull"])
    let clarify = try geminiResponse(#"{"status":"clarify","service_id":null}"#)
    #expect(try GeminiClient.services(data: clarify, statusCode: 200).count == CampusService.catalog.count)
    let noMatch = try geminiResponse(#"{"status":"no_match","service_id":null}"#)
    #expect(try GeminiClient.services(data: noMatch, statusCode: 200).isEmpty)
    for invalid in [
        #"{"status":"match","service_id":"invented"}"#,
        #"{"status":"match","service_id":null}"#,
        #"{"status":"clarify","service_id":"suit-a-bull"}"#,
        #"{"status":"no_match"}"#,
        #"{"status":"match","service_id":"suit-a-bull","directions":"turn left"}"#
    ] {
        let data = try geminiResponse(invalid)
        #expect(throws: (any Error).self) { try GeminiClient.services(data: data, statusCode: 200) }
    }
}

@Test func geminiRejectsBlockedTruncatedAndHTTPFailures() throws {
    for finish in ["SAFETY", "MAX_TOKENS"] {
        let data = try geminiResponse(#"{"status":"match","service_id":"feed-a-bull"}"#, finish: finish)
        #expect(throws: (any Error).self) { try GeminiClient.services(data: data, statusCode: 200) }
    }
    for code in [400, 401, 403, 404, 429, 500] {
        #expect(throws: (any Error).self) { try GeminiClient.services(data: Data(), statusCode: code) }
    }
    #expect(throws: (any Error).self) { try GeminiClient.services(data: Data(repeating: 0, count: 65_537), statusCode: 200) }
    #expect(throws: (any Error).self) { try GeminiClient.services(data: Data("{}".utf8), statusCode: 200) }
}

@Test func webSearchEnablesGoogleForRoomNumberQueries() throws {
    let request = try GeminiClient.webRequest(query: "Where is USF SVC 2060?", key: "test-placeholder", model: GeminiClient.defaultModel)
    let body = try #require(request.httpBody)
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let tools = try #require(object["tools"] as? [[String: Any]])
    #expect(tools.first?["googleSearch"] != nil)
    let config = try #require(object["generationConfig"] as? [String: Any])
    #expect(config["responseJsonSchema"] == nil)
    #expect(String(decoding: body, as: UTF8.self).contains("2060"))
}

@Test func groundedAnswersKeepSourcesCitationsAndSuggestions() throws {
    let text = "USF café is in room 101."
    let data = try JSONSerialization.data(withJSONObject: ["candidates": [[
        "finishReason": "STOP", "content": ["parts": [["text": text]]],
        "groundingMetadata": [
            "webSearchQueries": ["USF cafe room"],
            "groundingChunks": [["web": ["uri": "https://www.usf.edu/example", "title": "USF"]]],
            "groundingSupports": [["segment": ["endIndex": text.utf8.count], "groundingChunkIndices": [0]]],
            "searchEntryPoint": ["renderedContent": "<div>Google Search</div>"]
        ]
    ]]])
    let answer = try GeminiClient.webAnswer(data: data, statusCode: 200)
    #expect(answer.text == text + " [1]")
    #expect(answer.sources.first?.url.host == "www.usf.edu")
    #expect(answer.searchSuggestions == "<div>Google Search</div>")
}

@Test func webAnswersRequireSearchEvidenceAndSafeSources() throws {
    let ungrounded = try geminiResponse("A plausible room number without a source")
    #expect(throws: (any Error).self) { try GeminiClient.webAnswer(data: ungrounded, statusCode: 200) }
    for uri in ["javascript:alert(1)", "file:///private/secret", "https://"] {
        let data = try JSONSerialization.data(withJSONObject: ["candidates": [[
            "finishReason": "STOP", "content": ["parts": [["text": "Room 101"]]],
            "groundingMetadata": ["webSearchQueries": ["room"], "groundingChunks": [["web": ["uri": uri]]]]
        ]]])
        #expect(throws: (any Error).self) { try GeminiClient.webAnswer(data: data, statusCode: 200) }
    }
    for status in [403, 429, 500] {
        #expect(throws: (any Error).self) { try GeminiClient.webAnswer(data: Data(), statusCode: status) }
    }
}
