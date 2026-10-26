import Foundation

@main
struct AutomationTests {
    static func main() throws {
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
        let local = Calendar(identifier: .gregorian).dateComponents(in: .current, from: special.dueDate!)
        expect(local.year == 2026 && local.month == 10 && local.day == 28 && local.hour == 0, "date uses current time zone")
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
        print("PASS: \(checks) automation behavior assertions")
    }
}
