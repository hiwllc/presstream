import AVFoundation
import CoreMedia
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case alreadyRunning
    case notRunning
    case noFrames
    case writerSetupFailed
    case audioDeviceNotFound
    case audioDeviceUnavailable
    case displayNotFound
    case windowNotFound

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "Já existe uma gravação em andamento."
        case .notRunning: return "Nenhuma gravação em andamento."
        case .noFrames: return "Nenhum quadro foi capturado — verifique a permissão de Gravação de Tela."
        case .writerSetupFailed: return "Não foi possível preparar o arquivo de vídeo."
        case .audioDeviceNotFound: return "A entrada de áudio escolhida não foi encontrada."
        case .audioDeviceUnavailable: return "A entrada de áudio escolhida está em uso ou indisponível."
        case .displayNotFound: return "A tela escolhida não foi encontrada."
        case .windowNotFound: return "A janela escolhida foi fechada ou minimizada. Atualize a lista."
        }
    }
}

enum CaptureSource {
    /// Tela inteira, excluindo apps (o próprio PressStream) mas mantendo janelas (a bolinha).
    case display(SCDisplay, [SCRunningApplication], [SCWindow])
    /// Uma janela só (ex.: Ableton), independente do que está por cima dela.
    case window(SCWindow)
}

/// Pipeline:
/// - Modo normal ("zero-copy"): ScreenCaptureKit entrega YUV já redimensionado na GPU
///   → AVAssetWriter codifica no hardware.
/// - Modo câmera lateral: um timer na taxa de fps junta o último frame da tela + câmera
///   na GPU (FrameCompositor) e manda pro encoder. Assim a câmera continua viva mesmo
///   quando a tela está parada.
/// Vídeo, áudio e composição rodam na mesma fila serial: sem locks.
final class CaptureSession: NSObject {
    let mixer = AudioMixer()
    let framing = CameraFraming()
    private let sampleQueue = DispatchQueue(label: "app.pressstream.samples", qos: .userInitiated)
    private var stream: SCStream?
    private var writer: MovieWriter?
    private var audioInputs: [AudioInputCapture] = []

    // Modo lateral (acessados só na sampleQueue depois do start)
    private var compositor: FrameCompositor?
    private var cameraFeed: CameraFeed?
    private var latestScreen: CVPixelBuffer?
    private var screenIsNew = false
    private var lastCameraFrame: CVPixelBuffer?
    private var ticker: DispatchSourceTimer?

    /// Chamado (fora da main thread) se o sistema interromper a captura.
    var onError: ((Error) -> Void)?

    func start(source: CaptureSource,
               layout: CanvasLayout,
               settings: RecordingSettings,
               camera: CameraFeed?,
               url: URL) async throws {
        guard stream == nil else { throw CaptureError.alreadyRunning }

        let writer = try MovieWriter(url: url,
                                     width: Int(layout.canvas.width),
                                     height: Int(layout.canvas.height),
                                     settings: settings,
                                     audioTracks: settings.audioTracks)
        let compositor = layout.camera != nil ? try FrameCompositor(layout: layout, framing: framing) : nil

        let config = SCStreamConfiguration()
        config.width = Int(layout.content.width)
        config.height = Int(layout.content.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.fps))
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange // formato nativo do encoder
        config.queueDepth = 4                                               // poucos frames na RAM
        config.showsCursor = settings.showsCursor
        config.capturesAudio = settings.captureSystemAudio
        config.sampleRate = 48_000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true

        let filter: SCContentFilter
        switch source {
        case let .display(display, apps, windows):
            filter = SCContentFilter(display: display, excludingApplications: apps, exceptingWindows: windows)
        case let .window(window):
            filter = SCContentFilter(desktopIndependentWindow: window)
            if #available(macOS 14.0, *) {
                // Se a janela mudar de tamanho durante a gravação, continua encaixada.
                config.scalesToFit = true
                config.preservesAspectRatio = true
            }
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if settings.captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        }

        // Uma sessão de captura por entrada (música e microfone são independentes).
        var inputs: [AudioInputCapture] = []
        for (uid, track) in [(settings.musicUID, AudioTrack.music), (settings.micUID, AudioTrack.mic)] {
            guard let uid else { continue }
            inputs.append(try AudioInputCapture(deviceUID: uid, queue: sampleQueue) { [weak self] buffer in
                guard let self else { return }
                self.mixer.process(buffer, track: track)
                self.writer?.appendAudio(buffer, to: track)
            })
        }

        self.writer = writer
        self.stream = stream
        self.audioInputs = inputs
        self.compositor = compositor
        self.cameraFeed = camera
        self.latestScreen = nil

        inputs.forEach { $0.start() }
        do {
            try await stream.startCapture()
        } catch {
            inputs.forEach { $0.stop() }
            writer.cancel(on: sampleQueue)
            self.stream = nil
            self.audioInputs = []
            sampleQueue.async { self.resetQueueState() }
            throw error
        }

        if compositor != nil {
            startTicker(fps: settings.fps)
        }
    }

    /// Para a captura, finaliza o arquivo e devolve a URL gravada.
    func stop() async throws -> URL {
        guard let stream, let writer else { throw CaptureError.notRunning }
        ticker?.cancel()
        ticker = nil
        try? await stream.stopCapture()
        audioInputs.forEach { $0.stop() }
        self.stream = nil
        self.audioInputs = []

        defer { sampleQueue.async { self.resetQueueState() } }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finish(on: sampleQueue) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        return writer.url
    }

    // MARK: - Composição (modo lateral)

    private func startTicker(fps: Int) {
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: sampleQueue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / max(fps, 1)),
                       leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.composeFrame() }
        timer.resume()
        ticker = timer
    }

    private func composeFrame() {
        guard let writer, let compositor, let screen = latestScreen else { return }
        let camera = cameraFeed?.latestFrame
        // Só gasta GPU quando a tela ou a câmera mudou desde o último quadro.
        guard screenIsNew || camera !== lastCameraFrame else { return }
        screenIsNew = false
        lastCameraFrame = camera

        let now = CMClockGetTime(CMClockGetHostTimeClock()) // mesmo relógio do áudio
        guard let frame = compositor.compose(screen: screen, camera: camera) else { return }
        writer.appendPixelBuffer(frame, at: now)
    }

    private func resetQueueState() {
        writer = nil
        compositor = nil
        cameraFeed = nil
        latestScreen = nil
        lastCameraFrame = nil
        screenIsNew = false
    }

    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else { return false }
        return status == .complete
    }
}

extension CaptureSession: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, let writer else { return }
        switch type {
        case .screen:
            // Tela parada = frames "idle" sem imagem nova; só os completos interessam.
            guard Self.isCompleteFrame(sampleBuffer) else { return }
            if compositor != nil {
                latestScreen = CMSampleBufferGetImageBuffer(sampleBuffer)
                screenIsNew = true
            } else {
                writer.appendVideo(sampleBuffer)
            }
        case .audio:
            mixer.process(sampleBuffer, track: .system)
            writer.appendAudio(sampleBuffer, to: .system)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error)
    }
}
