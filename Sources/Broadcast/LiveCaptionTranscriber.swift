import AVFoundation
import Speech

/// SpeechAnalyzer runs the recognition model on device. Audio and text are never
/// written to App Group, logs, a server or a transcript file.
@available(iOS 26, *)
final class LiveCaptionTranscriber {
    private var task: Task<Void, Never>?
    private let lock = NSLock()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var stopped = false

    init(locale: String, onText: @escaping @Sendable (String) -> Void, onUnavailable: @escaping @Sendable () -> Void) {
        task = Task { [weak self] in
            guard SpeechTranscriber.isAvailable,
                  let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else {
                onUnavailable(); return
            }
            let module = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
            // Models are installed in the phone's settings flow, never mid-broadcast.
            guard await AssetInventory.status(forModules: [module]) == .installed,
                  let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
                onUnavailable(); return
            }
            let analyzer = SpeechAnalyzer(modules: [module])
            let (audio, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(bufferingPolicy: .bufferingNewest(12))
            self?.setContinuation(continuation)
            let results = Task {
                do {
                    for try await result in module.results {
                        guard !Task.isCancelled else { return }
                        onText(String(result.text.characters))
                    }
                } catch { if !Task.isCancelled { onUnavailable() } }
            }
            let (inputs, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(12))
            let conversion = Task {
                var converter: AVAudioConverter?
                for await buffer in audio {
                    guard !Task.isCancelled else { break }
                    if let converted = PCMUtilities.convert(buffer, to: format, converter: &converter) {
                        inputContinuation.yield(AnalyzerInput(buffer: converted))
                    }
                }
                inputContinuation.finish()
            }
            do { try await analyzer.prepareToAnalyze(in: format); try await analyzer.start(inputSequence: inputs) }
            catch {
                if !Task.isCancelled { onUnavailable() }
                // A failed recognizer must not keep converting broadcast audio.
                continuation.finish()
                conversion.cancel()
                inputContinuation.finish()
            }
            await conversion.value
            await analyzer.cancelAndFinishNow()
            results.cancel()
            onText("")
        }
    }
    private func setContinuation(_ continuation: AsyncStream<AVAudioPCMBuffer>.Continuation) {
        lock.lock(); defer { lock.unlock() }
        if stopped { continuation.finish() } else { self.continuation = continuation }
    }
    func append(_ sample: CMSampleBuffer) {
        lock.lock(); let continuation = stopped ? nil : continuation; lock.unlock()
        guard let continuation, let pcm = PCMUtilities.copyPCM(sample) else { return }
        continuation.yield(pcm)
    }
    func stop() {
        lock.lock(); stopped = true; continuation?.finish(); continuation = nil; lock.unlock()
        task?.cancel(); task = nil
    }
    deinit { stop() }
}
