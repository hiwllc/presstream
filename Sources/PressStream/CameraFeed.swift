import AVFoundation
import CoreVideo

/// Câmera para o modo lateral: guarda sempre o frame mais recente (BGRA)
/// para o compositor e expõe a sessão para o preview no painel.
final class CameraFeed: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "app.pressstream.camerafeed")
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var device: AVCaptureDevice?

    init(deviceUID: String?) throws {
        let device = deviceUID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .video)
        guard let device else { throw BubbleError.noCamera }
        super.init()

        session.beginConfiguration()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw BubbleError.cameraUnavailable
        }
        session.addInput(input)
        // Usa o formato nativo da câmera em vez de um preset fixo de 720p.
        // (No macOS, definir activeFormat já coloca a sessão em "input priority".)
        self.device = device
        Self.selectBestFormat(for: device)

        // YUV 4:2:0 ocupa ~40% da memória de BGRA; o Core Image converte na GPU.
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw BubbleError.cameraUnavailable
        }
        session.addOutput(output)
        session.commitConfiguration()
    }

    /// Maior resolução até 1080p que aguente 30 fps. Acima disso (4K) só gastaria USB e RAM:
    /// a faixa lateral tem no máximo ~1080–1440 px de altura.
    private static func selectBestFormat(for device: AVCaptureDevice) {
        let target = CMTime(value: 1, timescale: 30)
        func supports30(_ format: AVCaptureDevice.Format) -> Bool {
            format.videoSupportedFrameRateRanges.contains {
                $0.minFrameDuration <= target && target <= $0.maxFrameDuration
            }
        }
        func pixels(_ format: AVCaptureDevice.Format) -> Int32 {
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return d.width * d.height
        }
        let candidates = device.formats.filter {
            CMVideoFormatDescriptionGetDimensions($0.formatDescription).height <= 1080 && supports30($0)
        }
        guard let best = candidates.max(by: { pixels($0) < pixels($1) }) else { return }

        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            device.activeVideoMinFrameDuration = target
            device.activeVideoMaxFrameDuration = target
            device.unlockForConfiguration()
        } catch {
            // Sem acesso exclusivo: segue com o formato padrão da câmera.
        }
    }

    /// Proporção largura/altura da câmera (para a miniatura no painel).
    var aspectRatio: CGFloat {
        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return 16.0 / 9.0 }
        let d = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        return d.height > 0 ? CGFloat(d.width) / CGFloat(d.height) : 16.0 / 9.0
    }

    /// Resolução em uso (para mostrar no painel).
    var resolutionLabel: String {
        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return "" }
        let d = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        return "\(d.width)×\(d.height)"
    }

    func start() {
        queue.async {
            self.session.startRunning()
            // Reaplica depois de iniciar: em algumas câmeras o macOS volta ao formato padrão.
            if let device = self.device { Self.selectBestFormat(for: device) }
        }
    }

    func stop() {
        queue.async { self.session.stopRunning() }
        lock.lock(); latest = nil; lock.unlock()
    }

    var latestFrame: CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock(); latest = buffer; lock.unlock()
    }
}
