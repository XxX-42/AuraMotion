#if DEBUG
import Foundation
import CoreImage
import CoreMedia
import Darwin

/// Optional debug-only face inference. At most one frame is retained in flight.
public final class DebugFaceWorker: @unchecked Sendable {
    public static let shared = DebugFaceWorker()
    public static let notification = Notification.Name("AuraMotionDebugFaceUpdated")
    private let queue = DispatchQueue(label: "com.auramotion.debug.face", qos: .utility)
    private let lock = NSLock()
    private var enabled = false
    private var busy = false
    private var generation = 0
    private var lastFrame = 0.0
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private let context = CIContext()
    private var resultTimes: [TimeInterval] = []

    public func setEnabled(_ value: Bool) {
        lock.lock()
        enabled = value
        generation += 1
        lock.unlock()
        if !value {
            // A timeout on the worker queue bounds how long shutdown may wait.
            queue.async { [self] in stop() }
            publish([], status: "Off")
        }
    }

    public func submit(_ carrier: SampleCarrier) {
        lock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        guard enabled, !busy, now >= lastFrame else { lock.unlock(); return }
        busy = true
        lastFrame = now
        let token = generation
        lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); busy = false; lock.unlock() }
            lock.lock(); let valid = enabled && generation == token; lock.unlock()
            guard valid, let buffer = CMSampleBufferGetImageBuffer(carrier.buffer) else { return }
            do {
                try startIfNeeded()
                let image = CIImage(cvPixelBuffer: buffer)
                let scale = min(1, 320 / max(image.extent.width, image.extent.height))
                let width = max(1, Int((image.extent.width * scale).rounded(.down)))
                let height = max(1, Int((image.extent.height * scale).rounded(.down)))
                let resized = image.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / image.extent.width, y: CGFloat(height) / image.extent.height))
                var data = Data(count: 8 + width * height * 4)
                data.withUnsafeMutableBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    var w = UInt32(width).bigEndian
                    var h = UInt32(height).bigEndian
                    memcpy(base, &w, 4)
                    memcpy(base.advanced(by: 4), &h, 4)
                    context.render(resized, toBitmap: base.advanced(by: 8), rowBytes: width * 4,
                                   bounds: CGRect(x: 0, y: 0, width: width, height: height),
                                   format: .BGRA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                }
                guard let input, let output else { throw FaceError.failed }
                try writeFrame(data, to: input.fileDescriptor)
                var result = Data()
                let fd = output.fileDescriptor
                let deadline = Date().addingTimeInterval(8)
                while Date() < deadline {
                    var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                    let remaining = max(1, Int32(deadline.timeIntervalSinceNow * 1000))
                    guard poll(&p, 1, remaining) > 0, (p.revents & Int16(POLLIN)) != 0 else { throw FaceError.failed }
                    var chunk = [UInt8](repeating: 0, count: 65_536)
                    let count = Darwin.read(fd, &chunk, chunk.count)
                    guard count > 0 else { throw FaceError.failed }
                    let bytes = chunk.prefix(count)
                    if let newline = bytes.firstIndex(of: 10) {
                        result.append(contentsOf: bytes[..<newline])
                        break
                    }
                    result.append(contentsOf: bytes)
                    if result.count > 100_000 { throw FaceError.failed }
                }
                let points = try JSONDecoder().decode([[Double]].self, from: result)
                lock.lock(); let stillEnabled = enabled && generation == token; lock.unlock()
                if stillEnabled {
                    let now = ProcessInfo.processInfo.systemUptime
                    resultTimes.append(now)
                    resultTimes.removeAll { now - $0 > 2 }
                    let fps: Double? = resultTimes.count >= 2 && now > resultTimes[0]
                        ? Double(resultTimes.count - 1) / (now - resultTimes[0]) : nil
                    publish(points, status: points.isEmpty ? "No face" : "Active", fps: fps)
                }
            } catch {
                stop()
                lock.lock(); lastFrame = ProcessInfo.processInfo.systemUptime + 4; lock.unlock()
                lock.lock(); let stillEnabled = enabled && generation == token; lock.unlock()
                if stillEnabled { publish([], status: "Unavailable") }
            }
        }
    }

    private func writeFrame(_ data: Data, to fd: Int32) throws {
        let deadline = Date().addingTimeInterval(8)
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { throw FaceError.failed }
            var offset = 0
            while offset < raw.count {
                let left = deadline.timeIntervalSinceNow
                guard left > 0 else { throw FaceError.failed }
                var p = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                guard poll(&p, 1, max(1, Int32(left * 1000))) > 0,
                      (p.revents & Int16(POLLOUT)) != 0 else { throw FaceError.failed }
                let written = Darwin.send(fd, base.advanced(by: offset), raw.count - offset, 0)
                if written > 0 { offset += written }
                else if written < 0 && (errno == EAGAIN || errno == EINTR) { continue }
                else { throw FaceError.failed }
            }
        }
    }
    private enum FaceError: Error { case failed }
    private func startIfNeeded() throws {
        if let process, process.isRunning { return }
        stop()
        let env = ProcessInfo.processInfo.environment
        guard let python = env["AURAMOTION_FACE_PYTHON"], let script = env["AURAMOTION_FACE_SCRIPT"], let model = env["AURAMOTION_FACE_MODEL"] else { throw FaceError.failed }
        var sockets: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else { throw FaceError.failed }
        _ = fcntl(sockets[0], F_SETFL, O_NONBLOCK)
        var yes: Int32 = 1
        _ = setsockopt(sockets[0], SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        let parent = FileHandle(fileDescriptor: sockets[0], closeOnDealloc: true)
        let child = FileHandle(fileDescriptor: sockets[1], closeOnDealloc: true)
        let resultPipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: python)
        task.arguments = [script, model]
        task.standardInput = child
        task.standardOutput = resultPipe
        task.standardError = FileHandle.standardError
        do { try task.run() } catch { try? parent.close(); try? child.close(); throw error }
        try? child.close()
        self.process = task
        self.input = parent
        self.output = resultPipe.fileHandleForReading
    }
    private func stop() {
        resultTimes.removeAll()
        try? input?.close(); try? output?.close()
        if let process, process.isRunning { process.terminate() }
        input = nil; output = nil; process = nil
    }
    private func publish(_ points: [[Double]], status: String, fps: Double? = nil) {
        DispatchQueue.main.async {
            var info: [String: Any] = ["points": points, "status": status]
            if let fps { info["fps"] = fps }
            NotificationCenter.default.post(name: Self.notification, object: nil, userInfo: info)
        }
    }
}
#endif
