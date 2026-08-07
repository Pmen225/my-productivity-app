import AVFoundation
import Foundation
import Observation
import Speech
import SwiftUI

/// Voice-to-text for quick capture and the assistant.
///
/// Entirely optional: when permission is missing or recognition is unavailable,
/// the microphone affordance hides itself and typing continues to work.
@Observable
@MainActor
public final class SpeechService {
    public enum Authorisation: Equatable, Sendable {
        case notDetermined
        case denied
        case restricted
        case authorised

        public var canRecord: Bool { self == .authorised }

        public var explanation: String {
            switch self {
            case .notDetermined: "Flowmap has not asked to use speech recognition yet."
            case .denied: "Speech recognition is off. Turn it on in System Settings to dictate."
            case .restricted: "Speech recognition is restricted on this device."
            case .authorised: "Flowmap can turn your speech into text."
            }
        }
    }

    public private(set) var authorisation: Authorisation = .notDetermined
    public private(set) var isRecording = false
    public private(set) var transcript = ""
    public private(set) var lastError: String?

    private let recogniser = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    public init() {
        refreshAuthorisation()
    }

    /// Whether dictation is worth offering at all on this device.
    public var isAvailable: Bool {
        recogniser?.isAvailable == true && authorisation != .restricted
    }

    public func refreshAuthorisation() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: authorisation = .authorised
        case .denied: authorisation = .denied
        case .restricted: authorisation = .restricted
        case .notDetermined: authorisation = .notDetermined
        @unknown default: authorisation = .notDetermined
        }
    }

    /// Asks for permission in context — the first time the user taps the mic.
    @discardableResult
    public func requestAuthorisation() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        authorisation = switch status {
        case .authorized: .authorised
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
        return authorisation.canRecord
    }

    /// Starts listening, calling `onUpdate` with the transcript so far.
    public func start(onUpdate: @escaping (String) -> Void) async {
        guard !isRecording else { return }

        if !authorisation.canRecord {
            guard await requestAuthorisation() else {
                lastError = authorisation.explanation
                return
            }
        }

        guard let recogniser, recogniser.isAvailable else {
            lastError = "Speech recognition isn't available right now."
            return
        }

        #if os(iOS)
        // Recording needs the session configured before the engine starts.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            lastError = "The microphone could not be started."
            return
        }
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keeping audio on-device where possible is the private default.
        request.requiresOnDeviceRecognition = recogniser.supportsOnDeviceRecognition
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            lastError = "No microphone input is available."
            cleanUp()
            return
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            lastError = "The microphone could not be started."
            cleanUp()
            return
        }

        isRecording = true
        transcript = ""

        task = recogniser.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    onUpdate(self.transcript)
                    if result.isFinal { self.stop() }
                }
                if error != nil {
                    // A recognition error is not worth an alert; it just ends dictation.
                    self.stop()
                }
            }
        }
    }

    public func stop() {
        guard isRecording else { return }
        cleanUp()
    }

    public func toggle(onUpdate: @escaping (String) -> Void) {
        if isRecording {
            stop()
        } else {
            Task { await start(onUpdate: onUpdate) }
        }
    }

    private func cleanUp() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

/// The microphone affordance. Hides itself when dictation isn't available, so
/// the surrounding layout never carries a dead control.
public struct DictationButton: View {
    @Environment(\.colorScheme) private var scheme
    @State private var speech = SpeechService()

    private let onTranscript: (String) -> Void
    private let onRecordingChange: ((Bool) -> Void)?

    public init(onTranscript: @escaping (String) -> Void, onRecordingChange: ((Bool) -> Void)? = nil) {
        self.onTranscript = onTranscript
        self.onRecordingChange = onRecordingChange
    }

    public var body: some View {
        if speech.isAvailable {
            Button {
                speech.toggle(onUpdate: onTranscript)
            } label: {
                Image(systemName: speech.isRecording ? "mic.fill" : "mic")
                    .foregroundStyle(
                        speech.isRecording ? FlowTheme.accent : FlowTheme.secondaryText(scheme)
                    )
                    .symbolEffect(.pulse, isActive: speech.isRecording)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(speech.isRecording ? "Stop dictation" : "Dictate")
            .help(speech.isRecording ? "Stop dictation" : "Dictate")
            .onChange(of: speech.isRecording) { _, newValue in
                onRecordingChange?(newValue)
            }
        }
    }
}
