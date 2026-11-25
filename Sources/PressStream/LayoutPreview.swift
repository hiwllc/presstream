import AppKit
import AVFoundation
import SwiftUI

/// Miniatura 16:9 do resultado do modo lateral, com a câmera ao vivo na faixa da direita.
struct LayoutPreview: View {
    let session: AVCaptureSession?
    var side: CameraSide = .right
    var zoom: Double = 1
    var cameraAspect: CGFloat = 16.0 / 9.0

    var body: some View {
        HStack(spacing: 0) {
            if side == .left { cameraStrip }
            ZStack {
                Color.white.opacity(0.06)
                Image(systemName: "pianokeys")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 84)
            if side == .right { cameraStrip }
        }
        .frame(width: 112, height: 63)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
        .animation(.easeOut(duration: 0.2), value: side)
    }

    private var cameraStrip: some View {
        ZStack {
            Color.black
            if let session { CameraPreview(session: session, zoom: zoom, cameraAspect: cameraAspect) }
        }
        .frame(width: 28)
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var zoom: Double = 1
    var cameraAspect: CGFloat = 16.0 / 9.0

    func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.setSession(session)
        view.zoom = CGFloat(zoom)
        view.cameraAspect = cameraAspect
    }

    /// Mesma conta do FrameCompositor: interpola entre "imagem inteira" e "preencher".
    final class PreviewView: NSView {
        private let previewLayer = AVCaptureVideoPreviewLayer()
        var zoom: CGFloat = 1 { didSet { needsLayout = true } }
        var cameraAspect: CGFloat = 16.0 / 9.0 { didSet { needsLayout = true } }

        init(session: AVCaptureSession) {
            super.init(frame: .zero)
            wantsLayer = true
            layer?.masksToBounds = true
            previewLayer.videoGravity = .resizeAspect
            layer?.addSublayer(previewLayer)
            setSession(session)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) não suportado") }

        func setSession(_ session: AVCaptureSession) {
            guard previewLayer.session !== session else { return }
            previewLayer.session = session
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }

        override func layout() {
            super.layout()
            let w = bounds.width, h = bounds.height
            guard w > 0, h > 0, cameraAspect > 0 else { return }
            let fit = min(w / cameraAspect, h)
            let fill = max(w / cameraAspect, h)
            let scale = fit + (fill - fit) * zoom
            let size = CGSize(width: cameraAspect * scale, height: scale)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = CGRect(x: (w - size.width) / 2, y: (h - size.height) / 2,
                                        width: size.width, height: size.height)
            CATransaction.commit()
        }
    }
}
