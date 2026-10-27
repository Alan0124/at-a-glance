import AppKit

@main
struct PanelTests {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AtAGlancePanelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TaskStore(directory: directory, seedExamples: false)
        let controller = PanelController(store: store)
        controller.panel.orderOut(nil)
        func waitForFade() { RunLoop.main.run(until: Date().addingTimeInterval(1.5)) }
        waitForFade()

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
        print("PASS: hover restore, editing/menu protection, explicit open, and auto-collapse preference")
    }
}
