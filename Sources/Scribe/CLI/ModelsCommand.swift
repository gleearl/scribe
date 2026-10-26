import ArgumentParser
import FluidAudio
import Foundation
import WhisperKit

struct Models: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage explicitly downloaded local models.",
        subcommands: [DownloadTranscriptionModel.self]
    )
}

struct DownloadTranscriptionModel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "download-transcription",
        abstract: "Explicitly download a local transcription model."
    )

    @Flag(name: .long, help: "Replace an existing cached model.")
    var force = false

    @Option(name: .long, help: "Model: \(LocalTranscriptionModel.choices).")
    var model: String = LocalTranscriptionModel.selected.rawValue

    func run() async throws {
        guard let selected = LocalTranscriptionModel(rawValue: model) else {
            throw ValidationError("Unknown model '\(model)'. Choose \(LocalTranscriptionModel.choices).")
        }
        let destination = try await selected.download(force: force)
        print("transcription model ready at \(destination.path)")
    }
}

extension LocalTranscriptionModel {
    /// Explicit, user-initiated download. Runtime transcription never calls this.
    func download(force: Bool) async throws -> URL {
        guard let fluidVersion else { return try await WhisperModelStore.download(force: force) }
        return try await AsrModels.download(force: force, version: fluidVersion)
    }
}

extension WhisperModelStore {
    static func download(force: Bool) async throws -> URL {
        if force { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let folder = try await WhisperKit.download(variant: variant, downloadBase: base, from: repo)
        // Loading once fetches the tokenizer into `base`, so later loads
        // find it locally instead of reaching for the network.
        let kit = try await WhisperKit(WhisperKitConfig(
            downloadBase: base,
            modelFolder: folder.path,
            tokenizerFolder: base,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        ))
        await kit.unloadModels()
        guard isInstalled else {
            throw WhisperEngine.EngineError.modelMissing(modelFolder)
        }
        return folder
    }
}
