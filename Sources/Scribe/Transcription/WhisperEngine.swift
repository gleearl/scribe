import AVFoundation
import Foundation
// WhisperKit predates Sendable; the engine actor owns its instance exclusively.
@preconcurrency import WhisperKit

/// Where Scribe keeps its WhisperKit model and tokenizer. Both are fetched
/// together by `scribe models download-transcription` so runtime
/// transcription stays offline.
enum WhisperModelStore {
    static let variant = "openai_whisper-large-v3-v20240930_turbo_632MB"
    static let repo = "argmaxinc/whisperkit-coreml"
    static let tokenizerRepo = "openai/whisper-large-v3"

    static var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scribe/WhisperKit", isDirectory: true)
    }

    /// Mirrors WhisperKit's hub layout: <base>/models/<repo>/<variant>.
    static var modelFolder: URL {
        base.appendingPathComponent("models/\(repo)/\(variant)", isDirectory: true)
    }

    static var tokenizerFolder: URL {
        base.appendingPathComponent("models/\(tokenizerRepo)", isDirectory: true)
    }

    static var isInstalled: Bool {
        let files = ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"]
            .map { modelFolder.appendingPathComponent($0) }
            + [tokenizerFolder.appendingPathComponent("tokenizer.json")]
        return files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// Whisper large-v3 turbo via WhisperKit's Core ML port. Unlike Parakeet it
/// covers Tagalog/Filipino and copes with Taglish code-switching.
actor WhisperEngine: TranscriptionEngine {
    enum EngineError: Error, CustomStringConvertible {
        case notPrepared
        case modelMissing(URL)
        case unreadableAudio(URL, Error?)

        var description: String {
            switch self {
            case .notPrepared: return "whisper engine used before prepare()"
            case .modelMissing(let url):
                return "local transcription model is missing at \(url.path); run `scribe models download-transcription --model whisper-large-v3-turbo` before recording"
            case .unreadableAudio(let url, let e):
                return "unreadable or empty audio \(url.lastPathComponent)"
                    + (e.map { ": \($0)" } ?? "")
            }
        }
    }

    nonisolated let name = "whisper"
    nonisolated let selectedModel: LocalTranscriptionModel
    nonisolated let language: TranscriptionLanguage
    nonisolated var model: String { selectedModel.modelIdentifier }

    private var kit: WhisperKit?

    init(model: LocalTranscriptionModel = .filipino, language: TranscriptionLanguage = .selected) {
        selectedModel = model
        self.language = language
    }

    func prepare() async throws {
        guard kit == nil else { return }
        guard WhisperModelStore.isInstalled else {
            throw EngineError.modelMissing(WhisperModelStore.modelFolder)
        }
        kit = try await WhisperKit(WhisperKitConfig(
            downloadBase: WhisperModelStore.base,
            modelFolder: WhisperModelStore.modelFolder.path,
            tokenizerFolder: WhisperModelStore.base,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        ))
    }

    func transcribe(_ audio: URL) async throws -> [TranscriptSegment] {
        guard let kit else { throw EngineError.notPrepared }

        // Same guard as ParakeetEngine: an empty track crashes AVFoundation's
        // resampler with an uncatchable ObjC exception.
        do {
            let probe = try AVAudioFile(forReading: audio)
            guard probe.length > 0 else { throw EngineError.unreadableAudio(audio, nil) }
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineError.unreadableAudio(audio, error)
        }

        let options = DecodingOptions(
            task: .transcribe,
            language: language.whisperCode,
            usePrefillPrompt: language.whisperCode != nil,
            detectLanguage: language.whisperCode == nil,
            skipSpecialTokens: true,
            // VAD chunking skips silence, which is where Whisper hallucinates.
            chunkingStrategy: .vad
        )
        let results = try await kit.transcribe(audioPath: audio.path, decodeOptions: options)
        return Self.segments(from: results.flatMap(\.segments))
    }

    func release() async {
        if let kit { await kit.unloadModels() }
        kit = nil
    }

    static func segments(from segments: [TranscriptionSegment]) -> [TranscriptSegment] {
        segments.compactMap { segment in
            let text = cleaned(segment.text)
            guard !text.isEmpty else { return nil }
            return TranscriptSegment(
                start: TimeInterval(segment.start),
                end: TimeInterval(segment.end),
                text: text
            )
        }
        .sorted { $0.start < $1.start }
    }

    /// Strip any `<|…|>` control tokens Whisper leaves in segment text.
    static func cleaned(_ text: String) -> String {
        text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
