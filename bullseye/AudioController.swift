import Foundation
import Observation
import AVFoundation
import Speech
import UIKit

@MainActor @Observable final class AudioController {
    var recording = false
    var preparing = false
    var transcript = ""
    var message: String?
    private let speaker = AVSpeechSynthesizer()
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    private var engine: AVAudioEngine {
        if let audioEngine { return audioEngine }
        let value = AVAudioEngine()
        audioEngine = value
        return value
    }
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var installedTap = false
    private var generation = 0

    func speak(_ text: String) {
        stopRecording()
        speaker.stopSpeaking(at: .immediate)
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
            return
        }
        let token = generation
        Task {
            do {
                try await AudioSessionCoordinator.shared.activate(recording: false)
                guard token == generation else { return }
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                utterance.rate = 0.47
                speaker.speak(utterance)
            } catch { message = "Audio is unavailable. Read the instruction on screen." }
        }
    }
    func stop() {
        stopRecording()
        speaker.stopSpeaking(at: .immediate)
        Task { await AudioSessionCoordinator.shared.deactivate() }
    }
    func startRecording() async {
        guard !recording, !preparing else { return }
        preparing = true
        generation += 1
        let token = generation
        defer { preparing = false }
        speaker.stopSpeaking(at: .immediate)
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard token == generation else { return }
        guard speech && microphone else { message = "Microphone or speech permission denied. Type your search, or enable access in Settings."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            message = "Speech recognition is unavailable. Type your search."; return
        }
        do {
            try await AudioSessionCoordinator.shared.activate(recording: true)
            guard token == generation else { return }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            transcript = ""
            message = nil
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw DataIssue.message("No microphone input.") }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            installedTap = true
            engine.prepare()
            try engine.start()
            recording = true
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                let failed = error != nil
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if let text { self.transcript = text }
                    if final || failed {
                        self.stopRecording()
                        if failed && self.transcript.isEmpty { self.message = "Couldn’t hear a search. Try again or type it." }
                    }
                }
            }
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                if !Task.isCancelled { self?.stopRecording() }
            }
        } catch {
            stopRecording()
            message = "Couldn’t start the microphone. Typed search is available."
        }
    }
    func stopRecording() {
        generation += 1
        timeout?.cancel()
        audioEngine?.stop()
        if installedTap { audioEngine?.inputNode.removeTap(onBus: 0); installedTap = false }
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        request = nil
        recording = false
    }
}
