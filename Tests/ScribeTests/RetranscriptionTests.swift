import Foundation
import Testing

@testable import Scribe

struct RetranscriptionTests {
    @Test("Transcribe again offers each Parakeet model once and Whisper per language")
    func choices() {
        let titles = TranscriptionChoice.all.map(\.title)
        #expect(titles == [
            "Parakeet English",
            "Parakeet Multilingual",
            "Parakeet Compact",
            "Whisper Filipino · Filipino (Tagalog)",
            "Whisper Filipino · English",
            "Whisper Filipino · Detect automatically",
        ])
    }

    @Test("Transcribing again replaces the transcript with the chosen engine and keeps notes")
    func replacesTranscript() async throws {
        let directory = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let choice = TranscriptionChoice(model: .filipino, language: .filipino)
        let coordinator = TranscriptionCoordinator(
            makeEngine: { FixedEngine(name: "settings", text: "from settings") },
            makeChosenEngine: { chosen in
                FixedEngine(name: "chosen-\(chosen.language.rawValue)", text: "Kumusta kayo")
            }
        )

        try await coordinator.processNow(directory, choice: choice)

        let transcript = try JSONDecoder().decode(
            Transcript.self, from: Data(contentsOf: directory.appendingPathComponent("transcript.json"))
        )
        #expect(transcript.engine == "chosen-tl")
        #expect(Set(transcript.segments.map(\.text)) == ["Kumusta kayo mic.caf", "Kumusta kayo system.caf"])
        let markdown = try String(contentsOf: directory.appendingPathComponent("transcript.md"), encoding: .utf8)
        #expect(markdown.contains("Ana"))
        #expect(try String(contentsOf: directory.appendingPathComponent("note.md"), encoding: .utf8) == "original note")
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("speaker-overrides.json").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("speaker-names.json").path))
    }

    @Test("Transcribing again with no recognized speech keeps the existing transcript")
    func keepsTranscriptWhenEmpty() async throws {
        let directory = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let before = try Data(contentsOf: directory.appendingPathComponent("transcript.json"))
        let coordinator = TranscriptionCoordinator(
            makeChosenEngine: { _ in FixedEngine(name: "chosen", text: nil) }
        )

        await #expect(throws: TranscriptionCoordinator.RetranscriptionError.self) {
            try await coordinator.processNow(
                directory,
                choice: TranscriptionChoice(model: .english, language: .auto)
            )
        }
        #expect(try Data(contentsOf: directory.appendingPathComponent("transcript.json")) == before)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("speaker-overrides.json").path))
    }

    private func makeMeeting() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("scribe-retranscribe-\(UUID())")
        let directory = root.appendingPathComponent("2026-10-26 1000 - Planning")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let files: [String: String] = [
            "meta.json": """
            {"state":"complete","title":"Planning","started":"2026-10-26T02:00:00Z",
             "files":{"mic":"mic.caf","system":"system.caf"}}
            """,
            "mic.caf": "fixture",
            "system.caf": "fixture",
            "transcript.json": """
            {"engine":"parakeet","model":"parakeet-tdt-0.6b-v2-coreml","created_at":"2026-10-26T02:30:00Z",
             "segments":[{"speaker":"them","start_ms":0,"end_ms":1000,"text":"garbled"}]}
            """,
            "transcript.md": "# Planning\n",
            "note.md": "original note",
            "speaker-names.json": #"{"them":"Ana"}"#,
            "speaker-overrides.json": #"{"0":"Ben"}"#,
        ]
        for (name, contents) in files {
            try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
        }
        return directory
    }
}

private struct FixedEngine: TranscriptionEngine {
    let name: String
    let model = "test"
    /// nil simulates a track with no recognized speech.
    let text: String?

    func prepare() async throws {}

    func transcribe(_ audio: URL) async throws -> [TranscriptSegment] {
        text.map { [TranscriptSegment(start: 0, end: 1, text: "\($0) \(audio.lastPathComponent)")] } ?? []
    }

    func release() async {}
}
