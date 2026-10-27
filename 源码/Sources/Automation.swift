import Foundation

struct AutomationTask {
    let title: String
    let category: String
    let dueDate: Date?
}

enum TodoAutomationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum TodoAutomation {
    /// An explicit, append-only bridge. Other URL schemes are not handled here.
    static func parse(_ url: URL) throws -> AutomationTask? {
        guard url.scheme?.lowercased() == "ataglance" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.lowercased() == "add", components.path.isEmpty,
              components.user == nil, components.password == nil, components.port == nil,
              components.fragment == nil else {
            throw TodoAutomationError.invalid("仅支持添加待办：ataglance://add?title=任务名称。")
        }
        let query = components.queryItems ?? []
        let allowed = Set(["title", "category", "due"])
        guard query.allSatisfy({ allowed.contains($0.name) }), Set(query.map(\.name)).count == query.count else {
            throw TodoAutomationError.invalid("指令包含未知或重复参数；仅支持 title、category、due。")
        }
        func value(_ key: String) -> String? {
            query.first(where: { $0.name == key })?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let title = value("title"), !title.isEmpty else {
            throw TodoAutomationError.invalid("请提供待办标题，title 不能为空。")
        }
        guard title.count <= 10_000 else { throw TodoAutomationError.invalid("待办标题过长，请控制在 10000 字以内。") }
        let rawCategory = value("category") ?? "work"
        let category = rawCategory.isEmpty ? "work" : rawCategory
        guard category.count <= 100 else { throw TodoAutomationError.invalid("分类名称过长，请控制在 100 字以内。") }

        var dueDate: Date?
        if let dueItem = query.first(where: { $0.name == "due" }) {
            guard let due = dueItem.value,
                  due.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else {
                throw TodoAutomationError.invalid("截止日期须为有效的 YYYY-MM-DD，例如 2026-10-28。")
            }
            guard CivilDay.isValid(due) else {
                throw TodoAutomationError.invalid("截止日期不存在，请检查年月日。")
            }
            guard let date = CivilDay.date(from: due) else {
                throw TodoAutomationError.invalid("当前时区不存在此日期，请选择其他截止日期。")
            }
            dueDate = date
        }
        return AutomationTask(title: title, category: category, dueDate: dueDate)
    }
}
