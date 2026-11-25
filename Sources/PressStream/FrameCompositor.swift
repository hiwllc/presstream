import CoreImage
import CoreVideo
import Metal

/// Monta o quadro final do modo lateral na GPU (Core Image + Metal):
/// tela/janela à esquerda (3/4) e câmera espelhada à direita (1/4).
final class FrameCompositor {
    private let layout: CanvasLayout
    private let framing: CameraFraming
    private let context: CIContext
    private let background: CIImage
    private let cameraPlaceholder: CIImage
    private var pool: CVPixelBufferPool?

    init(layout: CanvasLayout, framing: CameraFraming) throws {
        self.layout = layout
        self.framing = framing
        if let device = MTLCreateSystemDefaultDevice() {
            // Prioridade baixa na GPU: o Rekordbox/Ableton desenham primeiro.
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false,
                                                             .priorityRequestLow: true])
        } else {
            context = CIContext(options: [.cacheIntermediates: false])
        }

        let canvasRect = CGRect(origin: .zero, size: layout.canvas)
        background = CIImage(color: CIColor(red: 0.04, green: 0.04, blue: 0.05)).cropped(to: canvasRect)
        cameraPlaceholder = CIImage(color: CIColor(red: 0.09, green: 0.09, blue: 0.11))
            .cropped(to: layout.camera ?? .zero)

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(layout.canvas.width),
            kCVPixelBufferHeightKey as String: Int(layout.canvas.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let poolAttributes: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3]
        CVPixelBufferPoolCreate(nil, poolAttributes as CFDictionary, attributes as CFDictionary, &pool)
        guard pool != nil else { throw CaptureError.writerSetupFailed }
    }

    func compose(screen: CVPixelBuffer, camera: CVPixelBuffer?) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var output: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess,
              let output else { return nil }

        // Tela: o ScreenCaptureKit já entrega no tamanho certo; aqui só posiciona.
        let screenImage = CIImage(cvPixelBuffer: screen)
        let content = layout.content
        let sx = content.width / max(screenImage.extent.width, 1)
        let sy = content.height / max(screenImage.extent.height, 1)
        var frame = screenImage
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: content.minX, y: content.minY))
            .composited(over: background)

        if let strip = layout.camera {
            if let camera {
                frame = cameraLayer(camera, in: strip, zoom: CGFloat(framing.zoom)).composited(over: frame)
            } else {
                frame = cameraPlaceholder.composited(over: frame)
            }
        }

        context.render(frame, to: output, bounds: CGRect(origin: .zero, size: layout.canvas),
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return output
    }

    // MARK: - Câmera

    /// Câmera espelhada na faixa. Com zoom < 1 a imagem não preenche a faixa e o espaço
    /// que sobra recebe a própria câmera desfocada e escurecida (calculada em 1/8 da
    /// resolução, então o desfoque custa quase nada).
    private func cameraLayer(_ buffer: CVPixelBuffer, in strip: CGRect, zoom: CGFloat) -> CIImage {
        let camera = CIImage(cvPixelBuffer: buffer)
        let w = max(camera.extent.width, 1)
        let h = max(camera.extent.height, 1)
        let fill = max(strip.width / w, strip.height / h)
        let fit = min(strip.width / w, strip.height / h)
        let scale = fit + (fill - fit) * zoom

        let foreground = Self.center(Self.mirrored(camera, scale: scale), in: strip)
        guard scale < fill - 0.001 else { return foreground.cropped(to: strip) }

        let factor: CGFloat = 8
        var small = Self.mirrored(camera, scale: fill / factor)
        small = small.transformed(by: CGAffineTransform(translationX: -small.extent.minX, y: -small.extent.minY))
        let blurred = small
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 3)
            .cropped(to: small.extent)
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -1.2])
        let background = Self.center(blurred.transformed(by: CGAffineTransform(scaleX: factor, y: factor)),
                                     in: strip)

        return foreground.composited(over: background).cropped(to: strip)
    }

    private static func mirrored(_ image: CIImage, scale: CGFloat) -> CIImage {
        image.transformed(by: CGAffineTransform(scaleX: -scale, y: scale))
    }

    private static func center(_ image: CIImage, in rect: CGRect) -> CIImage {
        let e = image.extent
        return image.transformed(by: CGAffineTransform(translationX: rect.midX - e.midX, y: rect.midY - e.midY))
    }
}
