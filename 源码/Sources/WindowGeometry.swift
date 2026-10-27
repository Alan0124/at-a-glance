import Foundation

/// Screen bounds select the display; visible bounds exclude its menu bar and Dock.
enum WindowGeometry {
    struct Screen {
        var frame: CGRect
        var visibleFrame: CGRect
    }

    static func screen(for frame: CGRect, anchor: CGPoint? = nil, screens: [Screen]) -> Screen? {
        guard !screens.isEmpty else { return nil }
        if let anchor, let match = screens.first(where: {
            anchor.x > $0.frame.minX && anchor.x <= $0.frame.maxX &&
            anchor.y > $0.frame.minY && anchor.y <= $0.frame.maxY
        }) { return match }
        func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
        let overlapping = screens.max { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) }!
        if area(overlapping.frame.intersection(frame)) > 0 { return overlapping }
        // A disconnected display may leave the saved frame completely off screen.
        func distance(_ screen: Screen) -> CGFloat {
            let x = max(screen.frame.minX - frame.midX, 0, frame.midX - screen.frame.maxX)
            let y = max(screen.frame.minY - frame.midY, 0, frame.midY - screen.frame.maxY)
            return x * x + y * y
        }
        return screens.min { distance($0) < distance($1) }
    }

    static func minimum(_ preferred: CGSize, in visible: CGRect) -> CGSize {
        CGSize(width: min(preferred.width, visible.width), height: min(preferred.height, visible.height))
    }

    static func fit(_ frame: CGRect, in visible: CGRect, minimum preferred: CGSize = .zero) -> CGRect {
        let minimum = minimum(preferred, in: visible)
        let size = CGSize(width: min(max(frame.width, minimum.width), visible.width),
                          height: min(max(frame.height, minimum.height), visible.height))
        return CGRect(x: max(visible.minX, min(frame.minX, visible.maxX - size.width)),
                      y: max(visible.minY, min(frame.minY, visible.maxY - size.height)),
                      width: size.width, height: size.height)
    }
}
