import Foundation
import Testing
import WhisperKit

@testable import Scribe

struct WhisperTranscriptionTests {
    @Test("Whisper Filipino is a Whisper model, the rest stay on Parakeet")
    func modelEngines() {
        #expect(LocalTranscriptionModel.filipino.engineName == "whisper")
        #expect(LocalTranscriptionModel.filipino.fluidVersion == nil)
        #expect(LocalTranscriptionModel.filipino.makeEngine() is WhisperEngine)
        for model in [LocalTranscriptionModel.english, .multilingual, .compact] {
            #expect(model.engineName == "parakeet")
            #expect(model.fluidVersion != nil)
            #expect(model.makeEngine() is ParakeetEngine)
        }
    }

    @Test("CLI model choices list every model")
    func choices() {
        #expect(LocalTranscriptionModel.choices
            == "parakeet-v2, parakeet-v3, parakeet-110m, or whisper-large-v3-turbo")
    }

    @Test("Language maps to a Whisper code, auto lets Whisper detect")
    func languageCodes() {
        #expect(TranscriptionLanguage.filipino.whisperCode == "tl")
        #expect(TranscriptionLanguage.english.whisperCode == "en")
        #expect(TranscriptionLanguage.auto.whisperCode == nil)
    }

    @Test("Transcription config carries the Whisper language")
    func parsesLanguage() throws {
        let document = try Config.parse(Data(#"""
        {"transcription": {"engine": "whisper", "model": "whisper-large-v3-turbo", "language": "tl"}}
        """#.utf8))
        #expect(document.transcription?.engine == "whisper")
        #expect(LocalTranscriptionModel(rawValue: document.transcription?.model ?? "") == .filipino)
        #expect(document.transcription?.language == "tl")
    }

    @Test("Whisper segments drop control tokens and empty text, sorted by time")
    func segmentCleanup() {
        func segment(_ start: Float, _ end: Float, _ text: String) -> TranscriptionSegment {
            TranscriptionSegment(start: start, end: end, text: text)
        }
        let out = WhisperEngine.segments(from: [
            segment(4, 6, "<|startoftranscript|><|tl|> Salamat po.<|endoftext|>"),
            segment(0, 3, " Kumusta kayo, let's start the meeting."),
            segment(3, 4, "<|nospeech|>"),
        ])
        #expect(out.map(\.text) == ["Kumusta kayo, let's start the meeting.", "Salamat po."])
        #expect(out.map(\.start) == [0, 4])
        #expect(out.last?.end == 6)
    }
}
