#if DEBUG
import Foundation
import CoreImage
import CoreMedia
import Darwin

/// Opt-in separate process for the sibling gaze_estimation project. It receives
/// the existing capture frames and never opens a second camera or posts input.
public final class ExperimentalGazeEstimationWorker: @unchecked Sendable {
    public static let shared = ExperimentalGazeEstimationWorker()
    public static let notification = Notification.Name("AuraMotionExperimentalGazeEstimation")
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.auramotion.gaze-estimation", qos: .utility)
    private let context = CIContext()
    private var enabled = false, busy = false
    private var generation: UInt64 = 0
    private var retryAfter = 0.0
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var times: [TimeInterval] = []

    public func setEnabled(_ value: Bool) {
        lock.lock(); enabled = value; generation &+= 1; retryAfter = 0; lock.unlock()
        if !value { queue.async { [self] in stop() }; publish(nil, status: "Off", fps: nil) }
    }
    public func submit(_ carrier: SampleCarrier) {
        lock.lock()
        guard enabled, !busy, ProcessInfo.processInfo.systemUptime >= retryAfter else { lock.unlock(); return }
        busy = true; let token = generation; lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); busy = false; lock.unlock() }
            lock.lock(); let active = enabled && generation == token; lock.unlock()
            guard active, let pixel = CMSampleBufferGetImageBuffer(carrier.buffer) else { return }
            do {
                try startIfNeeded()
                let image = CIImage(cvPixelBuffer: pixel)
                let scale = min(1, 640 / max(image.extent.width, image.extent.height))
                let width = max(1, Int((image.extent.width * scale).rounded(.down)))
                let height = max(1, Int((image.extent.height * scale).rounded(.down)))
                let resized = image.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / image.extent.width, y: CGFloat(height) / image.extent.height))
                var bytes = Data(count: 24 + width * height * 4)
                bytes.withUnsafeMutableBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    var id = carrier.frameID.bigEndian, ts = carrier.hostPresentationTime.bitPattern.bigEndian
                    var w = UInt32(width).bigEndian, h = UInt32(height).bigEndian
                    memcpy(base, &id, 8); memcpy(base.advanced(by: 8), &ts, 8)
                    memcpy(base.advanced(by: 16), &w, 4); memcpy(base.advanced(by: 20), &h, 4)
                    context.render(resized, toBitmap: base.advanced(by: 24), rowBytes: width * 4,
                                   bounds: CGRect(x: 0, y: 0, width: width, height: height),
                                   format: .BGRA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                }
                guard let input, let output else { throw Failure.unavailable }
                try send(bytes, fd: input.fileDescriptor)
                let response = try readResponse(fd: output.fileDescriptor)
                guard response.frameID == carrier.frameID, response.hostTime == carrier.hostPresentationTime else { throw Failure.unavailable }
                lock.lock(); let valid = enabled && token == generation; lock.unlock()
                guard valid else { return }
                let now = ProcessInfo.processInfo.systemUptime
                times.append(now); times.removeAll { now - $0 > 2 }
                let fps = times.count >= 2 && now > times[0] ? Double(times.count - 1) / (now - times[0]) : nil
                publish(response, status: response.phase, fps: fps)
            } catch {
                NSLog("gaze_estimation debug worker failed: %@", String(describing: error))
                stop()
                lock.lock()
                let valid = enabled && token == generation
                if valid { retryAfter = ProcessInfo.processInfo.systemUptime + 4 }
                lock.unlock()
                if valid { publish(nil, status: "Unavailable", fps: nil) }
            }
        }
    }
    private enum Failure: Error { case unavailable }
    private struct Response: Decodable, Sendable {
        let frameID: UInt64
        let hostTime: Double
        let phase: String
        let modelLoaded: Bool
        let modelSignature: String?
        let leftPatch: String?
        let rightPatch: String?
        let gaze: [Double]?
        let angles: [Double]?
        let eyeCenter: [Double]?
        let eyeRotation: [Double]?
        let screenGeometry: [Double]?
        let reason: String
    }
    private func startIfNeeded() throws {
        if let process, process.isRunning { return }
        stop()
        let env = ProcessInfo.processInfo.environment
        guard let source = env["AURAMOTION_FACE_SCRIPT"] else { throw Failure.unavailable }
        let project = URL(fileURLWithPath: source).deletingLastPathComponent().deletingLastPathComponent()
        let repo = env["AURAMOTION_GAZE_ESTIMATION_DIR"].map { URL(fileURLWithPath: $0) } ?? project.deletingLastPathComponent().appendingPathComponent("gaze_estimation")
        let python = repo.appendingPathComponent(".venv/bin/python")
        let adapter = project.appendingPathComponent("scripts/gaze_estimation_bridge.py")
        guard FileManager.default.isExecutableFile(atPath: python.path), FileManager.default.fileExists(atPath: adapter.path) else { throw Failure.unavailable }
        var sockets: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else { throw Failure.unavailable }
        _ = fcntl(sockets[0], F_SETFL, O_NONBLOCK)
        var yes: Int32 = 1
        _ = setsockopt(sockets[0], SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        let parent = FileHandle(fileDescriptor: sockets[0], closeOnDealloc: true)
        let child = FileHandle(fileDescriptor: sockets[1], closeOnDealloc: true)
        let pipe = Pipe(), task = Process()
        task.executableURL = python; task.arguments = [adapter.path]
        task.currentDirectoryURL = repo
        var childEnvironment = env; childEnvironment["AURAMOTION_GAZE_ESTIMATION_DIR"] = repo.path
        let override = project.appendingPathComponent("build/gaze-estimation-mp-override")
        guard FileManager.default.fileExists(atPath: override.appendingPathComponent("mediapipe").path) else {
            try? parent.close(); try? child.close(); throw Failure.unavailable
        }
        childEnvironment["PYTHONPATH"] = override.path + (env["PYTHONPATH"].map { ":" + $0 } ?? "")
        task.environment = childEnvironment
        task.standardInput = child; task.standardOutput = pipe; task.standardError = FileHandle.standardError
        do { try task.run() } catch { try? parent.close(); try? child.close(); throw error }
        try? child.close(); process = task; input = parent; output = pipe.fileHandleForReading
    }
    private func send(_ data: Data, fd: Int32) throws {
        let deadline = Date().addingTimeInterval(15)
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { throw Failure.unavailable }
            var offset = 0
            while offset < raw.count {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { throw Failure.unavailable }
                var poller = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                guard poll(&poller, 1, max(1, Int32(remaining * 1000))) > 0, (poller.revents & Int16(POLLOUT)) != 0 else { throw Failure.unavailable }
                let count = Darwin.send(fd, base.advanced(by: offset), raw.count - offset, 0)
                if count > 0 { offset += count } else if count < 0 && (errno == EAGAIN || errno == EINTR) { continue } else { throw Failure.unavailable }
            }
        }
    }
    private func readResponse(fd: Int32) throws -> Response {
        let deadline = Date().addingTimeInterval(15)
        var data = Data()
        while Date() < deadline {
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, max(1, Int32(deadline.timeIntervalSinceNow * 1000))) > 0, (poller.revents & Int16(POLLIN)) != 0 else { throw Failure.unavailable }
            var bytes = [UInt8](repeating: 0, count: 65536)
            let count = Darwin.read(fd, &bytes, bytes.count)
            guard count > 0 else { throw Failure.unavailable }
            let chunk = bytes.prefix(count)
            if let newline = chunk.firstIndex(of: 10) {
                data.append(contentsOf: chunk[..<newline]); return try JSONDecoder().decode(Response.self, from: data)
            }
            data.append(contentsOf: chunk)
            guard data.count < 100_000 else { throw Failure.unavailable }
        }
        throw Failure.unavailable
    }
    private func stop() {
        times.removeAll(); try? input?.close(); try? output?.close()
        if let process, process.isRunning { process.terminate() }
        process = nil; input = nil; output = nil
    }
    private func publish(_ response: Response?, status: String, fps: Double?) {
        DispatchQueue.main.async {
            var info: [String: Any] = ["status": status]
            if let response {
                info["frameID"] = response.frameID
                info["hostTime"] = response.hostTime
                info["modelLoaded"] = response.modelLoaded
                if let signature = response.modelSignature { info["modelSignature"] = signature }
                info["reason"] = response.reason
                if let l = response.leftPatch { info["leftPatch"] = l }
                if let r = response.rightPatch { info["rightPatch"] = r }
                if let gaze = response.gaze, gaze.count == 2, gaze.allSatisfy(\.isFinite) { info["gaze"] = gaze }
                if let angles = response.angles, angles.count == 2, angles.allSatisfy(\.isFinite) { info["angles"] = angles }
                if let eye = response.eyeCenter, eye.count == 3, eye.allSatisfy(\.isFinite) { info["eyeCenter"] = eye }
                if let rotation = response.eyeRotation, rotation.count == 9, rotation.allSatisfy(\.isFinite) { info["eyeRotation"] = rotation }
                if let geometry = response.screenGeometry, geometry.count == 4, geometry.allSatisfy(\.isFinite) { info["screenGeometry"] = geometry }
            }
            if let fps { info["fps"] = fps }
            NotificationCenter.default.post(name: Self.notification, object: nil, userInfo: info)
        }
    }
}
#endif
