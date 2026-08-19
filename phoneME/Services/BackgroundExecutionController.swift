import Combine
import Foundation

#if os(iOS)
import AVFoundation
import OSLog

private let backgroundExecutionLogger = Logger(
    subsystem: "dev.phoneme.emulator",
    category: "BackgroundExecution"
)

@MainActor
final class BackgroundExecutionController: NSObject, ObservableObject {
    static let preferenceKey = "keepJ2MERunningInBackground"

    enum ApplicationPhase: String {
        case active
        case inactive
        case background
    }

    enum Status: Equatable {
        case disabled
        case waitingForApplication
        case readyForBackground
        case active
        case failed(String)

        var description: String {
            switch self {
            case .disabled:
                return L10n.string("Disabled")
            case .waitingForApplication:
                return L10n.string("Starts when a J2ME application is running")
            case .readyForBackground:
                return L10n.string("Ready for background use")
            case .active:
                return L10n.string("Background execution is active")
            case .failed(let message):
                return message
            }
        }

        // Kept for the Settings view contract. The audio keeper does not need
        // a privacy permission or a trip to the system Settings application.
        var requiresSystemSettings: Bool { false }
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var status: Status
    @Published private(set) var isKeepingAlive = false

    private var runningApplicationCount = 0
    private var applicationPhase: ApplicationPhase = .active
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayerNode?
    private var keepAliveBuffer: AVAudioPCMBuffer?

    override init() {
        let defaults = UserDefaults.standard
        let storedValue = defaults.object(
            forKey: Self.preferenceKey
        ) as? Bool
        // This build is specifically intended to preserve active games while
        // the screen is locked or the app is hidden. Existing explicit user
        // choices still win, while fresh installs enable the feature by
        // default and only start audio after a J2ME application is running.
        let enabled = storedValue ?? true
        isEnabled = enabled
        status = enabled ? .waitingForApplication : .disabled
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionNeedsReevaluation(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionNeedsReevaluation(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else {
            reevaluate()
            return
        }

        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.preferenceKey)
        reevaluate()
    }

    func setRunningApplicationCount(_ count: Int) {
        runningApplicationCount = max(0, count)
        reevaluate()
    }

    func setApplicationPhase(_ phase: ApplicationPhase) {
        applicationPhase = phase
        reevaluate()
    }

    func openSystemSettings() {
        // No permission is required by the audio-based background keeper.
    }

    private func reevaluate() {
        guard isEnabled else {
            stopAudioKeeper(status: .disabled)
            return
        }

        guard runningApplicationCount > 0 else {
            stopAudioKeeper(status: .waitingForApplication)
            return
        }

        startAudioKeeperIfNeeded()
        if isKeepingAlive {
            status = applicationPhase == .active
                ? .readyForBackground
                : .active
        }
    }

    private func startAudioKeeperIfNeeded() {
        if let audioEngine,
           audioEngine.isRunning,
           audioPlayer?.isPlaying == true {
            isKeepingAlive = true
            return
        }

        stopAudioKeeper(status: status)
        phoneme_ios_set_background_audio_keeper_active(1)

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try session.setActive(true)

            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: 8_000,
                channels: 1
            ) else {
                throw BackgroundExecutionError.audioFormatUnavailable
            }

            let frameCount = AVAudioFrameCount(8_000)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            ), let samples = buffer.floatChannelData?[0] else {
                throw BackgroundExecutionError.audioBufferUnavailable
            }
            buffer.frameLength = frameCount

            // Keep the render graph genuinely active without producing an
            // audible signal. The alternating sample is about -140 dBFS and
            // is reduced again by the player volume below.
            for index in 0..<Int(frameCount) {
                samples[index] = index.isMultiple(of: 2) ? 0.000_000_1 : -0.000_000_1
            }

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            player.volume = 0.01
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            player.scheduleBuffer(buffer, at: nil, options: [.loops])
            engine.prepare()
            try engine.start()
            player.play()

            audioEngine = engine
            audioPlayer = player
            keepAliveBuffer = buffer
            isKeepingAlive = true
            backgroundExecutionLogger.info(
                "Background audio keeper started for \(self.runningApplicationCount) J2ME application(s)"
            )
        } catch {
            stopAudioKeeper(
                status: .failed(
                    String(
                        format: L10n.string("Could not start background execution: %@"),
                        error.localizedDescription
                    )
                )
            )
            backgroundExecutionLogger.error(
                "Background audio keeper failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func stopAudioKeeper(status: Status) {
        phoneme_ios_set_background_audio_keeper_active(0)
        audioPlayer?.stop()
        audioEngine?.stop()
        audioEngine?.reset()
        audioPlayer = nil
        audioEngine = nil
        keepAliveBuffer = nil

        if isKeepingAlive {
            backgroundExecutionLogger.info(
                "Background audio keeper stopped"
            )
        }
        isKeepingAlive = false
        self.status = status

        // Intentionally do not deactivate AVAudioSession here. A running game
        // may own active MMAPI audio through the same playback session.
    }

    @objc nonisolated private func handleAudioSessionNeedsReevaluation(
        _ notification: Notification
    ) {
        Task { @MainActor [weak self] in
            self?.reevaluate()
        }
    }

    @objc nonisolated private func handleAudioSessionInterruption(
        _ notification: Notification
    ) {
        guard let rawValue = notification.userInfo?[
            AVAudioSessionInterruptionTypeKey
        ] as? UInt else {
            return
        }

        Task { @MainActor [weak self] in
            guard
                let self,
                let interruption = AVAudioSession.InterruptionType(
                    rawValue: rawValue
                )
            else {
                return
            }
            switch interruption {
            case .began:
                self.stopAudioKeeper(
                    status: .failed(
                        L10n.string("Background audio was interrupted")
                    )
                )
            case .ended:
                self.reevaluate()
            @unknown default:
                self.reevaluate()
            }
        }
    }
}

private enum BackgroundExecutionError: LocalizedError {
    case audioFormatUnavailable
    case audioBufferUnavailable

    var errorDescription: String? {
        switch self {
        case .audioFormatUnavailable:
            return "Background audio format is unavailable"
        case .audioBufferUnavailable:
            return "Background audio buffer is unavailable"
        }
    }
}

#else

@MainActor
final class BackgroundExecutionController: ObservableObject {
    static let preferenceKey = "keepJ2MERunningInBackground"

    enum ApplicationPhase {
        case active
        case inactive
        case background
    }

    enum Status: Equatable {
        case disabled

        var description: String { L10n.string("Unavailable") }
        var requiresSystemSettings: Bool { false }
    }

    @Published private(set) var isEnabled = false
    @Published private(set) var status: Status = .disabled
    @Published private(set) var isKeepingAlive = false

    func setEnabled(_ enabled: Bool) {}
    func setRunningApplicationCount(_ count: Int) {}
    func setApplicationPhase(_ phase: ApplicationPhase) {}
    func openSystemSettings() {}
}

#endif
