import AuraMotionCore
import Darwin
import Foundation

private struct Options {
    var input: URL?
    var output: URL?
    var source: CursorExperimentSource?
    var synthetic = false
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

            let report = try CursorExperimentReplayEvaluator.evaluate(recording)
            _ = try CursorExperimentMetricsExporter.write(report, to: output)
            print("Wrote \(recording.source.rawValue) baseline+optimized replay to \(output.path)")
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
            case "--input":
                index += 1
                guard index < arguments.count else { throw CLIError.usage("--input needs a file path.") }
                options.input = URL(fileURLWithPath: arguments[index])
            case "--output":
                index += 1
                guard index < arguments.count else { throw CLIError.usage("--output needs a file path.") }
                options.output = URL(fileURLWithPath: arguments[index])
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

    private static func printHelp(to handle: FileHandle = .standardOutput) {
        let help = """
        Usage:
          swift run CursorReplay --synthetic --output /tmp/cursor-replay.csv [--fps 60]
          swift run CursorReplay --input session.json --source camera --output report.json

        New CursorExperimentRecording JSON includes its source and needs no --source.
        Legacy LandmarkRecorder JSON has no source label; pass --source camera or
        --source synthetic explicitly. CSV contains baseline and optimized runs in
        one file. JSON includes rows, measured summaries, and explicit unavailable reasons.
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
