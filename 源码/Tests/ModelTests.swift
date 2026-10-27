import Foundation

@main
struct ModelTests {
    @MainActor static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("AtAGlanceTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ reason: String) {
            assertions += 1
            guard condition() else { fatalError("FAILED: \(reason)") }
        }
        let directory = root.appendingPathComponent("live")
        let store = TaskStore(directory: directory, seedExamples: false)
        expect(store.items.isEmpty, "isolated empty install")
        expect(store.categories == ["work", "life", "content", "study"], "video category defaults")
        store.add(title: " \n ", category: "work")
        expect(store.items.isEmpty && !store.canUndo, "empty quick input does not create task or undo")
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        store.add(title: "  Finish design \n", category: "work", dueDate: due)
        expect(store.items[0].title == "Finish design", "trim input")
        expect(store.items[0].dueDate == due, "retain due date")
        let first = store.items[0].id
        store.add(title: "Second", category: "work")

        let ordered = TaskStore(directory: root.appendingPathComponent("sorting"), seedExamples: false)
        let day = Calendar.current.startOfDay(for: due)
        ordered.add(title: "No date, older", category: "work")
        ordered.add(title: "Later", category: "work", dueDate: day.addingTimeInterval(172_800))
        ordered.add(title: "Same day, older", category: "work", dueDate: day.addingTimeInterval(64_800))
        ordered.add(title: "Earlier", category: "work", dueDate: day.addingTimeInterval(-86_400))
        ordered.add(title: "Same day, newer", category: "work", dueDate: day.addingTimeInterval(28_800))
        ordered.add(title: "No date, newer", category: "work")
        let originalOrder = ordered.items
        expect(ordered.sortedItems(for: .todo).map(\.title) == ["Earlier", "Same day, older", "Same day, newer", "Later", "No date, older", "No date, newer"], "deadline ascending, same-day creation order, undated tasks last")
        expect(ordered.items == originalOrder, "display sorting does not mutate stored order")
        expect(ordered.sortedItems(for: .completed).isEmpty, "sorting respects the status filter")
        var rescheduled = ordered.items[1]
        rescheduled.dueDate = day.addingTimeInterval(-172_800)
        ordered.update(rescheduled)
        expect(ordered.sortedItems(for: .todo).first?.id == rescheduled.id, "deadline edit immediately changes display order")
        ordered.undo()
        expect(ordered.sortedItems(for: .todo).first?.title == "Earlier", "undo restores deadline order")
        ordered.setStatus(rescheduled.id, .completed)
        expect(ordered.sortedItems(for: .completed).map(\.id) == [rescheduled.id] && ordered.sortedItems(for: .todo).count == 5, "status changes keep sorted lists separate")
        let reordered = TaskStore(directory: ordered.directory, seedExamples: false)
        expect(reordered.sortedItems(for: .todo) == ordered.sortedItems(for: .todo), "deadline sorting survives relaunch")

        for status in TodoStatus.allCases {
            store.setStatus(first, status)
            expect(store.items.first(where: { $0.id == first })?.status == status, "status \(status)")
        }
        store.undo()
        expect(store.items.first(where: { $0.id == first })?.status == .completed, "undo status")
        var edited = store.items.first(where: { $0.id == first })!
        edited.title = "Updated"
        edited.category = "new"
        edited.dueDate = nil
        store.update(edited)
        expect(store.categories.contains("new") && store.items[0].title == "Updated", "edit and new category")
        store.renameCategory("new", to: "projects")
        expect(store.items[0].category == "projects", "rename keeps task linked")
        store.deleteCategory("projects")
        expect(store.items[0].category == "work", "delete category migrates task")
        store.undo()
        expect(store.items[0].category == "projects" && store.categories.contains("projects"), "undo category deletion restores both")
        store.delete(first)
        expect(!store.items.contains(where: { $0.id == first }), "delete task")
        store.undo()
        expect(store.items.contains(where: { $0.id == first }), "undo delete")
        store.preferences.idleOpacity = 0.5
        store.preferences.alwaysOnTop = false
        let reopened = TaskStore(directory: directory, seedExamples: false)
        expect(reopened.items == store.items, "save and relaunch all task data")
        expect(reopened.categories == store.categories && reopened.preferences == store.preferences, "save and relaunch preferences/categories")
        let export = root.appendingPathComponent("export.json")
        try store.exportData(to: export)
        let imported = TaskStore(directory: root.appendingPathComponent("imported"), seedExamples: false)
        imported.add(title: "Keep until import", category: "life")
        try imported.importData(from: export)
        expect(imported.items == store.items, "JSON round trip")
        expect(imported.preferences.alwaysOnTop, "import does not alter machine preference")
        imported.undo()
        expect(imported.items.count == 1 && imported.items[0].title == "Keep until import", "undo replaces import atomically")
        let bad = root.appendingPathComponent("invalid.json")
        try Data("{invalid}".utf8).write(to: bad)
        let unchanged = imported.items
        do { try imported.importData(from: bad); fatalError("Invalid import accepted") } catch {}
        expect(imported.items == unchanged, "malformed import preserves current data")
        var raw = try JSONSerialization.jsonObject(with: Data(contentsOf: export)) as! [String: Any]
        raw["categories"] = ["work", "work"]
        try JSONSerialization.data(withJSONObject: raw).write(to: bad)
        do { try imported.importData(from: bad); fatalError("Duplicate category accepted") } catch {}
        expect(imported.items == unchanged, "validation does not partially mutate")
        raw = try JSONSerialization.jsonObject(with: Data(contentsOf: export)) as! [String: Any]
        raw["categories"] = ["absent"]
        try JSONSerialization.data(withJSONObject: raw).write(to: bad)
        do { try imported.importData(from: bad); fatalError("Missing category accepted") } catch {}
        let corruptDirectory = root.appendingPathComponent("corrupt")
        try fm.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        let bytes = Data("precious unreadable user bytes".utf8)
        try bytes.write(to: corruptDirectory.appendingPathComponent("tasks.json"))
        let recovered = TaskStore(directory: corruptDirectory)
        expect(recovered.items.isEmpty && recovered.lastError != nil, "corrupt file does not silently seed samples")
        let preserved = try fm.contentsOfDirectory(at: corruptDirectory, includingPropertiesForKeys: nil).first(where: { $0.lastPathComponent.hasPrefix("tasks.unreadable-") })!
        let preservedBytes = try Data(contentsOf: preserved)
        expect(preservedBytes == bytes, "corrupt original preserved byte for byte")
        recovered.add(title: "Recovered", category: "work")
        expect(TaskStore(directory: corruptDirectory).items.count == 1, "recover and persist fresh valid document")
        let preservedAfterSave = try Data(contentsOf: preserved)
        expect(preservedAfterSave == bytes, "later saves preserve corrupt original")
        let seeded = TaskStore(directory: root.appendingPathComponent("seeded"))
        expect(seeded.items.count == 3, "three tutorial tasks once")
        seeded.delete(seeded.items[0].id)
        expect(TaskStore(directory: seeded.directory).items.count == 2, "tutorial never reseeds deleted entries")

