import AVFoundation
import CoreMedia

/// Escreve vídeo + uma faixa de áudio por fonte (música, microfone, som do Mac) num .mov.
/// Todos os métodos de append devem ser chamados na MESMA fila serial (sampleQueue).
final class MovieWriter {
    let url: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var audioInputs: [AudioTrack: AVAssetWriterInput] = [:]
    private var sessionStarted = false
    private var sessionStart: CMTime = .invalid
    private var finishing = false

    init(url: URL, width: Int, height: Int, settings: RecordingSettings, audioTracks: [AudioTrack]) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        // Arquivo fragmentado: se o app cair, o que já foi gravado continua legível.
        writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: settings.bitrate(for: CGSize(width: width, height: height)),
            AVVideoExpectedSourceFrameRateKey: settings.fps,
            AVVideoMaxKeyFrameIntervalKey: settings.fps * 2,
            AVVideoAllowFrameReorderingKey: false,
        ]
        if settings.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: settings.codec.avCodec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        // Usado no modo câmera lateral, quando o quadro vem do compositor.
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput,
                                                       sourcePixelBufferAttributes: nil)
        guard writer.canAdd(videoInput) else { throw CaptureError.writerSetupFailed }
        writer.add(videoInput)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 320_000,
        ]
        // Ordem fixa (música → mic → Mac): a faixa 1 é sempre a mais importante.
        for track in AudioTrack.allCases where audioTracks.contains(track) {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw CaptureError.writerSetupFailed }
            writer.add(input)
            audioInputs[track] = input
        }
    }

    /// Frame vindo direto do ScreenCaptureKit (sem composição).
    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard startIfNeeded(at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) else { return }
        if videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
        }
    }

    /// Frame montado pelo compositor (modo câmera lateral).
    func appendPixelBuffer(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard startIfNeeded(at: time) else { return }
        if videoInput.isReadyForMoreMediaData {
            adaptor.append(pixelBuffer, withPresentationTime: time)
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer, to track: AudioTrack) {
        guard sessionStarted, !finishing, writer.status == .writing else { return }
        guard CMSampleBufferGetPresentationTimeStamp(sampleBuffer) >= sessionStart else { return }
        guard let input = audioInputs[track], input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    private func startIfNeeded(at time: CMTime) -> Bool {
        guard !finishing, writer.status != .failed else { return false }
        if !sessionStarted {
            guard writer.startWriting() else { return false }
            writer.startSession(atSourceTime: time)
            sessionStart = time
            sessionStarted = true
        }
        return true
    }

    /// Finaliza o arquivo. Executa na fila de samples para não competir com appends.
    func finish(on queue: DispatchQueue, completion: @escaping (Error?) -> Void) {
        queue.async {
            self.finishing = true
            guard self.sessionStarted, self.writer.status == .writing else {
                if self.writer.status == .writing { self.writer.cancelWriting() }
                try? FileManager.default.removeItem(at: self.url)
                completion(self.writer.error ?? CaptureError.noFrames)
                return
            }
            self.videoInput.markAsFinished()
            self.audioInputs.values.forEach { $0.markAsFinished() }
            self.writer.finishWriting {
                completion(self.writer.status == .completed ? nil : self.writer.error)
            }
        }
    }

    func cancel(on queue: DispatchQueue) {
        queue.async {
            self.finishing = true
            if self.writer.status == .writing { self.writer.cancelWriting() }
            try? FileManager.default.removeItem(at: self.url)
        }
    }
}
