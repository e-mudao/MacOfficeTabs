import AppKit
import OfficeTabsCore

private final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TabButton: NSButton {
    var clicked: (() -> Void)?
    var dropped: ((CGPoint) -> Void)?
    override var acceptsFirstResponder: Bool { false }
    override func mouseDown(with event: NSEvent) {
        let start = event.locationInWindow
        var dragged = false
        highlight(true)
        while let next = NSApp.nextEvent(matching:[.leftMouseDragged,.leftMouseUp],until:.distantFuture,inMode:.eventTracking,dequeue:true) {
            if hypot(next.locationInWindow.x-start.x,next.locationInWindow.y-start.y) > 5 { dragged = true }
            if next.type == .leftMouseUp {
                highlight(false)
                if dragged { dropped?(next.locationInWindow) }
                else if bounds.contains(convert(next.locationInWindow,from:nil)) { clicked?() }
                return
            }
        }
        highlight(false)
    }
    @objc private func accessibleClick() { clicked?() }
    override init(frame: NSRect) {
        super.init(frame:frame); target = self; action = #selector(accessibleClick)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) unavailable") }
}

final class TabPanelController {
    private let panel: NSPanel
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private var orders: [OfficeApp: TabOrder] = [:]
    private var profile: OfficeApp = .word
    private var rendered: [UUID] = []
    private var renderKey = ""
    private var visibilityReason = "notUpdated"
    var activate: ((UUID) -> Void)?
    var close: ((UUID) -> Void)?
    var enabled = true
    var diagnostic: String {
        "panel app=\(profile.name) visible=\(panel.isVisible) reason=\(visibilityReason) frame=\(NSStringFromRect(panel.frame)) activeSpace=\(panel.isOnActiveSpace) key=\(panel.isKeyWindow) main=\(panel.isMainWindow) frontmostOffice=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier == profile.rawValue)"
    }

    init() {
        panel = PassivePanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title = "MacOfficeTabs · Word 标签"
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces,.canJoinAllApplications,.fullScreenAuxiliary,.ignoresCycle]
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.becomesKeyOnlyIfNeeded = true
        let background = NSVisualEffectView(); background.material = .hudWindow; background.blendingMode = .behindWindow
        background.state = .active; background.wantsLayer = true; background.layer?.cornerRadius = 8
        panel.contentView = background
        stack.orientation = .horizontal; stack.spacing = 4; stack.alignment = .centerY
        scroll.documentView = stack; scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .allowed; scroll.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo:background.leadingAnchor,constant:6),
            scroll.trailingAnchor.constraint(equalTo:background.trailingAnchor,constant:-6),
            scroll.topAnchor.constraint(equalTo:background.topAnchor,constant:3),
            scroll.bottomAnchor.constraint(equalTo:background.bottomAnchor,constant:-3)
        ])
    }
    func orderedIDs(_ visible:[UUID]) -> [UUID] {
        var order = orders[profile] ?? TabOrder()
        let result = order.ordered(visible); orders[profile] = order; return result
    }
    func hide(reason:String = "explicitHide") { visibilityReason = reason; panel.orderOut(nil) }
    func update(_ details: [WindowDetails], canControl: Bool, targets: [TabTarget], profile: OfficeApp = .word) {
        self.profile = profile
        panel.title = "MacOfficeTabs · \(profile.name) 标签"
        guard enabled else { hide(reason:"disabled"); return }
        guard canControl else { hide(reason:"scanOrActionUnsafe"); return }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == profile.rawValue else { hide(reason:"officeNotFrontmost"); return }
        guard let focus = details.first(where: { $0.focused }) else { hide(reason:"noStandardFocus"); return }
        guard focus.minimized == false else { hide(reason:"minimizedOrUnknown"); return }
        guard focus.safeForPanel else { hide(reason:"modalOrUnknown"); return }
        guard let ax = focus.frame,let primary = NSScreen.screens.first else { hide(reason:"geometryUnknown"); return }
        let safeScreens = NSScreen.screens.map { screen in
            let visible = screen.visibleFrame
            let top = min(visible.maxY,screen.frame.maxY-screen.safeAreaInsets.top)
            return CGRect(x:visible.minX,y:visible.minY,width:visible.width,height:max(0,top-visible.minY))
        }
        guard let frame = PanelPlacement.frame(windowAX:ax,desktopTop:primary.frame.maxY,visibleScreens:safeScreens) else {
            hide(reason:"noInternalSafeSpace"); return
        }
        var order = orders[profile] ?? TabOrder()
        let ids = order.ordered(targets.map { $0.id })
        orders[profile] = order
        let byID = Dictionary(uniqueKeysWithValues:targets.map { ($0.id,$0) })
        let key = ids.compactMap { byID[$0] }.map { "\($0.id):\($0.title):\($0.focused):\($0.canClose)" }.joined(separator:"|")
        if key != renderKey {
            rendered = ids; renderKey = key
            for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
            var total: CGFloat = 0
            for id in ids {
                guard let detail = byID[id] else { continue }
                let short = String(id.uuidString.prefix(8))
                let title = detail.title
                let button = TabButton(frame:.zero)
                button.title = title + " · " + short
                button.toolTip = title + "\n" + short + (detail.canClose ? " · 拖动调整顺序" : " · 请先点击此标签核验窗口身份，成功后启用 ×")
                button.setAccessibilityLabel("切换到 \(title) · \(short)")
                button.bezelStyle = .rounded; button.font = .systemFont(ofSize:11,weight:detail.focused ? .semibold : .regular)
                button.contentTintColor = detail.focused ? .systemBlue : .labelColor
                button.lineBreakMode = .byTruncatingMiddle
                button.clicked = { [weak self] in self?.activate?(id) }
                button.dropped = { [weak self] point in self?.reorder(id,point:point,details:details,canControl:canControl,targets:targets,profile:profile) }
                let closeButton = NSButton(title:"×",target:nil,action:nil)
                closeButton.isEnabled = detail.canClose
                closeButton.bezelStyle = .inline; closeButton.font = .systemFont(ofSize:16)
                closeButton.setAccessibilityLabel("关闭 \(title) · \(short)")
                closeButton.toolTip = detail.canClose ? "交给 Office 原生关闭；保留保存提示" : "请先点击标签标题核验窗口身份，再使用 ×"
                let handler = CloseHandler { [weak self] in self?.close?(id) }
                closeButton.target = handler; closeButton.action = #selector(CloseHandler.invoke)
                // NSControl targets are weak. Keep the handler with its containing view.
                let item = TabItem(views:[button,closeButton],handler:handler)
                item.orientation = .horizontal; item.spacing = 2
                let width: CGFloat = 196
                button.widthAnchor.constraint(equalToConstant:168).isActive = true
                closeButton.widthAnchor.constraint(equalToConstant:24).isActive = true
                item.widthAnchor.constraint(equalToConstant:width).isActive = true
                stack.addArrangedSubview(item); total += width+4
            }
            stack.frame = NSRect(x:0,y:0,width:max(1,total),height:30)
        }
        visibilityReason = "internalTop"
        panel.setFrame(frame,display:true); panel.orderFrontRegardless()
    }
    private func reorder(_ id:UUID,point:CGPoint,details:[WindowDetails],canControl:Bool,targets:[TabTarget],profile:OfficeApp) {
        guard self.profile == profile else { return }
        let local = stack.convert(point,from:nil)
        let before = zip(rendered,stack.arrangedSubviews).first { $0.0 != id && local.x < $0.1.frame.midX }?.0
        var order = orders[profile] ?? TabOrder()
        order.move(id,before:before); orders[profile] = order
        renderKey = ""; update(details,canControl:canControl,targets:targets,profile:profile)
    }
    func reset() { hide(); orders[profile] = TabOrder(); renderKey = "" }
}
private final class CloseHandler: NSObject {
    private let action: () -> Void
    init(_ action:@escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
}
private final class TabItem: NSStackView {
    let handler:CloseHandler
    init(views:[NSView],handler:CloseHandler) { self.handler = handler; super.init(frame:.zero); for view in views { addArrangedSubview(view) } }
    required init?(coder:NSCoder) { fatalError("init(coder:) unavailable") }
}
