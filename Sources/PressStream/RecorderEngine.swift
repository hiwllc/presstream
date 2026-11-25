import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

enum SourceKind: String, CaseIterable, Identifiable {
    case display = "Tela inteira"
    case window = "Janela"
    var id: String { rawValue }
}

enum CameraMode: String, CaseIterable, Identifiable {
    case off = "Desligada"
    case bubble = "Bolinha"
    case side = "Lateral"
    var id: String { rawValue }
}

@MainActor
final class RecorderEngine: ObservableObject {
    enum Phase: Equatable { case idle, starting, recording, stopping }

    // Estado
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var screenPermissionMissing = false
    @Published var errorMessage: String?

    // Fonte
    @Published var sourceKind: SourceKind = .display {
        didSet { if sourceKind == .window && oldValue != .window { Task { await refreshWindows() } } }
    }
    @Published private(set) var displays: [DisplayOption] = []
    @Published var selectedDisplayID: CGDirectDisplayID?
    @Published private(set) var windows: [WindowOption] = []
    @Published var selectedWindowID: CGWindowID?

    // Áudio: música (controladora / device virtual), microfone e som do Mac, cada um na sua faixa
    @Published private(set) var audioDevices: [DeviceOption] = []
    @Published var selectedMusicUID: String? { didSet { defaults.set(selectedMusicUID, forKey: "musicUID") } }
    @Published var selectedMicUID: String? { didSet { defaults.set(selectedMicUID, forKey: "micUID") } }
    @Published var captureSystemAudio = true
    @Published var musicGain: Double = 1 { didSet { gainChanged(.music, musicGain) } }
    @Published var micGain: Double = 1 { didSet { gainChanged(.mic, micGain) } }
    @Published var systemGain: Double = 1 { didSet { gainChanged(.system, systemGain) } }
    @Published private(set) var levels: [AudioTrack: Float] = [:]

    // Câmera
    @Published private(set) var cameras: [DeviceOption] = []
    @Published private(set) var cameraFeed: CameraFeed?
    @Published var cameraMode: CameraMode = .off {
        didSet { if cameraMode != oldValue { Task { await updateCamera() } } }
    }
    @Published var selectedCameraUID: String? {
        didSet { if cameraMode != .off && selectedCameraUID != oldValue { Task { await updateCamera() } } }
    }

    @Published var canvasShape: CanvasShape = .fitSource
    @Published var cameraZoom: Double = 0.4 {
        didSet {
            capture.framing.zoom = cameraZoom
            defaults.set(cameraZoom, forKey: "cameraZoom")
        }
    }
    @Published var cameraSide: CameraSide = .right {
        didSet { defaults.set(cameraSide.rawValue, forKey: "cameraSide") }
    }

    // Qualidade
    @Published var resolution: OutputResolution = .p1080
    @Published var fps = 60
    @Published var codec: VideoCodec = .h264

    let outputDirectory: URL
    private let capture: CaptureSession
    private let bubble: CameraBubbleController
    private var timer: Timer?
    private var startDate: Date?
    private var observers: [NSObjectProtocol] = []
    private let defaults = UserDefaults.standard

