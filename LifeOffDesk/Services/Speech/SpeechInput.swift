import AVFoundation
import Foundation
import Speech

/// Push-to-talk speech-to-text with Apple's Speech framework, **on-device only**
/// (`requiresOnDeviceRecognition`), so audio never leaves the iPhone and it works in Airplane Mode.
/// If no installed language supports on-device recognition, voice is unavailable; it never falls
/// back to Apple's servers. The transcript only fills the text box; the planner AI still reads it.
@MainActor
final class SpeechInput: ObservableObject {
    enum State: Equatable {
        case idle
        case listening
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    /// Locale actually used, e.g. "English (Philippines)".
    @Published private(set) var languageName: String?

    /// Tried in order; the first with on-device support is used. Filipino first, then Philippine
    /// and US English (Taglish words are helped by `contextualStrings`).
    static let preferredLocales = ["fil-PH", "en-PH", "en-US"]
    static let taglishHints = ["kape", "tahimik", "malapit", "lakad", "lakad lang", "tara", "mamaya", "ngayon",
                               "pasyal", "simbahan", "palengke", "pulis", "ospital", "kain", "merienda", "mura",
                               "libre", "tayo", "muna", "sana", "gusto", "hindi", "lang", "mga", "lakad ko",
                               "Makati", "Muntinlupa", "Alabang", "Ayala", "Salcedo", "Legazpi", "BGC", "Bonifacio",
                               "pickleball", "badminton", "milk tea"]

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onFinish: ((String) -> Void)?

    /// Starts listening (asks for microphone and speech permission the first time).
    func start(onFinish: @escaping (String) -> Void) {
        guard state != .listening else { return }
        self.onFinish = onFinish
        transcript = ""
        Task {
            guard await Self.authorize() else {
                state = .unavailable("Voice needs Microphone and Speech Recognition access (Settings → Life Off Desk).")
                return
            }
            guard let recognizer = Self.onDeviceRecognizer() else {
                state = .unavailable("Voice needs on-device speech recognition for English or Filipino on this iPhone. It is not sent online, so it is off for now. Type instead.")
                return
            }
            do {
                try begin(with: recognizer)
            } catch {
                finishAudio()
                state = .unavailable("Voice could not start: \(error.localizedDescription)")
            }
        }
    }

    /// Stops listening and hands the transcript to the caller.
    func stop() {
        guard state == .listening else { return }
        request?.endAudio()
        finishAudio()
        state = .idle
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let finish = onFinish
        onFinish = nil
        if !text.isEmpty { finish?(text) }
    }

    func cancel() {
        task?.cancel()
        finishAudio()
        onFinish = nil
        if state == .listening { state = .idle }
    }

    private func begin(with recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true // never Apple's servers
        request.shouldReportPartialResults = true
        request.contextualStrings = Self.taglishHints
        request.taskHint = .search
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        Self.installTap(on: input, format: format, request: request)
        engine.prepare()
        try engine.start()
        languageName = Locale.current.localizedString(forIdentifier: recognizer.locale.identifier)
        state = .listening

        task = Self.recognize(recognizer, request: request) { [weak self] text, isFinal, error in
            guard let self else { return }
            if let text { self.transcript = text }
            if isFinal {
                self.stop()
            } else if let error, self.state == .listening {
                // Silence or an interrupted session ends the request; keep what was heard.
                if self.transcript.isEmpty {
                    self.finishAudio()
                    self.state = .unavailable("Voice stopped: \(error)")
                } else {
                    self.stop()
                }
            }
        }
    }

    // Callbacks run on audio/recognition threads: build them outside the main actor and hop back.
    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat,
                                               request: SFSpeechAudioBufferRecognitionRequest) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
    }

    nonisolated private static func recognize(_ recognizer: SFSpeechRecognizer,
                                              request: SFSpeechAudioBufferRecognitionRequest,
                                              update: @escaping @MainActor (String?, Bool, String?) -> Void)
        -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let message = error?.localizedDescription
            Task { @MainActor in update(text, isFinal, message) }
        }
    }

    private func finishAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func onDeviceRecognizer() -> SFSpeechRecognizer? {
        for id in preferredLocales {
            if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: id)),
               recognizer.supportsOnDeviceRecognition, recognizer.isAvailable {
                return recognizer
            }
        }
        return nil
    }

    nonisolated private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
