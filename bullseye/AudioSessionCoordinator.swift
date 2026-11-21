import AVFoundation

// Session activation may block while hardware starts. Keep it off the UI actor,
// and serialize microphone/narration category changes on one actor.
actor AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()
    func activate(recording: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if recording {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        } else {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        }
        try session.setActive(true)
    }
    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
