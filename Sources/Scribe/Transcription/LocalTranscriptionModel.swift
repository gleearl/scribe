import FluidAudio
import Foundation

enum LocalTranscriptionModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case english = "parakeet-v2"
    case multilingual = "parakeet-v3"
    case compact = "parakeet-110m"
    case filipino = "whisper-large-v3-turbo"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: return "Parakeet English"
        case .multilingual: return "Parakeet Multilingual"
        case .compact: return "Parakeet Compact"
        case .filipino: return "Whisper Filipino"
        }
    }

    var detail: String {
        switch self {
        case .english: return "Best English accuracy · recommended"
        case .multilingual: return "25 European languages"
        case .compact: return "Fastest and lightest for everyday notes"
        case .filipino: return "Tagalog, Filipino, and Taglish · slower"
        }
    }

    var approximateSize: String {
        switch self {
        case .english, .multilingual: return "About 600 MB"
        case .compact: return "About 150 MB"
        case .filipino: return "About 650 MB"
        }
    }

    /// Engine identifier recorded in config and transcript.json provenance.
    var engineName: String {
        switch self {
        case .english, .multilingual, .compact: return "parakeet"
        case .filipino: return "whisper"
        }
    }

    var modelIdentifier: String {
        switch self {
        case .english: return "parakeet-tdt-0.6b-v2-coreml"
        case .multilingual: return "parakeet-tdt-0.6b-v3-coreml"
        case .compact: return "parakeet-tdt-ctc-110m-coreml"
        case .filipino: return WhisperModelStore.variant
        }
    }

    /// FluidAudio's version for Parakeet models; nil for Whisper.
    var fluidVersion: AsrModelVersion? {
        switch self {
        case .english: return .v2
        case .multilingual: return .v3
        case .compact: return .tdtCtc110m
        case .filipino: return nil
        }
    }

    var isInstalled: Bool {
        guard let fluidVersion else { return WhisperModelStore.isInstalled }
        let cache = AsrModels.defaultCacheDirectory(for: fluidVersion)
        return AsrModels.modelsExist(at: cache, version: fluidVersion)
    }

    func makeEngine() -> any TranscriptionEngine {
        fluidVersion == nil ? WhisperEngine(model: self) : ParakeetEngine(model: self)
    }

    static var selected: LocalTranscriptionModel {
        LocalTranscriptionModel(rawValue: Config.transcriptionModelID()) ?? .english
    }

    static var choices: String {
        let ids = allCases.map(\.rawValue)
        return ids.dropLast().joined(separator: ", ") + ", or " + ids.last!
    }
}

/// Spoken language passed to Whisper. Parakeet ignores it.
enum TranscriptionLanguage: String, CaseIterable, Identifiable, Sendable {
    case filipino = "tl"
    case english = "en"
    case auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .filipino: return "Filipino (Tagalog)"
        case .english: return "English"
        case .auto: return "Detect automatically"
        }
    }

    /// Whisper language code, or nil to let Whisper detect it.
    var whisperCode: String? { self == .auto ? nil : rawValue }

    static var selected: TranscriptionLanguage {
        Config.transcriptionLanguage().flatMap(TranscriptionLanguage.init(rawValue:)) ?? .filipino
    }
}
