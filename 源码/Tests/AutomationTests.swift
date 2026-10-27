import Foundation

@main
struct AutomationTests {
    @MainActor static func main() throws {
        let originalTimeZone = NSTimeZone.default
        defer { NSTimeZone.default = originalTimeZone }
        NSTimeZone.default = TimeZone(identifier: "Asia/Shanghai")!
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ reason: String) {
            checks += 1
            guard condition() else { fatalError("FAILED: \(reason)") }
        }
        func rejects(_ raw: String) {
            checks += 1
            do { _ = try TodoAutomation.parse(URL(string: raw)!); fatalError("Accepted invalid URL: \(raw)") }
            catch { expect(!error.localizedDescription.isEmpty, "localized validation error") }
        }
        let simple = try TodoAutomation.parse(URL(string: "ataglance://add?title=Hello")!)!
        expect(simple.title == "Hello" && simple.category == "work" && simple.dueDate == nil, "default category and optional date")
        let special = try TodoAutomation.parse(URL(string: "ataglance://add?title=%20%E4%B9%B0%20%E5%92%96%E5%95%A1%20%26%20%E8%8C%B6%2B%E7%82%B9%E5%BF%83%20&category=life&due=2026-10-28")!)!
        expect(special.title == "买 咖啡 & 茶+点心" && special.category == "life", "decode Chinese spaces ampersand and literal plus")
        let local = CivilDay.calendar().dateComponents([.year, .month, .day, .hour], from: special.dueDate!)
        expect(local.year == 2026 && local.month == 10 && local.day == 28 && local.hour == 12, "date uses local noon to avoid DST midnight gaps")
        let leap = try TodoAutomation.parse(URL(string: "ataglance://add?title=Leap&due=2028-02-29")!)!
        expect(leap.dueDate != nil, "leap day accepted")
        let unrelated = try TodoAutomation.parse(URL(string: "https://example.com/add?title=Hello")!)
        expect(unrelated == nil, "unrelated scheme ignored")
        rejects("ataglance://delete?title=Hello")
        rejects("ataglance://add/tasks?title=Hello")
        rejects("ataglance://add?title=")
        rejects("ataglance://add?title=%20%0A%20")
        rejects("ataglance://add?title=Hello&title=Bye")
        rejects("ataglance://add?title=Hello&command=delete")
        rejects("ataglance://add?title=Hello&due=2026-02-29")
        rejects("ataglance://add?title=Hello&due=2026-02-30")
        rejects("ataglance://add?title=Hello&due=2026-13-01")
        rejects("ataglance://add?title=Hello&due=2026-1-01")
        rejects("ataglance://add?title=Hello&due=")
        rejects("ataglance://add?title=Hello#delete")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AtAGlanceAutomationTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TaskStore(directory: directory, seedExamples: false)
        expect(store.add(title: special.title, category: special.category, dueDate: special.dueDate), "parsed URL task saves successfully")
        let expectedDay = store.items[0].dueDay
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        expect(expectedDay == "2026-10-28" && store.items[0].dueDay == expectedDay, "URL task preserves its civil date across time zones")
        expect(DeadlinePresentation.short(store.items[0].dueDay!) == "10/28", "visible short date remains unchanged")
        expect(CivilDay.string(from: store.items[0].dueDate!) == expectedDay, "DatePicker adapter uses the same local day")
        let reloaded = TaskStore(directory: directory, seedExamples: false)
        expect(reloaded.items[0].dueDay == expectedDay, "URL deadline survives restart in another time zone")
        NSTimeZone.default = TimeZone(identifier: "America/Sao_Paulo")!
        let midnightDST = try TodoAutomation.parse(URL(string: "ataglance://add?title=DST&due=2018-11-04")!)!
        expect(CivilDay.string(from: midnightDST.dueDate!) == "2018-11-04", "valid civil day with a midnight DST gap is accepted")
        NSTimeZone.default = TimeZone(identifier: "Pacific/Apia")!
        rejects("ataglance://add?title=Skipped&due=2011-12-30")
        expect(DeadlinePresentation.short("2011-12-30") == "12/30", "existing skipped civil dates retain their visible label")
        let fullSkippedDay = DeadlinePresentation.full("2011-12-30")
        NSTimeZone.default = TimeZone(identifier: "Asia/Shanghai")!
        expect(DeadlinePresentation.full("2011-12-30") == fullSkippedDay, "long labels format the civil day, independent of system time zone")
        print("PASS: \(checks) automation behavior assertions")
    }
}
