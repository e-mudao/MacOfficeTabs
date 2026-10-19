import Foundation
import CoreGraphics

public struct TabOrder {
    private var ids: [UUID] = []
    public init() {}
    public mutating func ordered(_ visible: [UUID]) -> [UUID] {
        for id in visible where !ids.contains(id) { ids.append(id) }
        let available = Set(visible)
        return ids.filter { available.contains($0) }
    }
    public mutating func move(_ source: UUID, before target: UUID?) {
        guard ids.contains(source), source != target, target == nil || ids.contains(target!) else { return }
        ids.removeAll { $0 == source }
        if let target, let index = ids.firstIndex(of: target) { ids.insert(source, at:index) }
        else { ids.append(source) }
    }
    public mutating func remove(_ id: UUID) { ids.removeAll { $0 == id } }
}

public enum PanelPlacement {
    public static func frame(windowAX: CGRect, desktopTop: CGFloat, visibleScreens: [CGRect]) -> CGRect? {
        guard ControlSafety.validFrame(windowAX), desktopTop.isFinite else { return nil }
        let window = CGRect(x:windowAX.minX,y:desktopTop-windowAX.maxY,width:windowAX.width,height:windowAX.height)
        let screens = visibleScreens.filter(ControlSafety.validFrame)
        guard let screen = screens.max(by: { area($0.intersection(window)) < area($1.intersection(window)) }),
              area(screen.intersection(window)) > 0 else { return nil }
        // One placement rule for normal, maximized and native fullscreen.
        // Restrict the strip to the visible part of its own focus window.
        let visible = screen.intersection(window)
        let width = min(720,visible.width - 32)
        let height: CGFloat = 38, topInset: CGFloat = 40
        guard width >= 180, visible.height >= topInset + height + 8 else { return nil }
        return CGRect(x:visible.midX-width/2,y:visible.maxY-topInset-height,width:width,height:height)
    }
    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : max(0,rect.width)*max(0,rect.height) }
}
