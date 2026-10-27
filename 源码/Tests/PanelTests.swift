import AppKit

@main
struct PanelTests {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let savedFrame = UserDefaults.standard.object(forKey: "panelFrame")
        UserDefaults.standard.removeObject(forKey: "panelFrame")
        defer { UserDefaults.standard.set(savedFrame, forKey: "panelFrame") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AtAGlancePanelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TaskStore(directory: directory, seedExamples: false)
        let controller = PanelController(store: store)
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
        let restored = PanelController(store: store)
        restored.panel.orderOut(nil)
        precondition(restored.panel.frame.size == resized, "custom size survives controller recreation")

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
        print("PASS: native resizing, size persistence, hover restore, editing/menu/resize protection, and auto-collapse preference")
    }
}
