import AppKit
import CoreGraphics

struct NotchMetrics: Equatable {
    let hasNotch: Bool
    let isSimulated: Bool
    let width: CGFloat
    let height: CGFloat

    static let none = NotchMetrics(hasNotch: false, isSimulated: false, width: 0, height: 0)
}

extension NSScreen {
    var effectiveIslandMetrics: NotchMetrics {
        let topInset = max(safeAreaInsets.top, 0)

        if topInset > 0 {
            let leftRect = auxiliaryTopLeftArea
            let rightRect = auxiliaryTopRightArea
            let leftWidth = leftRect?.width ?? 0
            let rightWidth = rightRect?.width ?? 0
            let inferredWidth = max(0, frame.width - leftWidth - rightWidth)

            let fallbackWidth = min(max(frame.width * 0.145, 180), 240)
            let hasUsableAuxiliaryAreas = leftRect != nil && rightRect != nil
            let inferredLooksReasonable = inferredWidth >= 150 && inferredWidth <= 320
            let resolvedWidth = (hasUsableAuxiliaryAreas && inferredLooksReasonable) ? inferredWidth : fallbackWidth
            let resolvedHeight = max(topInset, 32)

            return NotchMetrics(
                hasNotch: true,
                isSimulated: false,
                width: resolvedWidth,
                height: resolvedHeight
            )
        }

        let simulatedWidth = min(max(frame.width * 0.14, 188), 248)
        let simulatedHeight = min(max(frame.height * 0.026, 30), 38)

        return NotchMetrics(
            hasNotch: true,
            isSimulated: true,
            width: simulatedWidth,
            height: simulatedHeight
        )
    }

    var displayID: NSNumber? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }
}

@MainActor
final class IslandMetricsStore: ObservableObject {
    @Published private(set) var notchMetrics: NotchMetrics = .none

    func update(from screen: NSScreen?) {
        notchMetrics = screen?.effectiveIslandMetrics ?? .none
    }
}
