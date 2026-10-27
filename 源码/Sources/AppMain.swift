import AppKit
import SwiftUI
import Combine
import ServiceManagement

#if !PANEL_TESTS
@main
struct AtAGlanceMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}
#endif

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, ObservableObject, NSWindowDelegate {
    let store: TaskStore
    let panel: FloatingPanel
    @Published var compact = false
    @Published var activeStatus: TodoStatus = .todo
    @Published var focusRequest = UUID()
    @Published var pinned = false
    private var interactions = Set<String>()
    private var pointerInside = false
    private var restoreCompactOnLeave = false
    private var fadeWork: DispatchWorkItem?
    private var observation: AnyCancellable?
    private var editObservation: AnyCancellable?
    private var pointerTimer: Timer?
    private var expandedSize = NSSize(width: 344, height: 436)
    private let minimumExpandedSize = NSSize(width: 300, height: 260)
    private var resizing = false
    var onSettings: (() -> Void)?
    var onExport: (() -> Void)?
    var onImport: (() -> Void)?

    init(store: TaskStore) {
        self.store = store
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: expandedSize),
                              styleMask: [.borderless, .resizable, .nonactivatingPanel, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init()
        panel.title = "常在待办"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        let container = NSView(frame: NSRect(origin: .zero, size: expandedSize))
        let contentView = NSHostingView(rootView: TodoPanelView(store: store, controller: self))
        // Nest the hosting view so SwiftUI cannot replace the window's resize limits.
        contentView.sizingOptions = []
        contentView.frame = container.bounds
        contentView.autoresizingMask = [.width, .height]
        container.addSubview(contentView)
        panel.contentView = container
        panel.minSize = minimumExpandedSize
        if let frameString = UserDefaults.standard.string(forKey: "panelFrame") {
            let saved = NSRectFromString(frameString)
            expandedSize = NSSize(width: max(minimumExpandedSize.width, saved.width),
                                  height: max(minimumExpandedSize.height, saved.height))
            panel.setFrame(NSRect(origin: saved.origin, size: expandedSize), display: false)
        } else if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - expandedSize.width - 26,
                                         y: screen.visibleFrame.maxY - expandedSize.height - 26))
        }
        clampToScreen()
        applyPreferences()
        observation = store.$preferences.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyPreferences() }
        }
        editObservation = store.$items.combineLatest(store.$categories).dropFirst().sink { [weak self] _ in
            self?.didEdit()
        }
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuOpened), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuClosed), name: NSMenu.didEndTrackingNotification, object: nil)
        show()
        scheduleFade()
    }

    func show(focus: Bool = false) {
        fadeWork?.cancel()
        restoreCompactOnLeave = false
        setCompact(false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        if focus {
            panel.makeKey()
            activeStatus = .todo
            focusRequest = UUID()
        }
        scheduleFade()
    }

    func toggleVisible() {
        if panel.isVisible { panel.orderOut(nil) } else { show() }
    }

    func setInteracting(_ token: String, _ interacting: Bool) {
        if interacting { interactions.insert(token); fadeWork?.cancel(); panel.alphaValue = 1 }
        else { interactions.remove(token); scheduleFade() }
    }

    func togglePin() {
        pinned.toggle()
        if pinned { restoreCompactOnLeave = false; setCompact(false); panel.alphaValue = 1; fadeWork?.cancel() }
        else { scheduleFade() }
    }

    func minimizeToPill() {
        interactions.removeAll()
        panel.makeFirstResponder(nil)
        setCompact(true)
    }

    func didEdit() { restoreCompactOnLeave = false }

    private func checkPointer() {
        guard panel.isVisible else { return }
        updatePointer(inside: panel.frame.contains(NSEvent.mouseLocation))
    }

    func updatePointer(inside: Bool) {
        guard pointerInside != inside else { return }
        pointerInside = inside
        if inside {
            fadeWork?.cancel()
            if compact { restoreCompactOnLeave = true }
            setCompact(false)
            animateOpacity(1)
        } else { scheduleFade() }
    }

    private func scheduleFade() {
        fadeWork?.cancel()
        guard !pointerInside, !pinned, interactions.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.pointerInside, !self.pinned, self.interactions.isEmpty else { return }
            if self.store.preferences.collapseOnLeave || self.restoreCompactOnLeave { self.setCompact(true) }
            self.animateOpacity(self.store.preferences.idleOpacity)
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: work)
    }

    private func animateOpacity(_ opacity: Double) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.28
            panel.animator().alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : opacity
        }
    }

    private func setCompact(_ value: Bool) {
        guard compact != value else { return }
        if value { restoreCompactOnLeave = false }
        resizing = true
        let topRight = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
        compact = value
        let size = value ? NSSize(width: 174, height: 42) : expandedSize
        panel.minSize = value ? size : minimumExpandedSize
        if value { panel.styleMask.remove(.resizable) }
        else { panel.styleMask.insert(.resizable) }
        panel.setFrame(NSRect(x: topRight.x - size.width, y: topRight.y - size.height,
                              width: size.width, height: size.height), display: true)
        resizing = false
    }

    private func applyPreferences() {
        panel.level = store.preferences.alwaysOnTop ? .floating : .normal
        if !store.preferences.collapseOnLeave && compact { setCompact(false) }
        if !pointerInside { scheduleFade() }
    }

    func windowDidResignKey(_ notification: Notification) {
        interactions.remove("input")
        panel.makeFirstResponder(nil)
        scheduleFade()
    }

    func windowDidMove(_ notification: Notification) {
        guard !resizing else { return }
        let frame = NSRect(x: panel.frame.maxX - expandedSize.width,
                           y: panel.frame.maxY - expandedSize.height,
                           width: expandedSize.width, height: expandedSize.height)
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: "panelFrame")
    }

    func windowDidResize(_ notification: Notification) {
        guard !resizing, !compact else { return }
        expandedSize = panel.frame.size
        windowDidMove(notification)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        didEdit()
        setInteracting("resize", true)
    }

    func windowDidEndLiveResize(_ notification: Notification) { setInteracting("resize", false) }

    @objc private func screensChanged() { clampToScreen() }
    @objc private func menuOpened() { setInteracting("menu", true) }
    @objc private func menuClosed() { setInteracting("menu", false) }
    private func clampToScreen() {
        let frame = panel.frame
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: max(visible.minX, min(frame.minX, visible.maxX - frame.width)),
                                     y: max(visible.minY, min(frame.minY, visible.maxY - frame.height))))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: TaskStore!
    private var controller: PanelController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = TaskStore()
        controller = PanelController(store: store)
        controller.onSettings = { [weak self] in self?.openSettings() }
        controller.onExport = { [weak self] in self?.exportData() }
        controller.onImport = { [weak self] in self?.importData() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "常在待办")
            button.image?.isTemplate = true
            button.toolTip = "常在待办 · 点击显示或隐藏，右键打开菜单"
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        setupMainMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            do {
                if let task = try TodoAutomation.parse(url) {
                    store.add(title: task.title, category: task.category, dueDate: task.dueDate)
                    controller.activeStatus = .todo
                    controller.show()
                }
            } catch { store.lastError = error.localizedDescription; controller.show() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.show()
        return true
    }

    private func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "常在待办")
        appMenu.addItem(menuItem("设置…", #selector(openSettings), ","))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("退出常在待办", #selector(quit), "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(menuItem("撤销待办操作", #selector(undo), "z"))
        edit.addItem(.separator())
        for (title, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"),
                                     ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        let editItem = NSMenuItem(); editItem.submenu = edit; main.addItem(editItem)
        let task = NSMenu(title: "待办")
        task.addItem(menuItem("添加待办", #selector(newTask), "n"))
        let taskItem = NSMenuItem(); taskItem.submenu = task; main.addItem(taskItem)
        NSApp.mainMenu = main
    }

    private func menuItem(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp, let button = statusItem.button {
            let menu = NSMenu()
            menu.addItem(menuItem("显示待办", #selector(showPanel)))
            menu.addItem(menuItem("添加待办…", #selector(newTask)))
            let undoItem = menuItem("撤销上一次操作", #selector(undo)); undoItem.isEnabled = store.canUndo
            menu.addItem(undoItem)
            menu.addItem(.separator())
            menu.addItem(menuItem("设置与分类…", #selector(openSettings)))
            menu.addItem(menuItem("导出备份…", #selector(exportData)))
            menu.addItem(menuItem("导入备份…", #selector(importData)))
            menu.addItem(.separator())
            menu.addItem(menuItem("退出常在待办", #selector(quit)))
            NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: button)
        } else { controller.toggleVisible() }
    }

    @objc private func showPanel() { controller.show() }
    @objc private func newTask() { controller.show(focus: true) }
    @objc private func undo() {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
           editor.undoManager?.canUndo == true { editor.undoManager?.undo() }
        else { store.undo() }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSettings() {
        if let window = settingsWindow { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 560),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "常在待办 · 设置"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(store: store,
            onExport: { [weak self] in self?.exportData() }, onImport: { [weak self] in self?.importData() }))
        window.center()
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func exportData() {
        controller.setInteracting("dialog", true)
        defer { controller.setInteracting("dialog", false) }
        let dialog = NSSavePanel()
        dialog.title = "导出待办备份"
        dialog.nameFieldStringValue = "常在待办-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
        dialog.allowedContentTypes = [.json]
        dialog.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        if dialog.runModal() == .OK, let url = dialog.url {
            do { try store.exportData(to: url) } catch { showError(error.localizedDescription) }
        }
    }

    @objc private func importData() {
        controller.setInteracting("dialog", true)
        defer { controller.setInteracting("dialog", false) }
        let dialog = NSOpenPanel()
        dialog.title = "导入待办备份"
        dialog.message = "导入会替换现有任务和分类；导入后可撤销。"
        dialog.prompt = "导入并替换"
        dialog.allowedContentTypes = [.json]
        dialog.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if dialog.runModal() == .OK, let url = dialog.url {
            do { try store.importData(from: url); controller.show() }
            catch { showError(error.localizedDescription) }
        }
    }

    private func showError(_ text: String) {
        let alert = NSAlert(); alert.messageText = "操作未完成"; alert.informativeText = text
        alert.addButton(withTitle: "好"); alert.runModal()
    }
}

struct DragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = HandleView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class HandleView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func accessibilityLabel() -> String? { "拖动待办窗口" }
    }
}

struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .aqua)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
