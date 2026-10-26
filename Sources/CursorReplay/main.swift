import AuraMotionCore
import Darwin
import Foundation

private struct Options {
    var input: URL?
    var output: URL?
    var settings: URL?
    var source: CursorExperimentSource?
    var synthetic = false
    var sweep = false
    var fps = 60
    var showHelp = false
}

@main
private enum CursorReplayCommand {
    static func main() {
        do {
            let options = try parse(Array(CommandLine.arguments.dropFirst()))
            if options.showHelp {
                printHelp()
                return
            }
            guard let output = options.output else {
                throw CLIError.usage("--output <path.csv|path.json> is required.")
            }
            let recording: CursorExperimentRecording
            if options.synthetic {
                guard options.input == nil else { throw CLIError.usage("Use either --synthetic or --input, not both.") }
                recording = CursorExperimentSyntheticTrace.makeRecording(fps: options.fps)
            } else {
                guard let input = options.input else {
                    throw CLIError.usage("Pass --input <RecordedSession.json> or --synthetic.")
                }
                recording = try CursorExperimentRecordingCodec.load(from: input, legacySource: options.source)
            }

            let report: CursorExperimentReplayReport
            if options.sweep {
                guard options.settings == nil else {
                    throw CLIError.usage("Use either --sweep or --settings, not both.")
                }
                report = try CursorExperimentReplayEvaluator.evaluateSweep(recording)
            } else if let settingsURL = options.settings {
                let settings = try loadSettings(from: settingsURL)
                report = try CursorExperimentReplayEvaluator.evaluate(recording, optimizedSettings: settings)
            } else {
                report = try CursorExperimentReplayEvaluator.evaluate(recording)
            }
            _ = try CursorExperimentMetricsExporter.write(report, to: output)
            let replayKind = options.sweep ? "module sweep" : "baseline+optimized replay"
            print("Wrote \(recording.source.rawValue) \(replayKind) to \(output.path)")
        } catch {
            FileHandle.standardError.write(Data("CursorReplay: \(error.localizedDescription)\n".utf8))
            if error is CLIError { printHelp(to: .standardError) }
            exit(EXIT_FAILURE)
        }
    }

    private static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                options.showHelp = true
            case "--synthetic":
                options.synthetic = true
            case "--sweep":
                options.sweep = true
            case "--input":
                index += 1
                guard index < arguments.count else { throw CLIError.usage("--input needs a file path.") }
                options.input = URL(fileURLWithPath: arguments[index])
            case "--output":
                index += 1
                guard index < arguments.count else { throw CLIError.usage("--output needs a file path.") }
                options.output = URL(fileURLWithPath: arguments[index])
            case "--settings":
                index += 1
                guard index < arguments.count else { throw CLIError.usage("--settings needs a JSON file path.") }
                options.settings = URL(fileURLWithPath: arguments[index])
            case "--source":
                index += 1
                guard index < arguments.count,
                      let source = CursorExperimentSource(rawValue: arguments[index]) else {
                    throw CLIError.usage("--source must be camera or synthetic.")
                }
                options.source = source
            case "--fps":
                index += 1
                guard index < arguments.count, let fps = Int(arguments[index]), (10...120).contains(fps) else {
                    throw CLIError.usage("--fps must be an integer from 10 through 120.")
                }
                options.fps = fps
            default:
                throw CLIError.usage("Unknown argument: \(argument)")
            }
            index += 1
        }
        return options
    }

    private static func loadSettings(from url: URL) throws -> CursorExperimentSettings {
        let data = try Data(contentsOf: url)
        guard let overrides = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIError.usage("--settings must contain a JSON object of CursorExperimentSettings fields.")
        }

        var optimizedDefaults = CursorExperimentSettings()
        optimizedDefaults.applyPreset(.optimized)
        let encodedDefaults = try JSONEncoder().encode(optimizedDefaults)
        guard var merged = try JSONSerialization.jsonObject(with: encodedDefaults) as? [String: Any] else {
            throw CLIError.usage("Could not encode Optimized defaults for --settings.")
        }
        let unknownKeys = Set(overrides.keys).subtracting(merged.keys)
        guard unknownKeys.isEmpty else {
            throw CLIError.usage("Unknown --settings field(s): \(unknownKeys.sorted().joined(separator: ", ")).")
        }
        for (key, value) in overrides { merged[key] = value }

        let mergedData = try JSONSerialization.data(withJSONObject: merged)
        return try JSONDecoder().decode(CursorExperimentSettings.self, from: mergedData).normalized()
    }

    private static func printHelp(to handle: FileHandle = .standardOutput) {
        let help = """
        Usage:
          swift run CursorReplay --synthetic --output /tmp/cursor-replay.csv [--fps 60] [--sweep]
          swift run CursorReplay --input session.json --source camera --output report.json
          swift run CursorReplay --input recording.json --settings cursor-settings.json --output report.json

        New CursorExperimentRecording JSON includes its source and needs no --source.
        Legacy LandmarkRecorder JSON has no source label; pass --source camera or
        --source synthetic explicitly. CSV contains baseline and optimized runs in
        one file. JSON includes rows, measured summaries, and explicit unavailable reasons.
        --settings uses JSON CursorExperimentSettings fields over Optimized defaults for
        the optimized replay only; baseline remains unchanged. The option cannot be combined
        with --sweep. Omitted fields retain their Optimized default values.
        Synthetic traces are deterministic model checks; they do not report real
        inference time, CPU, or memory.
        """
        handle.write(Data((help + "\n").utf8))
    }
}

private enum CLIError: Error, LocalizedError {
    case usage(String)

    var errorDescription: String? {
        if case let .usage(message) = self { return message }
        return nil
    }
}
