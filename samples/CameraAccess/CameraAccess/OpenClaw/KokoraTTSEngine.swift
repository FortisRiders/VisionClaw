import AVFoundation
import Foundation

#if KOKORO_ENABLED

final class KokoraTTSEngine: NSObject {
    static let shared = KokoraTTSEngine()

    private(set) var isReady = false
    var onFinish: (() -> Void)?
    var onPlaybackStarted: (() -> Void)?

    private var handle: OpaquePointer?
    private var player: AVAudioPlayer?
    private var generationTask: Task<Void, Never>?

    private override init() {
        super.init()
        Task.detached(priority: .background) { [weak self] in
            self?.loadModel()
        }
    }

    private func loadModel() {
        let dir = "kokoro-int8-en-v0_19"
        guard
            let modelPath = Bundle.main.path(forResource: "model.int8", ofType: "onnx", inDirectory: dir),
            let voicesPath = Bundle.main.path(forResource: "voices", ofType: "bin", inDirectory: dir),
            let tokensPath = Bundle.main.path(forResource: "tokens", ofType: "txt", inDirectory: dir)
        else {
            NSLog("[KokoroTTS] Model files not found in bundle under %@/", dir)
            return
        }
        let dataDir = Bundle.main.bundlePath + "/\(dir)/espeak-ng-data"

        modelPath.withCString { model in
            voicesPath.withCString { voices in
                tokensPath.withCString { tokens in
                    dataDir.withCString { data in
                    var kokoro = SherpaOnnxOfflineTtsKokoroModelConfig()
                    kokoro.model = model
                    kokoro.voices = voices
                    kokoro.tokens = tokens
                    kokoro.data_dir = data
                    kokoro.length_scale = 1.0

                    var modelCfg = SherpaOnnxOfflineTtsModelConfig()
                    modelCfg.kokoro = kokoro
                    modelCfg.num_threads = 4

                    var ttsCfg = SherpaOnnxOfflineTtsConfig()
                    ttsCfg.model = modelCfg
                    ttsCfg.max_num_sentences = 1

                    handle = SherpaOnnxCreateOfflineTts(&ttsCfg)
                    }
                }
            }
        }

        if handle != nil {
            isReady = true
            NSLog("[KokoroTTS] Model loaded OK")
        } else {
            NSLog("[KokoroTTS] SherpaOnnxCreateOfflineTts returned nil")
        }
    }

    func speak(_ text: String, voiceId: Int32 = 5, onFinish: @escaping () -> Void) {
        guard isReady, let handle else { return }
        generationTask?.cancel()
        self.onFinish = onFinish

        generationTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let audioPtr: UnsafePointer<SherpaOnnxGeneratedAudio>? = text.withCString { cText in
                SherpaOnnxOfflineTtsGenerate(handle, cText, voiceId, 1.0)
            }

            guard !Task.isCancelled, let ptr = audioPtr else { return }
            defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(ptr) }

            let audio = ptr.pointee
            guard audio.n > 0 else { return }

            let wavData = Self.buildWAV(
                samples: audio.samples,
                count: Int(audio.n),
                sampleRate: Int(audio.sample_rate)
            )

            await MainActor.run { [weak self] in
                self?.playWAV(wavData)
            }
        }
    }

    func stop() {
        generationTask?.cancel()
        generationTask = nil
        player?.stop()
        player = nil
        onFinish = nil
        onPlaybackStarted = nil
    }

    private func playWAV(_ data: Data) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("jarvis_tts.wav")
        do {
            try data.write(to: url, options: .atomic)
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.play()
            onPlaybackStarted?()
            onPlaybackStarted = nil
            NSLog("[KokoroTTS] Playback started (%d bytes)", data.count)
        } catch {
            NSLog("[KokoroTTS] Playback error: %@", error.localizedDescription)
            let cb = onFinish
            onFinish = nil
            cb?()
        }
    }

    private static func buildWAV(samples: UnsafePointer<Float>?, count: Int, sampleRate: Int) -> Data {
        let pcmByteCount = count * 2
        let headerSize = 44
        var data = Data(count: headerSize + pcmByteCount)

        data.withUnsafeMutableBytes { ptr in
            var offset = 0

            func writeBytes<T>(_ value: T) {
                withUnsafeBytes(of: value) { src in
                    let dest = UnsafeMutableRawBufferPointer(start: ptr.baseAddress!.advanced(by: offset), count: src.count)
                    src.copyBytes(to: dest)
                    offset += src.count
                }
            }
            func writeASCII(_ s: String) {
                s.utf8.forEach { ptr[offset] = $0; offset += 1 }
            }

            writeASCII("RIFF")
            writeBytes(UInt32(36 + pcmByteCount).littleEndian)
            writeASCII("WAVE")
            writeASCII("fmt ")
            writeBytes(UInt32(16).littleEndian)
            writeBytes(UInt16(1).littleEndian)   // PCM
            writeBytes(UInt16(1).littleEndian)   // mono
            writeBytes(UInt32(sampleRate).littleEndian)
            writeBytes(UInt32(sampleRate * 2).littleEndian)
            writeBytes(UInt16(2).littleEndian)   // block align
            writeBytes(UInt16(16).littleEndian)  // bits per sample
            writeASCII("data")
            writeBytes(UInt32(pcmByteCount).littleEndian)

            for i in 0..<count {
                let clamped = max(-1.0, min(1.0, samples?[i] ?? 0))
                writeBytes(Int16(clamped * 32767.0).littleEndian)
            }
        }
        return data
    }

    deinit {
        if let handle { SherpaOnnxDestroyOfflineTts(handle) }
    }
}

extension KokoraTTSEngine: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        NSLog("[KokoroTTS] Playback finished flag=%@", flag ? "true" : "false")
        let cb = onFinish
        onFinish = nil
        cb?()
    }
}

#else

final class KokoraTTSEngine: NSObject {
    static let shared = KokoraTTSEngine()
    let isReady = false
    var onFinish: (() -> Void)?
    private override init() { super.init() }
    func speak(_ text: String, voiceId: Int32 = 5, onFinish: @escaping () -> Void) {}
    func stop() { onFinish = nil }
}

#endif
