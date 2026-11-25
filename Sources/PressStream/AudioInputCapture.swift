import AVFoundation
import CoreMedia

/// Captura a entrada de áudio escolhida (controladora, interface ou microfone)
/// e entrega PCM 48 kHz estéreo na fila de samples, com timestamps no relógio do host
/// (o mesmo relógio usado pelo ScreenCaptureKit).
final class AudioInputCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let handler: (CMSampleBuffer) -> Void

    init(deviceUID: String, queue: DispatchQueue, handler: @escaping (CMSampleBuffer) -> Void) throws {
        guard let device = AVCaptureDevice(uniqueID: deviceUID) else {
            throw CaptureError.audioDeviceNotFound
        }
        self.handler = handler
        super.init()

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CaptureError.audioDeviceUnavailable
        }
        session.addInput(input)

        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CaptureError.audioDeviceUnavailable
        }
        session.addOutput(output)
        session.commitConfiguration()
    }

    func start() { session.startRunning() }
    func stop() { session.stopRunning() }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        handler(retimedToHostClock(sampleBuffer) ?? sampleBuffer)
    }

    /// Normalmente o relógio da sessão já é o do host; se não for, converte os timestamps.
    private func retimedToHostClock(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let clock = session.synchronizationClock else { return nil }
        let host = CMClockGetHostTimeClock()
        if CFEqual(clock, host) { return nil }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let delta = CMSyncConvertTime(pts, from: clock, to: host) - pts

        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return nil }
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count, arrayToFill: &timings, entriesNeededOut: &count)
        for i in timings.indices {
            timings[i].presentationTimeStamp = timings[i].presentationTimeStamp + delta
            timings[i].decodeTimeStamp = .invalid
        }

        var retimed: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sampleBuffer,
                                              sampleTimingEntryCount: count, sampleTimingArray: &timings,
                                              sampleBufferOut: &retimed)
        return retimed
    }
}