        // Write limits and read limits must be identical: rejected edits are atomic and undo-free.
        let limitsDirectory = root.appendingPathComponent("limits")
        let limits = TaskStore(directory: limitsDirectory, seedExamples: false)
        let maximumTitle = String(repeating: "汉", count: 10_000)
        let oversizedTitle = maximumTitle + "字"
        let maximumCategory = String(repeating: "类", count: 100)
        let oversizedCategory = maximumCategory + "别"
        limits.add(title: maximumTitle, category: maximumCategory)
        expect(limits.items.first?.title == maximumTitle && limits.categories.contains(maximumCategory), "exact Chinese title/category limits accepted without truncation")
        let cleanLimits = TaskStore(directory: limitsDirectory, seedExamples: false)
        expect(cleanLimits.lastError == nil && cleanLimits.items == limits.items, "max title/category survives relaunch intact")
        expect(!cleanLimits.add(title: oversizedTitle, category: "work"), "rejected add returns false")
        var returnValueEdit = cleanLimits.items[0]
        returnValueEdit.title = oversizedTitle
        expect(!cleanLimits.update(returnValueEdit), "rejected update returns false")
        expect(cleanLimits.update(cleanLimits.items[0]), "unchanged update returns true without undo")
        expect(!cleanLimits.addCategory(oversizedCategory), "rejected category add returns false")
        expect(!cleanLimits.renameCategory("work", to: oversizedCategory), "rejected category rename returns false")
        expect(cleanLimits.addCategory("work") && cleanLimits.renameCategory("work", to: "work") && !cleanLimits.canUndo, "idempotent category edits succeed without undo history")

        func unchangedAfterRejection(_ subject: TaskStore, _ reason: String, _ action: () -> Void) throws {
            let beforeItems = subject.items
            let beforeCategories = subject.categories
            let beforeBytes = try Data(contentsOf: subject.dataFileURL)
            let beforeUndo = subject.canUndo
            subject.lastError = nil
            action()
            expect(subject.lastError != nil, reason + " reports Chinese validation error")
            expect(subject.items == beforeItems && subject.categories == beforeCategories, reason + " does not partially mutate")
            expect(subject.canUndo == beforeUndo, reason + " does not add undo entry")
            let afterBytes = try Data(contentsOf: subject.dataFileURL)
            expect(afterBytes == beforeBytes, reason + " leaves persisted bytes unchanged")
            let afterReopen = TaskStore(directory: subject.directory, seedExamples: false)
            expect(afterReopen.lastError == nil && afterReopen.items == beforeItems && afterReopen.categories == beforeCategories, reason + " survives relaunch")
        }
        try unchangedAfterRejection(cleanLimits, "oversized add title") {
            cleanLimits.add(title: oversizedTitle, category: "must-not-be-created")
        }
        try unchangedAfterRejection(cleanLimits, "oversized implicit category") {
            cleanLimits.add(title: "valid title", category: oversizedCategory)
        }
        try unchangedAfterRejection(cleanLimits, "oversized explicit category") { cleanLimits.addCategory(oversizedCategory) }
        try unchangedAfterRejection(cleanLimits, "oversized category rename") { cleanLimits.renameCategory("work", to: oversizedCategory) }
        var oversizedEdit = cleanLimits.items[0]
        oversizedEdit.title = oversizedTitle
        oversizedEdit.category = "also-not-created"
        try unchangedAfterRejection(cleanLimits, "oversized edit title") { cleanLimits.update(oversizedEdit) }
        oversizedEdit.title = "valid title"
        oversizedEdit.category = oversizedCategory
        try unchangedAfterRejection(cleanLimits, "oversized edit category") { cleanLimits.update(oversizedEdit) }
        var invalidDateEdit = cleanLimits.items[0]
        invalidDateEdit.dueDate = Date(timeIntervalSinceReferenceDate: .infinity)
        try unchangedAfterRejection(cleanLimits, "invalid edit date") { cleanLimits.update(invalidDateEdit) }
        try unchangedAfterRejection(cleanLimits, "invalid add date") {
            cleanLimits.add(title: "invalid date", category: "work", dueDate: Date(timeIntervalSinceReferenceDate: .nan))
        }

