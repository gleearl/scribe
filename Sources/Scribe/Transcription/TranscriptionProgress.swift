import Foundation

/// What the transcription queue is doing right now, for the progress
/// indicator in the app and menu bar.
struct TranscriptionProgress: Equatable, Sendable {
    enum Stage: Equatable, Sendable {
        case loadingModel
        case transcribingTrack(speaker: String, index: Int, count: Int)
        case writingNotes
    }

    /// Session folder name of the meeting being transcribed.
    let session: String
    let modelTitle: String
    let isRetranscription: Bool
    let startedAt: Date
    var stage: Stage
    /// Meetings waiting behind this one.
    var queued: Int

    var headline: String {
        isRetranscription ? "Transcribing again with \(modelTitle)" : "Transcribing with \(modelTitle)"
    }

    var stageText: String {
        switch stage {
        case .loadingModel:
            return "Loading the model"
        case .transcribingTrack(let speaker, let index, let count):
            let track = Self.trackName(speaker)
            return count > 1 ? "\(track) · track \(index) of \(count)" : track
        case .writingNotes:
            return "Writing notes"
        }
    }

    /// One line for the toolbar and menu bar.
    var summary: String {
        let queue = queued > 0 ? " · \(queued) queued" : ""
        return "Transcribing · \(stageText)\(queue)"
    }

    /// Extra reassurance once loading has taken a while; the first load after
    /// a download compiles the model for this Mac.
    func hint(elapsed: TimeInterval) -> String? {
        guard stage == .loadingModel, elapsed >= 30 else { return nil }
        return "The first run after downloading a model can take several minutes while macOS prepares it."
    }

    static func elapsedText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return total < 60 ? "\(total)s" : String(format: "%dm %02ds", total / 60, total % 60)
    }

    private static func trackName(_ speaker: String) -> String {
        switch speaker {
        case "me": return "Your microphone"
        case "them": return "Call audio"
        default: return speaker
        }
    }
}
