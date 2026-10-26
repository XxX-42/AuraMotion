import Foundation
import CoreGraphics

private enum OneEuroFilterBounds {
    static func minCutoff(_ value: Double, fallback: Double) -> Double {
        bounded(value, range: 0.1...10, fallback: fallback)
    }

    static func beta(_ value: Double, fallback: Double) -> Double {
        // Keep the wider range supported by existing non-cursor One Euro users
        // (for example the command menu filter); cursor settings are bounded by
        // CursorFilterConfiguration before they reach this filter.
        bounded(value, range: 0...10, fallback: fallback)
    }

    static func dCutoff(_ value: Double, fallback: Double) -> Double {
        bounded(value, range: 0.1...10, fallback: fallback)
    }

    private static func bounded(_ value: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

/// Low-pass filter with dynamic cutoff frequency based on velocity.
/// Based on Casiez, Roussel, Vogel (CHI 2012): "1€ Filter: A Simple Speed-based Low-pass Filter for Noisy Input in HCI"
public final class OneEuroFilter1D: @unchecked Sendable {
    public var minCutoff: Double {
        didSet { minCutoff = OneEuroFilterBounds.minCutoff(minCutoff, fallback: 1.0) }
    }
    public var beta: Double {
        didSet { beta = OneEuroFilterBounds.beta(beta, fallback: 0.007) }
    }
    public var dCutoff: Double {
        didSet { dCutoff = OneEuroFilterBounds.dCutoff(dCutoff, fallback: 1.0) }
    }

    private var xPrev: Double?
    private var rawPrev: Double?
    private var dxPrev: Double = 0.0
    private var tPrev: TimeInterval?

    public init(minCutoff: Double = 1.0, beta: Double = 0.007, dCutoff: Double = 1.0) {
        self.minCutoff = OneEuroFilterBounds.minCutoff(minCutoff, fallback: 1.0)
        self.beta = OneEuroFilterBounds.beta(beta, fallback: 0.007)
        self.dCutoff = OneEuroFilterBounds.dCutoff(dCutoff, fallback: 1.0)
    }

    /// Changes tuning without discarding the current signal and derivative history.
    func configure(minCutoff: Double, beta: Double, dCutoff: Double) {
        self.minCutoff = OneEuroFilterBounds.minCutoff(minCutoff, fallback: 1.0)
        self.beta = OneEuroFilterBounds.beta(beta, fallback: 0.007)
        self.dCutoff = OneEuroFilterBounds.dCutoff(dCutoff, fallback: 1.0)
    }

    public func reset() {
        xPrev = nil
        rawPrev = nil
        dxPrev = 0.0
        tPrev = nil
    }

    private func alpha(rate: Double, cutoff: Double) -> Double {
        guard rate.isFinite, rate > 0, cutoff.isFinite, cutoff > 0 else { return 1.0 }
        let tau = 1.0 / (2.0 * Double.pi * cutoff)
        let te = 1.0 / rate
        let value = 1.0 / (1.0 + tau / te)
        return value.isFinite ? min(1.0, max(0.0, value)) : 1.0
    }

    public func filter(x: Double, timestamp: TimeInterval) -> Double {
        guard x.isFinite, timestamp.isFinite else { return xPrev ?? 0 }
        guard let prevX = xPrev, let prevT = tPrev else {
            xPrev = x
            rawPrev = x
            tPrev = timestamp
            return x
        }

        guard timestamp > prevT else { return prevX }
        if timestamp - prevT > 0.25 {
            reset()
            return filter(x: x, timestamp: timestamp)
        }
        let dt = max(timestamp - prevT, 1e-4)
        let rate = 1.0 / dt

        // Estimate derivative (velocity) with low-pass filtering
        let dx = (x - (rawPrev ?? x)) * rate
        guard dx.isFinite else { return prevX }
        let aD = alpha(rate: rate, cutoff: dCutoff)
        let dxHat = aD * dx + (1.0 - aD) * dxPrev
        guard dxHat.isFinite else { return prevX }

        // Dynamic cutoff based on speed
        let cutoff = minCutoff + beta * abs(dxHat)
        let a = alpha(rate: rate, cutoff: cutoff)
        let xHat = a * x + (1.0 - a) * prevX
        guard xHat.isFinite else { return prevX }

        tPrev = timestamp
        rawPrev = x
        dxPrev = dxHat
        xPrev = xHat

        return xHat
    }
}

public final class OneEuroFilter2D: @unchecked Sendable {
    private let filterX: OneEuroFilter1D
    private let filterY: OneEuroFilter1D
    private var lastPoint: CGPoint?

    public init(minCutoff: Double = 0.5, beta: Double = 0.008, dCutoff: Double = 1.0) {
        let safeMinCutoff = OneEuroFilterBounds.minCutoff(minCutoff, fallback: 0.5)
        let safeBeta = OneEuroFilterBounds.beta(beta, fallback: 0.008)
        let safeDCutoff = OneEuroFilterBounds.dCutoff(dCutoff, fallback: 1.0)
        self.filterX = OneEuroFilter1D(minCutoff: safeMinCutoff, beta: safeBeta, dCutoff: safeDCutoff)
        self.filterY = OneEuroFilter1D(minCutoff: safeMinCutoff, beta: safeBeta, dCutoff: safeDCutoff)
    }

    public var minCutoff: Double {
        get { filterX.minCutoff }
        set {
            filterX.minCutoff = newValue
            filterY.minCutoff = newValue
        }
    }

    public var beta: Double {
        get { filterX.beta }
        set {
            filterX.beta = newValue
            filterY.beta = newValue
        }
    }

    public var dCutoff: Double {
        get { filterX.dCutoff }
        set {
            filterX.dCutoff = newValue
            filterY.dCutoff = newValue
        }
    }

    /// Applies new tuning to both axes while preserving the current filter state.
    public func configure(minCutoff: Double, beta: Double, dCutoff: Double) {
        let safeMinCutoff = OneEuroFilterBounds.minCutoff(minCutoff, fallback: 0.5)
        let safeBeta = OneEuroFilterBounds.beta(beta, fallback: 0.008)
        let safeDCutoff = OneEuroFilterBounds.dCutoff(dCutoff, fallback: 1.0)
        filterX.configure(minCutoff: safeMinCutoff, beta: safeBeta, dCutoff: safeDCutoff)
        filterY.configure(minCutoff: safeMinCutoff, beta: safeBeta, dCutoff: safeDCutoff)
    }

    public func reset() {
        filterX.reset()
        filterY.reset()
        lastPoint = nil
    }

    public func filter(point: CGPoint, timestamp: TimeInterval) -> CGPoint {
        guard point.x.isFinite, point.y.isFinite, timestamp.isFinite else {
            return lastPoint ?? .zero
        }
        let fx = filterX.filter(x: Double(point.x), timestamp: timestamp)
        let fy = filterY.filter(x: Double(point.y), timestamp: timestamp)
        guard fx.isFinite, fy.isFinite else { return lastPoint ?? .zero }
        let result = CGPoint(x: fx, y: fy)
        lastPoint = result
        return result
    }
}
