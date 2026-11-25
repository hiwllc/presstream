import AppKit
@preconcurrency import AVFoundation

enum BubbleError: LocalizedError {
    case noCamera
    case cameraUnavailable

    var errorDescription: String? {
        switch self {
        case .noCamera: return "Nenhuma câmera encontrada."
        case .cameraUnavailable: return "A câmera está em uso por outro app."
        }
    }
}

/// Janela redonda flutuante com o preview da câmera (estilo Loom).
/// Ela entra na gravação como parte da tela: nenhuma composição de vídeo é feita.
@MainActor
final class CameraBubbleController {
    private var panel: NSPanel?
    private var session: AVCaptureSession?
    private var lastOrigin: NSPoint?
    private let sessionQueue = DispatchQueue(label: "app.pressstream.camera")

    var diameter: CGFloat = 200

    /// ID da janela, usado para incluí-la na captura mesmo com o app excluído.
    var windowID: CGWindowID? {
        guard let panel, panel.isVisible else { return nil }
        return CGWindowID(panel.windowNumber)
    }

    func show(deviceUID: String?) throws {
        hide()

        let device = deviceUID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .video)
        guard let device else { throw BubbleError.noCamera }

        let session = AVCaptureSession()
        session.beginConfiguration()
        // Preview pequeno = menos CPU/RAM. A bolinha tem ~200 pt, 640x480 sobra.
        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        } else {
            session.sessionPreset = .medium
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw BubbleError.cameraUnavailable
        }
        session.addInput(input)
        session.commitConfiguration()

        let size = NSSize(width: diameter, height: diameter)
        let origin = lastOrigin ?? defaultOrigin(for: size)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = BubbleView(frame: NSRect(origin: .zero, size: size), session: session)
        panel.orderFrontRegardless()

        self.panel = panel
        self.session = session
        sessionQueue.async { session.startRunning() }
    }

    func hide() {
        if let panel {
            lastOrigin = panel.frame.origin
            panel.orderOut(nil)
        }
        panel = nil
        if let session {
            sessionQueue.async { session.stopRunning() }
        }
        session = nil
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.maxX - size.width - 32, y: visible.minY + 32)
    }
}

private final class BubbleView: NSView {
    private let preview: AVCaptureVideoPreviewLayer

    init(frame: NSRect, session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = frame.width / 2
        layer?.masksToBounds = true
        layer?.borderWidth = 3
        layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor

        preview.videoGravity = .resizeAspectFill
        preview.frame = bounds
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true // espelhado, como um espelho
        }
        layer?.addSublayer(preview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não suportado") }

    override var mouseDownCanMoveWindow: Bool { true }
}
