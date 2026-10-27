import Foundation
import Combine

@main
struct ModelTests {
    @MainActor static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("AtAGlanceTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func tryResult(_ operation: () throws -> Bool) -> Bool {
            do { return try operation() } catch { return false }
        }
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
        expect(store.items[0].dueDate == CivilDay.date(from: CivilDay.string(from: due)!), "retain due date")
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

        let bcDate = CivilDay.calendar().date(from: DateComponents(era: 0, year: 1, month: 1, day: 1, hour: 12))!
        expect(CivilDay.string(from: bcDate) == nil, "BC era date cannot silently become AD deadline")
        try unchangedAfterRejection(cleanLimits, "BC add deadline") {
            cleanLimits.add(title: "BC deadline", category: "work", dueDate: bcDate)
        }
        var bcEdit = cleanLimits.items[0]
        bcEdit.dueDate = bcDate
        try unchangedAfterRejection(cleanLimits, "BC edit deadline") { cleanLimits.update(bcEdit) }

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

        // Stable failures do not depend on running as a particular user or chmod behavior.
        for failure in ["backup", "primary"] {
            let subject = TaskStore(directory: root.appendingPathComponent("write-" + failure), seedExamples: false)
            expect(subject.add(title: "durable", category: "work"), "failure fixture saved")
            let originalItems = subject.items
            let originalCategories = subject.categories
            let originalPreferences = subject.preferences
            let originalBytes = try Data(contentsOf: subject.dataFileURL)
            let parked = subject.directory.appendingPathComponent("parked.json")
            let obstruction = subject.directory.appendingPathComponent(failure == "backup" ? "tasks.backup.json" : "tasks.json")
            if failure == "primary" { try fm.moveItem(at: subject.dataFileURL, to: parked) }
            else { try? fm.removeItem(at: obstruction) }
            try fm.createDirectory(at: obstruction, withIntermediateDirectories: false)
            func assertFailure(_ name: String, _ action: () throws -> Bool) throws {
                subject.lastError = nil
                expect(tryResult(action) == false, failure + " " + name + " reports failure")
                expect(subject.lastError != nil, failure + " " + name + " explains error")
                expect(subject.items == originalItems && subject.categories == originalCategories && subject.preferences == originalPreferences && subject.canUndo,
                       failure + " " + name + " leaves committed live data and history")
                let durable = try Data(contentsOf: failure == "primary" ? parked : subject.dataFileURL)
                expect(durable == originalBytes, failure + " " + name + " preserves durable bytes")
            }
            try assertFailure("add") { subject.add(title: "lost", category: "implicit") }
            var edit = subject.items[0]; edit.title = "changed"; edit.dueDate = due
            try assertFailure("edit") { subject.update(edit) }
            try assertFailure("delete") { subject.delete(originalItems[0].id) }
            try assertFailure("status") { subject.setStatus(originalItems[0].id, .completed) }
            try assertFailure("category add") { subject.addCategory("new") }
            try assertFailure("category rename") { subject.renameCategory("work", to: "renamed") }
            try assertFailure("category delete") { subject.deleteCategory("work") }
            try assertFailure("undo") { subject.undo() }
            try assertFailure("import") { try subject.importData(from: export); return true }
            try assertFailure("preferences") {
                subject.preferences.alwaysOnTop.toggle()
                return subject.preferences != originalPreferences
            }
            try fm.removeItem(at: obstruction)
            if failure == "primary" { try fm.moveItem(at: parked, to: subject.dataFileURL) }
            expect(subject.add(title: "retry", category: "life") && subject.lastError == nil, failure + " successful retry clears stale error")
            expect(subject.undo() && subject.items == originalItems, failure + " undo successful retry")
            expect(subject.undo() && subject.items.isEmpty && !subject.canUndo, failure + " failed actions never consumed or appended undo snapshots")
            expect(TaskStore(directory: subject.directory, seedExamples: false).items.isEmpty, failure + " recovered state survives restart")
        }
        // Inject failure at the final atomic write, after the real backup write succeeds.
        let finalWriteDirectory = root.appendingPathComponent("final-write-failure")
        var failFinalWrite = false
        let finalWriteStore = TaskStore(directory: finalWriteDirectory, seedExamples: false, atomicWriter: { data, url in
            if failFinalWrite && url.lastPathComponent == "tasks.json" {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try data.write(to: url, options: .atomic)
        })
        expect(finalWriteStore.add(title: "durable before final write", category: "work"), "final write fixture commits normally")
        let finalWriteItems = finalWriteStore.items
        let finalWriteCategories = finalWriteStore.categories
        let finalWritePreferences = finalWriteStore.preferences
        let finalWriteBytes = try Data(contentsOf: finalWriteStore.dataFileURL)
        failFinalWrite = true
        func assertFinalWriteFailure(_ name: String, _ action: () throws -> Bool) throws {
            finalWriteStore.lastError = nil
            expect(!tryResult(action) && finalWriteStore.lastError != nil, name + " final atomic write failure is reported")
            expect(finalWriteStore.items == finalWriteItems && finalWriteStore.categories == finalWriteCategories && finalWriteStore.preferences == finalWritePreferences && finalWriteStore.canUndo,
                   name + " final atomic write failure preserves live data and undo")
            let unchangedMain = try Data(contentsOf: finalWriteStore.dataFileURL)
            let completedBackup = try Data(contentsOf: finalWriteDirectory.appendingPathComponent("tasks.backup.json"))
            expect(unchangedMain == finalWriteBytes, name + " failed final write preserves main bytes")
            expect(completedBackup == finalWriteBytes, name + " backup already contains previously committed document")
        }
        try assertFinalWriteFailure("add") { finalWriteStore.add(title: "rejected", category: "new") }
        var finalWriteEdit = finalWriteItems[0]; finalWriteEdit.title = "rejected edit"
        try assertFinalWriteFailure("update") { finalWriteStore.update(finalWriteEdit) }
        try assertFinalWriteFailure("import") { try finalWriteStore.importData(from: export); return true }
        try assertFinalWriteFailure("undo") { finalWriteStore.undo() }
        try assertFinalWriteFailure("preferences") {
            finalWriteStore.preferences.alwaysOnTop.toggle()
            return finalWriteStore.preferences != finalWritePreferences
        }
        failFinalWrite = false
        expect(finalWriteStore.add(title: "successful retry", category: "work") && finalWriteStore.lastError == nil, "final write retry succeeds and clears stale error")
        expect(finalWriteStore.undo() && finalWriteStore.items == finalWriteItems, "retry undo restores original committed data")
        expect(finalWriteStore.undo() && finalWriteStore.items.isEmpty && !finalWriteStore.canUndo, "failed final writes never alter undo stack")
        expect(TaskStore(directory: finalWriteDirectory, seedExamples: false).items.isEmpty, "recovered final write state survives restart")

        let blockedDirectory = root.appendingPathComponent("blocked")
        try Data("directory obstruction".utf8).write(to: blockedDirectory)
        let blocked = TaskStore(directory: blockedDirectory, seedExamples: false)
        expect(blocked.lastError != nil, "initial directory failure is visible")
        expect(!blocked.add(title: "not saved", category: "work") && blocked.items.isEmpty && !blocked.canUndo, "blocked persistence cannot report successful add")
        let blockedPreferences = blocked.preferences
        blocked.preferences.alwaysOnTop.toggle()
        expect(blocked.preferences == blockedPreferences && blocked.lastError != nil, "blocked preferences retain committed value")

        // Only this test process changes its default time zone; never change system settings.
        let originalZone = NSTimeZone.default
        defer { NSTimeZone.default = originalZone }
        NSTimeZone.default = TimeZone(identifier: "Asia/Shanghai")!
        let shanghaiDeadlineInstant = CivilDay.date(from: "2026-10-28")!
        let utcDisplayInstant = CivilDay.displayDate(from: "2026-10-28")!
        let civil = TaskStore(directory: root.appendingPathComponent("civil"), seedExamples: false)
        for dayString in ["2026-10-28", "2026-03-08", "2026-11-01", "2028-02-29"] {
            expect(civil.add(title: dayString, category: "work", dueDate: CivilDay.date(from: dayString)!), "civil day added")
        }
        civil.add(title: "undated", category: "work")
        let civilExport = root.appendingPathComponent("civil-export.json")
        try civil.exportData(to: civilExport)
        let civilRaw = try JSONSerialization.jsonObject(with: Data(contentsOf: civilExport)) as! [String: Any]
        expect(civilRaw["version"] as? Int == 2, "writes schema v2")
        expect((civilRaw["items"] as! [[String: Any]])[0]["dueDate"] as? String == "2026-10-28", "canonical deadline string on disk")
        for zone in ["America/Los_Angeles", "Europe/Berlin", "Asia/Shanghai"] {
            NSTimeZone.default = TimeZone(identifier: zone)!
            if zone == "America/Los_Angeles" {
                expect(CivilDay.date(from: "2026-10-28") != shanghaiDeadlineInstant, "timezone test changes actual local deadline instant")
                expect(CivilDay.displayDate(from: "2026-10-28") == utcDisplayInstant, "UTC display adapter is timezone invariant")
            }
            for item in civil.items where item.title != "undated" {
                expect(item.dueDate.flatMap(CivilDay.string) == item.title, zone + " live date retains civil day including DST")
            }
            let reopenedCivil = TaskStore(directory: civil.directory, seedExamples: false)
            expect(reopenedCivil.items == civil.items, zone + " restart retains canonical data")
            expect(reopenedCivil.items.last?.dueDate == nil, zone + " no deadline remains nil")
            expect(reopenedCivil.sortedItems(for: .todo).map(\.title) == ["2026-03-08", "2026-10-28", "2026-11-01", "2028-02-29", "undated"], zone + " civil sorting")
            let destination = TaskStore(directory: root.appendingPathComponent(UUID().uuidString), seedExamples: false)
            try destination.importData(from: civilExport)
            expect(destination.items == civil.items, zone + " cross-zone import retains days")
            var changedDay = destination.items[0]
            changedDay.dueDate = CivilDay.date(from: "2026-10-29")!
            expect(destination.update(changedDay) && destination.items[0].dueDate.flatMap(CivilDay.string) == "2026-10-29", zone + " local date editor adapter")
            expect(destination.undo() && destination.items == civil.items, zone + " deadline edit undo")
        }
        NSTimeZone.default = TimeZone(identifier: "Asia/Shanghai")!
        var legacy = civilRaw
        legacy["version"] = 1
        var legacyItems = legacy["items"] as! [[String: Any]]
        for index in legacyItems.indices {
            if let dayString = legacyItems[index]["dueDate"] as? String {
                legacyItems[index]["dueDate"] = CivilDay.date(from: dayString)!.timeIntervalSinceReferenceDate
            }
        }
        legacy["items"] = legacyItems
        let legacyBytes = try JSONSerialization.data(withJSONObject: legacy)
        let legacyDirectory = root.appendingPathComponent("v1")
        try fm.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try legacyBytes.write(to: legacyDirectory.appendingPathComponent("tasks.json"))
        let failedMigrationDirectory = root.appendingPathComponent("v1-write-failed")
        try fm.createDirectory(at: failedMigrationDirectory, withIntermediateDirectories: true)
        let failedMigrationFile = failedMigrationDirectory.appendingPathComponent("tasks.json")
        try legacyBytes.write(to: failedMigrationFile)
        let failedMigrationBackup = failedMigrationDirectory.appendingPathComponent("tasks.backup.json")
        try fm.createDirectory(at: failedMigrationBackup, withIntermediateDirectories: false)
        let failedMigration = TaskStore(directory: failedMigrationDirectory, seedExamples: false)
        let failedMigrationBytes = try Data(contentsOf: failedMigrationFile)
        expect(failedMigration.lastError != nil && failedMigrationBytes == legacyBytes, "failed migration preserves original file and reports error")
        expect(failedMigration.items == civil.items && failedMigration.categories == civil.categories, "failed migration retains decoded tasks for viewing")
        let failedMigrationExport = root.appendingPathComponent("failed-migration-export.json")
        try failedMigration.exportData(to: failedMigrationExport)
        let exportedMigration = TaskStore(directory: root.appendingPathComponent("failed-migration-import"), seedExamples: false)
        try exportedMigration.importData(from: failedMigrationExport)
        expect(exportedMigration.items == civil.items, "failed migration still allows lossless task export")
        expect(!failedMigration.add(title: "blocked", category: "work") && !failedMigration.canUndo, "failed migration blocks false success and undo changes")
        try fm.removeItem(at: failedMigrationBackup)
        expect(TaskStore(directory: failedMigrationDirectory, seedExamples: false).items == civil.items, "migration retries safely after reopening with writable backup")
        let migrated = TaskStore(directory: legacyDirectory, seedExamples: false)
        expect(migrated.lastError == nil && migrated.items == civil.items, "v1 timestamps interpreted in migration Mac timezone")
        let migrationCopy = try fm.contentsOfDirectory(at: legacyDirectory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("tasks.v1-") }!
        let migrationBytes = try Data(contentsOf: migrationCopy)
        expect(migrationBytes == legacyBytes, "migration retains byte-exact v1 original")
        let migratedRaw = try JSONSerialization.jsonObject(with: Data(contentsOf: migrated.dataFileURL)) as! [String: Any]
        expect(migratedRaw["version"] as? Int == 2, "migration commits v2 before publishing")
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        expect(TaskStore(directory: legacyDirectory, seedExamples: false).items[0].dueDate.flatMap(CivilDay.string) == "2026-10-28", "migrated deadline survives timezone change")
        for invalidDay in ["2026-02-29", "2026-13-01", "2026-04-31", "2026-1-01", "0000-01-01"] {
            var invalidRaw = civilRaw
            var invalidItems = invalidRaw["items"] as! [[String: Any]]
            invalidItems[0]["dueDate"] = invalidDay; invalidRaw["items"] = invalidItems
            try JSONSerialization.data(withJSONObject: invalidRaw).write(to: bad)
            let beforeInvalid = civil.items
            do { try civil.importData(from: bad); fatalError("Invalid civil date accepted") } catch {}
            expect(civil.items == beforeInvalid && civil.lastError != nil, "invalid civil date rejected: " + invalidDay)
        }
        var numericV2 = civilRaw
        var numericV2Items = numericV2["items"] as! [[String: Any]]
        numericV2Items[0]["dueDate"] = due.timeIntervalSinceReferenceDate
        numericV2["items"] = numericV2Items
        try JSONSerialization.data(withJSONObject: numericV2).write(to: bad)
        let beforeNumericV2 = civil.items
        do { try civil.importData(from: bad); fatalError("Numeric v2 deadline accepted") } catch {}
        expect(civil.items == beforeNumericV2 && civil.lastError != nil, "v2 rejects numeric legacy deadline without mutation")
        NSTimeZone.default = TimeZone(identifier: "Asia/Shanghai")!
        let skippedDayDirectory = root.appendingPathComponent("skipped-civil-day")
        let skippedDayStore = TaskStore(directory: skippedDayDirectory, seedExamples: false)
        skippedDayStore.add(title: "Apia skipped date", category: "work", dueDate: CivilDay.date(from: "2011-12-30")!)
        skippedDayStore.add(title: "previous day", category: "work", dueDate: CivilDay.date(from: "2011-12-29")!)
        skippedDayStore.add(title: "next day", category: "work", dueDate: CivilDay.date(from: "2011-12-31")!)
        skippedDayStore.add(title: "undated", category: "work")
        let skippedDayOriginal = skippedDayStore.items
        NSTimeZone.default = TimeZone(identifier: "Pacific/Apia")!
        expect(CivilDay.isValid("2011-12-30") && CivilDay.displayDate(from: "2011-12-30") != nil, "UTC canonical validation accepts civil date skipped in Apia")
        expect(CivilDay.date(from: "2011-12-30") == nil, "local DatePicker adapter explicitly has no date for skipped local day")
        let skippedDayReopened = TaskStore(directory: skippedDayDirectory, seedExamples: false)
        expect(skippedDayReopened.lastError == nil && skippedDayReopened.items == skippedDayOriginal, "Apia loads all canonical data without quarantine")
        expect(skippedDayReopened.items[0].dueDay == "2011-12-30", "Apia preserves canonical deadline even when local adapter is nil")
        expect(skippedDayReopened.sortedItems(for: .todo).map(\.title) == ["previous day", "Apia skipped date", "next day", "undated"], "Apia sorting compares canonical days")
        let skippedDayExport = root.appendingPathComponent("apia-export.json")
        try skippedDayReopened.exportData(to: skippedDayExport)
        let skippedDayImported = TaskStore(directory: root.appendingPathComponent("apia-import"), seedExamples: false)
        try skippedDayImported.importData(from: skippedDayExport)
        expect(skippedDayImported.items == skippedDayOriginal, "Apia export and import retain all tasks and canonical deadlines")
        skippedDayImported.preferences.alwaysOnTop.toggle()
        expect(skippedDayImported.lastError == nil && TaskStore(directory: skippedDayImported.directory, seedExamples: false).items == skippedDayOriginal, "Apia preference write cannot discard skipped-day task")
        let skippedDayFiles = try fm.contentsOfDirectory(at: skippedDayDirectory, includingPropertiesForKeys: nil)
        expect(!skippedDayFiles.contains(where: { $0.lastPathComponent.hasPrefix("tasks.unreadable-") }), "valid canonical data does not enter unreadable recovery")
        NSTimeZone.default = TimeZone(identifier: "America/Sao_Paulo")!
        expect(CivilDay.isValid("2018-11-04"), "midnight DST transition is a valid Gregorian date")
        let midnightDST = CivilDay.date(from: "2018-11-04")
        expect(midnightDST.flatMap(CivilDay.string) == "2018-11-04", "local noon adapter round trips Sao Paulo midnight DST")
        expect(CivilDay.calendar().component(.hour, from: midnightDST!) == 12, "Sao Paulo adapter uses representable local noon")
        for invalidGregorian in ["2011-02-29", "1900-02-29", "2026-04-31", "2026-00-10", "2026-01-00"] {
            expect(!CivilDay.isValid(invalidGregorian), "UTC validation rejects invalid Gregorian date " + invalidGregorian)
        }
        let observedPreferences = TaskStore(directory: root.appendingPathComponent("preferences-publisher"), seedExamples: false)
        var preferenceEvents: [AppPreferences] = []
        let preferenceSubscription = observedPreferences.preferencesPublisher.sink { preferenceEvents.append($0) }
        observedPreferences.preferences.alwaysOnTop = false
        expect(preferenceEvents.count == 2 && preferenceEvents.last?.alwaysOnTop == false, "public publisher emits initial and successfully committed preferences")
        try fm.removeItem(at: observedPreferences.directory.appendingPathComponent("tasks.backup.json"))
        try fm.createDirectory(at: observedPreferences.directory.appendingPathComponent("tasks.backup.json"), withIntermediateDirectories: false)
        observedPreferences.preferences.alwaysOnTop = true
        expect(preferenceEvents.count == 2 && !observedPreferences.preferences.alwaysOnTop, "publisher does not expose rejected preference changes")
        withExtendedLifetime(preferenceSubscription) {}
        NSTimeZone.default = originalZone

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
