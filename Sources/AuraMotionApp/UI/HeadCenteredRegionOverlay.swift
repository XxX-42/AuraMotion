#if DEBUG
import SwiftUI
import AuraMotionCore

/// Camera-space visualization only; region decisions are made in AuraMotionCore.
struct HeadCenteredRegionOverlay: View {
    let center: CGPoint
    let focused: FocusedRegion?
    let candidate: FocusedRegion?
    private let config = HeadCenteredRegionConfiguration()

    var body: some View {
        Canvas { context, size in
            let origin = CGPoint(x: center.x * size.width, y: center.y * size.height)
            let unit = min(size.width, size.height)
            func radius(_ value: CGFloat) -> CGFloat { value * unit }
            func render(_ region: FocusedRegion?, color: Color) {
                guard let region else { return }
                let inner: CGFloat, outer: CGFloat
                switch region.radial {
                case .center:
                    let r = radius(config.centerRadius)
                    context.fill(Path(ellipseIn: CGRect(x: origin.x-r, y: origin.y-r, width: 2*r, height: 2*r)), with: .color(color.opacity(0.45)))
                    return
                case .ring1: inner = radius(config.centerRadius); outer = radius(config.ring1OuterRadius)
                case .ring2: inner = radius(config.ring1OuterRadius); outer = radius(config.ring2OuterRadius)
                case .outside: return
                }
                guard let sector = region.sector else { return }
                let angles: [AngularSector: Double] = [.north: -90, .northEast: -45, .east: 0, .southEast: 45, .south: 90, .southWest: 135, .west: 180, .northWest: 225]
                let a = angles[sector, default: 0] * .pi / 180
                let half = Double.pi / 8
                func pt(_ r: CGFloat, _ angle: Double) -> CGPoint { CGPoint(x: origin.x + r * cos(angle), y: origin.y + r * sin(angle)) }
                var path = Path(); path.move(to: pt(inner, a-half))
                for i in 0...16 { path.addLine(to: pt(outer, a-half + 2*half*Double(i)/16)) }
                for i in (0...16).reversed() { path.addLine(to: pt(inner, a-half + 2*half*Double(i)/16)) }
                path.closeSubpath()
                context.fill(path, with: .color(color.opacity(0.4)))
            }
            render(focused, color: .cyan)
            render(candidate, color: .yellow)
            for r in [config.centerRadius, config.ring1OuterRadius, config.ring2OuterRadius] {
                let d = radius(r)
                context.stroke(Path(ellipseIn: CGRect(x: origin.x-d, y: origin.y-d, width: d*2, height: d*2)), with: .color(.white.opacity(0.55)), lineWidth: 1)
            }
            for i in 0..<8 {
                let angle = (Double(i) * 45 - 22.5) * .pi / 180
                var line = Path()
                line.move(to: CGPoint(x: origin.x + radius(config.centerRadius)*cos(angle), y: origin.y + radius(config.centerRadius)*sin(angle)))
                line.addLine(to: CGPoint(x: origin.x + radius(config.ring2OuterRadius)*cos(angle), y: origin.y + radius(config.ring2OuterRadius)*sin(angle)))
                context.stroke(line, with: .color(.white.opacity(0.4)), lineWidth: 1)
            }
            let directions = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
            for i in 0..<8 {
                let angle = Double(i) * .pi / 4
                let r = radius(config.ring2OuterRadius) + 10
                let point = CGPoint(x: origin.x + r*cos(angle), y: origin.y + r*sin(angle))
                context.draw(Text(directions[i]).font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.85)), at: point)
            }
            context.fill(Path(ellipseIn: CGRect(x: origin.x-3, y: origin.y-3, width: 6, height: 6)), with: .color(.white))
        }
    }
}
#endif
