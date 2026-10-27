import AppKit

@main
struct PanelTests {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suite = "AtAGlancePanelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let primary = WindowGeometry.Screen(frame: NSRect(x: 0, y: 0, width: 1200, height: 900),
                                            visibleFrame: NSRect(x: 64, y: 0, width: 1136, height: 876))
        let left = WindowGeometry.Screen(frame: NSRect(x: -1400, y: -200, width: 1400, height: 1000),
                                         visibleFrame: NSRect(x: -1400, y: -200, width: 1400, height: 976))
        for origin in [NSPoint(x: 64, y: 0), NSPoint(x: 1026, y: 0)] {
            let expanded = NSRect(x: origin.x + 174 - 480, y: origin.y + 42 - 560, width: 480, height: 560)
            precondition(primary.visibleFrame.contains(WindowGeometry.fit(expanded, in: primary.visibleFrame)))
        }
        let spanning = NSRect(x: -900, y: 0, width: 1000, height: 500)
        precondition(WindowGeometry.screen(for: spanning, screens: [primary, left])!.frame == left.frame)
        precondition(WindowGeometry.screen(for: spanning, anchor: NSPoint(x: -1, y: 500), screens: [primary, left])!.frame == left.frame)
        precondition(WindowGeometry.screen(for: NSRect(x: -3000, y: 0, width: 200, height: 200), screens: [primary, left])!.frame == left.frame)
        let tiny = NSRect(x: -200, y: -100, width: 220, height: 180)
        precondition(WindowGeometry.minimum(NSSize(width: 300, height: 260), in: tiny) == tiny.size)
        precondition(WindowGeometry.fit(NSRect(x: 0, y: 0, width: 3000, height: 2000), in: tiny,
                                        minimum: NSSize(width: 300, height: 260)) == tiny)
        var testScreens = [primary]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AtAGlancePanelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TaskStore(directory: directory, seedExamples: false)
        let controller = PanelController(store: store, defaults: defaults, screens: { testScreens })
        controller.panel.orderOut(nil)
        func waitForFade() { RunLoop.main.run(until: Date().addingTimeInterval(1.5)) }
        waitForFade()

        precondition(controller.panel.styleMask.contains(.resizable), "expanded panel supports native resizing")
        precondition(controller.panel.minSize == NSSize(width: 300, height: 260), "expanded panel has a usable minimum size: \(controller.panel.minSize), content minimum: \(controller.panel.contentMinSize)")
        let resized = NSSize(width: 480, height: 560)
        controller.panel.setContentSize(resized)
        precondition(controller.panel.frame.size == resized, "expanded panel accepts a custom size")
        controller.minimizeToPill()
        precondition(controller.panel.frame.size == NSSize(width: 174, height: 42), "custom size does not enlarge the compact pill")
        precondition(!controller.panel.styleMask.contains(.resizable), "compact pill stays fixed in size")
        controller.show()
        controller.panel.orderOut(nil)
        precondition(controller.panel.frame.size == resized && controller.panel.styleMask.contains(.resizable), "expanding restores the custom size and native resize support")
        let restored = PanelController(store: store, defaults: defaults, screens: { testScreens })
        restored.panel.orderOut(nil)
        precondition(restored.panel.frame.size == resized, "custom size survives controller recreation")

        for x in [primary.visibleFrame.minX, primary.visibleFrame.maxX - 174] {
            controller.minimizeToPill()
            controller.panel.setFrameOrigin(NSPoint(x: x, y: primary.visibleFrame.minY))
            controller.show()
            precondition(primary.visibleFrame.contains(controller.panel.frame), "bottom edge expansion stays visible")
            precondition(controller.panel.frame.size == resized, "compact frame does not overwrite normal size")
        }
        defaults.set(NSStringFromRect(NSRect(x: -2500, y: -500, width: 3000, height: 2000)), forKey: "panelFrame")
        let oversized = PanelController(store: store, defaults: defaults, screens: { testScreens })
        precondition(primary.visibleFrame.contains(oversized.panel.frame), "startup shrinks oversized saved frame")
        controller.minimizeToPill()
        testScreens = [WindowGeometry.Screen(frame: tiny, visibleFrame: tiny)]
        oversized.screensChanged()
        precondition(oversized.panel.frame == tiny, "disconnect shrinks an already expanded window")
        controller.screensChanged()
        precondition(tiny.contains(controller.panel.frame), "compact display change stays visible")
        controller.show()
        precondition(controller.panel.frame == tiny && controller.panel.minSize == tiny.size, "small screen overrides default minimum")
        testScreens = [primary]
        controller.screensChanged()
        controller.panel.setContentSize(resized)

        func hoverPill() {
            controller.updatePointer(inside: false)
            controller.minimizeToPill()
            precondition(controller.compact, "manual minimize shows the pill")
            controller.updatePointer(inside: true)
            precondition(!controller.compact, "hover expands the pill")
        }
        func leave() { controller.updatePointer(inside: false); waitForFade() }

        hoverPill()
        leave()
        precondition(controller.compact, "hover without edits returns to the pill with auto-collapse disabled")
        hoverPill()
        leave()
        precondition(controller.compact, "repeated hover still returns to the pill")

        hoverPill()
        controller.setInteracting("menu", true)
        leave()
        precondition(!controller.compact, "open menu prevents collapse")
        controller.setInteracting("menu", false)
        waitForFade()
        precondition(controller.compact, "closing the menu without editing restores the pill")

        hoverPill()
        controller.setInteracting("edit", true)
        leave()
        precondition(!controller.compact, "open editor prevents collapse")
        controller.setInteracting("edit", false)
        waitForFade()
        precondition(controller.compact, "cancelling an unchanged editor restores the pill")

        hoverPill()
        controller.didEdit()
        leave()
        precondition(!controller.compact, "draft edits keep the panel expanded")

        hoverPill()
        controller.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification))
        leave()
        precondition(!controller.compact, "live resize prevents hover collapse")
        controller.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))
        waitForFade()
        precondition(!controller.compact, "deliberate resizing keeps the panel expanded")

        hoverPill()
        store.add(title: "Regression check", category: "work")
        leave()
        precondition(!controller.compact, "task changes keep the panel expanded")

        hoverPill()
        controller.show()
        controller.panel.orderOut(nil)
        leave()
        precondition(!controller.compact, "explicitly opening the panel keeps it expanded")

        controller.updatePointer(inside: true)
        store.preferences.collapseOnLeave = true
        leave()
        precondition(controller.compact, "the existing auto-collapse preference still works after edits")
        print("PASS: geometry boundaries/multiple displays/oversized frames/small-screen minimum, hidden controller startup/display changes, native resizing, size persistence, hover restore, editing/menu/resize protection, and auto-collapse preference")
    }
}