    init() {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies")
        outputDirectory = movies.appendingPathComponent("PressStream", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        capture = CaptureSession()
        bubble = CameraBubbleController()

        musicGain = defaults.object(forKey: "gain.music") as? Double ?? 1
        micGain = defaults.object(forKey: "gain.mic") as? Double ?? 1
        systemGain = defaults.object(forKey: "gain.system") as? Double ?? 1
        selectedMusicUID = defaults.string(forKey: "musicUID")
        selectedMicUID = defaults.string(forKey: "micUID")
        cameraSide = CameraSide(rawValue: defaults.string(forKey: "cameraSide") ?? "") ?? .right
        cameraZoom = defaults.object(forKey: "cameraZoom") as? Double ?? 0.4
        capture.framing.zoom = cameraZoom
        capture.mixer.setGain(Float(musicGain), for: .music)
        capture.mixer.setGain(Float(micGain), for: .mic)
        capture.mixer.setGain(Float(systemGain), for: .system)

        capture.onError = { [weak self] error in
            Task { @MainActor in await self?.handleStreamFailure(error) }
        }

        for name in [NSNotification.Name.AVCaptureDeviceWasConnected, .AVCaptureDeviceWasDisconnected] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshDevices() }
            })
        }
    }

    // MARK: - Estado derivado

    var isBusy: Bool { phase != .idle }

    /// Na gravação de janela, a bolinha (que é outra janela) não entra no vídeo.
    var bubbleHiddenInWindowMode: Bool { sourceKind == .window && cameraMode == .bubble }

    var currentSettings: RecordingSettings {
        RecordingSettings(resolution: resolution, fps: fps, codec: codec,
                          captureSystemAudio: captureSystemAudio,
                          micUID: selectedMicUID, musicUID: selectedMusicUID, showsCursor: true)
    }

    var bitrateLabel: String {
        let format = cameraMode == .side
            ? (canvasShape == .widescreen ? "16:9 com câmera" : "fonte + câmera")
            : "tamanho da fonte"
        return String(format: "≈ %.0f Mbps · %@ · %@",
                      Double(currentSettings.videoBitrate) / 1_000_000, codec.rawValue, format)
    }

    // MARK: - Setup

    func bootstrap() async {
        refreshDevices()
        await refreshDisplays()
    }

    func refreshDisplays() async {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            screenPermissionMissing = false
            displays = content.displays.map { DisplayOption(id: $0.displayID, name: DeviceCatalog.displayName($0)) }
            if !displays.contains(where: { $0.id == selectedDisplayID }) {
                selectedDisplayID = displays.first?.id
            }
            updateWindows(from: content)
        } catch {
            screenPermissionMissing = true
        }
    }

    func refreshWindows() async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        else { return }
        updateWindows(from: content)
    }

    private func updateWindows(from content: SCShareableContent) {
        let pid = ProcessInfo.processInfo.processIdentifier
        windows = DeviceCatalog.recordableWindows(in: content, excludingPID: pid)
            .map { WindowOption(id: $0.windowID, name: DeviceCatalog.windowName($0)) }
        if !windows.contains(where: { $0.id == selectedWindowID }) {
            // Prefere Ableton / Rekordbox se estiverem abertos.
            selectedWindowID = windows.first(where: {
                $0.name.localizedCaseInsensitiveContains("ableton") || $0.name.localizedCaseInsensitiveContains("rekordbox")
            })?.id ?? windows.first?.id
        }
    }

    func refreshDevices() {
        audioDevices = DeviceCatalog.audioInputs()
        cameras = DeviceCatalog.cameras()
        // Se o device sumiu (desconectado), volta para "Nenhuma".
        if let uid = selectedMusicUID, !audioDevices.contains(where: { $0.id == uid }) {
            selectedMusicUID = nil
        }
        if let uid = selectedMicUID, !audioDevices.contains(where: { $0.id == uid }) {
            selectedMicUID = nil
        }
        if selectedCameraUID.map({ uid in cameras.contains { $0.id == uid } }) != true {
            selectedCameraUID = cameras.first?.id
        }
    }

    // MARK: - Gravação

    func toggleRecording() {
        switch phase {
        case .idle: Task { await start() }
        case .recording: Task { await stop() }
        default: break
        }
    }

    func start() async {
        guard phase == .idle else { return }
        errorMessage = nil
        phase = .starting

        if selectedMicUID != nil || selectedMusicUID != nil, !(await Self.requestAccess(.audio)) {
            errorMessage = "Sem permissão de microfone. Libere em Ajustes → Privacidade → Microfone."
            phase = .idle
            return
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let settings = currentSettings
            let source: CaptureSource
            let sourcePixels: CGSize

            switch sourceKind {
            case .display:
                guard let id = selectedDisplayID,
                      let display = content.displays.first(where: { $0.displayID == id }) else {
                    throw CaptureError.displayNotFound
                }
                // Esconde o painel do PressStream do vídeo, mas mantém a bolinha da câmera.
                let pid = ProcessInfo.processInfo.processIdentifier
                let ownApps = content.applications.filter { $0.processID == pid }
                let bubbleID = cameraMode == .bubble ? bubble.windowID : nil
                let exceptions = content.windows.filter { bubbleID != nil && $0.windowID == bubbleID! }
                let scale = DeviceCatalog.screen(for: id)?.backingScaleFactor ?? 2
                source = .display(display, ownApps, exceptions)
                sourcePixels = CGSize(width: CGFloat(display.width) * scale, height: CGFloat(display.height) * scale)

            case .window:
                guard let id = selectedWindowID,
                      let window = content.windows.first(where: { $0.windowID == id }) else {
                    throw CaptureError.windowNotFound
                }
                let scale = DeviceCatalog.maxBackingScale
                source = .window(window)
                sourcePixels = CGSize(width: window.frame.width * scale, height: window.frame.height * scale)
            }

            let sideCamera = cameraMode == .side
            let layout = settings.layout(sourcePixels: sourcePixels, sideCamera: sideCamera,
                                         shape: canvasShape, side: cameraSide)
            let url = outputDirectory.appendingPathComponent(Self.fileName())

            try await capture.start(source: source, layout: layout, settings: settings,
                                    camera: sideCamera ? cameraFeed : nil, url: url)
            startDate = Date()
            elapsed = 0
            phase = .recording
            startTimer()
        } catch {
            errorMessage = "Não foi possível iniciar: \(error.localizedDescription)"
            phase = .idle
        }
    }

    func stop() async {
        guard phase == .recording else { return }
        phase = .stopping
        stopTimer()
        do {
            lastRecordingURL = try await capture.stop()
        } catch {
            errorMessage = "Erro ao salvar: \(error.localizedDescription)"
        }
        levels = [:]
        phase = .idle
    }

    private func handleStreamFailure(_ error: Error) async {
        guard phase == .recording else { return }
        await stop()
        errorMessage = "A captura foi interrompida: \(error.localizedDescription)"
    }

    // MARK: - Áudio

    private func gainChanged(_ track: AudioTrack, _ gain: Double) {
        capture.mixer.setGain(Float(gain), for: track)
        defaults.set(gain, forKey: "gain.\(track.rawValue)")
    }

    // MARK: - Câmera

    private func updateCamera() async {
        bubble.hide()
        cameraFeed?.stop()
        cameraFeed = nil
        guard cameraMode != .off else { return }

        guard await Self.requestAccess(.video) else {
            errorMessage = "Sem permissão de câmera. Libere em Ajustes → Privacidade → Câmera."
            cameraMode = .off
            return
        }
        do {
            switch cameraMode {
            case .bubble:
                try bubble.show(deviceUID: selectedCameraUID)
            case .side:
                let feed = try CameraFeed(deviceUID: selectedCameraUID)
                feed.start()
                cameraFeed = feed
            case .off:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
            cameraMode = .off
        }
    }

    // MARK: - Atalhos

    func openOutputFolder() { NSWorkspace.shared.open(outputDirectory) }

    func revealLastRecording() {
        guard let url = lastRecordingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helpers

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        if let start = startDate { elapsed = Date().timeIntervalSince(start) }
        // Medidor com queda suave (o pico sobe na hora e desce aos poucos).
        let peaks = capture.mixer.takePeaks()
        var next: [AudioTrack: Float] = [:]
        for track in AudioTrack.allCases {
            next[track] = max(peaks[track] ?? 0, (levels[track] ?? 0) * 0.82)
        }
        levels = next
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private static func requestAccess(_ type: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: type)
        default: return false
        }
    }

    private static func fileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "PressStream \(formatter.string(from: Date())).mov"
    }
}