        for number in 1...95 { cleanLimits.addCategory("类别\(number)") }
        expect(cleanLimits.categories.count == 100, "100th category accepted")
        let fullCategories = TaskStore(directory: limitsDirectory, seedExamples: false)
        expect(fullCategories.categories.count == 100 && !fullCategories.canUndo, "all 100 categories reopen without history")
        try unchangedAfterRejection(fullCategories, "101st explicit category") { fullCategories.addCategory("101") }
        try unchangedAfterRejection(fullCategories, "101st category via task add") { fullCategories.add(title: "valid task", category: "101") }
        var categoryOverflowEdit = fullCategories.items[0]
        categoryOverflowEdit.category = "101"
        try unchangedAfterRejection(fullCategories, "101st category via task edit") { fullCategories.update(categoryOverflowEdit) }
        fullCategories.add(title: "existing category still works", category: "work")
        expect(fullCategories.items.count == 2 && fullCategories.categories.count == 100, "task add in existing category works at category capacity")
        try unchangedAfterRejection(fullCategories, "rejection while valid undo exists") { fullCategories.addCategory("101") }
        fullCategories.undo()
        expect(fullCategories.items.count == 1 && !fullCategories.canUndo, "rejected actions do not consume the real undo operation")

        let validPreferences = cleanLimits.preferences
        cleanLimits.lastError = nil
        cleanLimits.preferences.idleOpacity = .nan
        expect(cleanLimits.preferences == validPreferences && cleanLimits.lastError != nil, "NaN opacity rejected without invalidating document")
        cleanLimits.preferences.idleOpacity = .infinity
        expect(cleanLimits.preferences == validPreferences, "infinite opacity rejected")
        cleanLimits.preferences.idleOpacity = -1
        expect(cleanLimits.preferences.idleOpacity == 0.15, "finite opacity remains safely clamped")
        let validPreferencesReopen = TaskStore(directory: limitsDirectory, seedExamples: false)
        expect(validPreferencesReopen.lastError == nil && validPreferencesReopen.preferences.idleOpacity == 0.15, "preferences reopen after invalid numerical inputs")

        // Use one compact fixture rather than 100,000 disk writes to exercise task-count capacity.
        let capacityDirectory = root.appendingPathComponent("capacity")
        try fm.createDirectory(at: capacityDirectory, withIntermediateDirectories: true)
        var capacityDocument = try JSONSerialization.jsonObject(with: Data(contentsOf: export)) as! [String: Any]
        let taskTemplate = (capacityDocument["items"] as! [[String: Any]])[0]
        var capacityItems = [[String: Any]]()
        capacityItems.reserveCapacity(100_001)
        for number in 0..<100_000 {
            var entry = taskTemplate
            entry["id"] = UUID().uuidString
            entry["title"] = "任务\(number)"
            capacityItems.append(entry)
        }
        capacityDocument["items"] = capacityItems
        let capacityFile = capacityDirectory.appendingPathComponent("tasks.json")
        try JSONSerialization.data(withJSONObject: capacityDocument).write(to: capacityFile)
        let capacityStore = TaskStore(directory: capacityDirectory, seedExamples: false)
        expect(capacityStore.lastError == nil && capacityStore.items.count == 100_000, "100000th task supported")
        try unchangedAfterRejection(capacityStore, "100001st task") { capacityStore.add(title: "one too many", category: "work") }
        var extra = taskTemplate
        extra["id"] = UUID().uuidString
        capacityItems.append(extra)
        capacityDocument["items"] = capacityItems
        let tooManyImport = root.appendingPathComponent("too-many.json")
        try JSONSerialization.data(withJSONObject: capacityDocument).write(to: tooManyImport)
        do { try cleanLimits.importData(from: tooManyImport); fatalError("Over-capacity import accepted") } catch {}
        expect(TaskStore(directory: limitsDirectory, seedExamples: false).items == cleanLimits.items, "over-capacity import preserves saved data")
        print("PASS: \(assertions) model behavior assertions")
    }
}
