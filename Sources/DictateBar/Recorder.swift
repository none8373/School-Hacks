import AVFoundation

/// Records the microphone straight to a 16 kHz mono WAV, the format whisper.cpp wants.
final class Recorder {
    enum RecorderError: Error { case noPermission, badFormat }

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private(set) var currentURL: URL?

    var isRecording: Bool { engine.isRunning }

    static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { completion(ok) } }
        default: completion(false)
        }
    }

    func start(to url: URL) throws {
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw RecorderError.badFormat
        }
        let file = try AVAudioFile(forWriting: url, settings: outFormat.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        self.file = file
        self.converter = converter
        self.currentURL = url

        let ratio = outFormat.sampleRate / inFormat.sampleRate
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter, let file = self.file else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
            var delivered = false
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, outStatus in
                if delivered { outStatus.pointee = .noDataNow; return nil }
                delivered = true
                outStatus.pointee = .haveData
                return buffer
            }
            if status != .error, out.frameLength > 0 {
                try? file.write(from: out)
            }
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops and returns the finished WAV.
    func stop() -> URL? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
        converter = nil
        let url = currentURL
        currentURL = nil
        return url
    }
}
