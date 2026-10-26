import Foundation
import Testing

@testable import Scribe

struct TranscriptionProgressTests {
    private func progress(_ stage: TranscriptionProgress.Stage, queued: Int = 0, again: Bool = false) -> TranscriptionProgress {
        TranscriptionProgress(
            session: "2026-10-26 1000 - Planning",
            modelTitle: "Whisper Filipino",
            isRetranscription: again,
            startedAt: Date(),
            stage: stage,
            queued: queued
        )
    }

    @Test("Stage text names the track being transcribed")
    func stageText() {
        #expect(progress(.loadingModel).stageText == "Loading the model")
        #expect(progress(.transcribingTrack(speaker: "me", index: 1, count: 2)).stageText == "Your microphone · track 1 of 2")
        #expect(progress(.transcribingTrack(speaker: "them", index: 1, count: 1)).stageText == "Call audio")
        #expect(progress(.writingNotes).stageText == "Writing notes")
    }

    @Test("Headline and summary describe the job and queue")
    func headlineAndSummary() {
        #expect(progress(.loadingModel).headline == "Transcribing with Whisper Filipino")
        #expect(progress(.loadingModel, again: true).headline == "Transcribing again with Whisper Filipino")
        #expect(progress(.writingNotes, queued: 2).summary == "Transcribing · Writing notes · 2 queued")
    }

    @Test("Slow model loads explain the first-run delay")
    func hint() {
        #expect(progress(.loadingModel).hint(elapsed: 10) == nil)
        #expect(progress(.loadingModel).hint(elapsed: 45) != nil)
        #expect(progress(.writingNotes).hint(elapsed: 300) == nil)
    }

    @Test("Elapsed time reads as seconds, then minutes")
    func elapsed() {
        #expect(TranscriptionProgress.elapsedText(42) == "42s")
        #expect(TranscriptionProgress.elapsedText(185) == "3m 05s")
    }

    @Test("The queue reports each stage, then idle")
    func reportsStages() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("scribe-progress-\(UUID())")
        let directory = root.appendingPathComponent("2026-10-26 1000 - Planning")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("""
        {"state":"complete","title":"Planning","started":"2026-10-26T02:00:00Z",
         "files":{"mic":"mic.caf","system":"system.caf"}}
        """.utf8).write(to: directory.appendingPathComponent("meta.json"))
        for name in ["mic.caf", "system.caf"] {
            try Data("fixture".utf8).write(to: directory.appendingPathComponent(name))
        }

        let (events, continuation) = AsyncStream<TranscriptionCoordinator.Status>.makeStream()
        let coordinator = TranscriptionCoordinator(makeChosenEngine: { _ in ProgressTestEngine() })
        await coordinator.setStatusHandler { continuation.yield($0) }
        await coordinator.retranscribe(directory, with: TranscriptionChoice(model: .filipino, language: .filipino))

        var stages: [TranscriptionProgress.Stage] = []
        for await status in events {
            if case .transcribing(let progress) = status {
                #expect(progress.isRetranscription)
                #expect(progress.session == directory.lastPathComponent)
                if stages.last != progress.stage { stages.append(progress.stage) }
            } else {
                break
            }
        }
        #expect(stages == [
            .loadingModel,
            .transcribingTrack(speaker: "me", index: 1, count: 2),
            .transcribingTrack(speaker: "them", index: 2, count: 2),
        ])
    }
}

private struct ProgressTestEngine: TranscriptionEngine {
    let name = "test"
    let model = "test"

    func prepare() async throws {}

    func transcribe(_ audio: URL) async throws -> [TranscriptSegment] {
        [TranscriptSegment(start: 0, end: 1, text: audio.lastPathComponent)]
    }

    func release() async {}
}
