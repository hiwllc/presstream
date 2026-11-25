import Accelerate
import CoreMedia
import Foundation

/// Faixas de áudio gravadas, na ordem em que entram no arquivo.
enum AudioTrack: String, CaseIterable {
    case music   // entrada de música: controladora, interface ou device virtual/agregado (ex.: Rekordbox)
    case mic     // microfone
    case system  // som do Mac (ScreenCaptureKit)
}

/// Aplica o ganho de cada faixa direto no PCM (antes do AAC) e mede o pico.
/// O processamento é in-place com vDSP: custo desprezível.
final class AudioMixer {
    private let lock = NSLock()
    private var gains: [AudioTrack: Float] = [:]
    private var peaks: [AudioTrack: Float] = [:]

    func setGain(_ gain: Float, for track: AudioTrack) {
        lock.lock(); defer { lock.unlock() }
        gains[track] = gain
    }

    /// Chamado na fila de samples para cada buffer de áudio.
    func process(_ sampleBuffer: CMSampleBuffer, track: AudioTrack) {
        lock.lock()
        let gain = gains[track] ?? 1
        lock.unlock()

        let peak = Self.applyGain(gain, to: sampleBuffer)

        lock.lock()
        peaks[track] = max(peaks[track] ?? 0, peak)
        lock.unlock()
    }

    /// Lê e zera os picos acumulados (a UI chama ~15x por segundo).
    func takePeaks() -> [AudioTrack: Float] {
        lock.lock(); defer { lock.unlock() }
        let result = peaks
        peaks.removeAll(keepingCapacity: true)
        return result
    }

    private static func applyGain(_ gain: Float, to sampleBuffer: CMSampleBuffer) -> Float {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatID == AudioFormatID(kAudioFormatLinearPCM),
              asbd.mFormatFlags & AudioFormatFlags(kAudioFormatFlagIsFloat) != 0,
              asbd.mBitsPerChannel == 32,
              let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0 }

        var length = 0
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &length,
                                          totalLengthOut: nil, dataPointerOut: &pointer) == kCMBlockBufferNoErr,
              let pointer else { return 0 }

        let count = length / MemoryLayout<Float>.size
        guard count > 0 else { return 0 }

        // O ganho é igual em todos os canais, então o layout (intercalado ou não) não importa.
        return pointer.withMemoryRebound(to: Float.self, capacity: count) { samples in
            if gain != 1 {
                var g = gain
                vDSP_vsmul(samples, 1, &g, samples, 1, vDSP_Length(count))
            }
            var peak: Float = 0
            vDSP_maxmgv(samples, 1, &peak, vDSP_Length(count))
            return peak
        }
    }
}
