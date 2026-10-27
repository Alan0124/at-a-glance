import Foundation
import Combine

enum TodoStatus: String, Codable, CaseIterable, Identifiable {
    case todo, pending, completed, cancelled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .todo: return "To-do"
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }
}

/// A deadline is a Gregorian civil day, independent of the machine's time zone.
/// Date is only the local-calendar adapter used by DatePicker and automation.
enum CivilDay {
    // Foundation default follows the system zone unless explicitly overridden by this process.
    static func calendar(timeZone: TimeZone = NSTimeZone.default) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
    static func string(from date: Date) -> String? {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let c = calendar().dateComponents([.era, .year, .month, .day], from: date)
        guard c.era == 1, let y = c.year, let m = c.month, let d = c.day, (1...9999).contains(y) else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
    /// A UTC adapter for display with an explicitly UTC formatter, never DatePicker.
    static func displayDate(from string: String) -> Date? {
        parsedDate(from: string, timeZone: TimeZone(secondsFromGMT: 0)!)
    }
    static func isValid(_ string: String) -> Bool { displayDate(from: string) != nil }

    /// Local DatePicker adapter. A civil day skipped by this time zone has no Date.
    /// That does not make an existing canonical deadline invalid.
    static func date(from string: String) -> Date? {
        parsedDate(from: string, timeZone: NSTimeZone.default)
    }
    private static func parsedDate(from string: String, timeZone: TimeZone) -> Date? {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              string.utf8.allSatisfy({ $0 == 45 || (48...57).contains($0) }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]), (1...9999).contains(y) else { return nil }
        let cal = calendar(timeZone: timeZone)
        guard let date = cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) else { return nil }
        let c = cal.dateComponents([.year, .month, .day], from: date)
        guard c.year == y, c.month == m, c.day == d else { return nil }
        return date
    }
}

private extension CodingUserInfoKey {
    static let storeVersion = CodingUserInfoKey(rawValue: "AtAGlance.storeVersion")!
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var category: String
    var status: TodoStatus = .todo
    private var deadline: String? = nil
    private var invalidDeadline: Date? = nil
    var createdAt: Date = Date()
    var dueDate: Date? {
        get { invalidDeadline ?? deadline.flatMap(CivilDay.date) }
        set {
            deadline = newValue.flatMap(CivilDay.string)
            invalidDeadline = newValue != nil && deadline == nil ? newValue : nil
        }
    }
    /// The sole persisted deadline truth, including dates absent in the current time zone.
    var dueDay: String? { deadline }
    var hasValidDeadline: Bool { invalidDeadline == nil && (deadline.map(CivilDay.isValid) ?? true) }
    init(id: UUID = UUID(), title: String, category: String, status: TodoStatus = .todo, dueDate: Date? = nil, createdAt: Date = Date()) {
        self.id = id; self.title = title; self.category = category; self.status = status; self.createdAt = createdAt
        self.dueDate = dueDate
    }
    private enum CodingKeys: String, CodingKey { case id, title, category, status, dueDate, createdAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        category = try c.decode(String.self, forKey: .category)
        status = try c.decode(TodoStatus.self, forKey: .status)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        if try !c.contains(.dueDate) || c.decodeNil(forKey: .dueDate) { deadline = nil }
        else if (decoder.userInfo[.storeVersion] as? Int ?? 2) == 2 {
            let day = try c.decode(String.self, forKey: .dueDate)
            guard CivilDay.isValid(day) else { throw TaskStoreError.invalid("任务日期无效，操作未执行。") }
            deadline = day
        } else {
            let date = try c.decode(Date.self, forKey: .dueDate)
            guard let day = CivilDay.string(from: date) else { throw TaskStoreError.invalid("任务日期无效，操作未执行。") }
            deadline = day
        }
    }
    func encode(to encoder: Encoder) throws {
        guard hasValidDeadline else { throw TaskStoreError.invalid("任务日期无效，操作未执行。") }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(title, forKey: .title)
        try c.encode(category, forKey: .category); try c.encode(status, forKey: .status)
        try c.encodeIfPresent(deadline, forKey: .dueDate); try c.encode(createdAt, forKey: .createdAt)
    }
}

struct AppPreferences: Codable, Equatable {
    var idleOpacity: Double = 0.32
    var alwaysOnTop: Bool = true
    var collapseOnLeave: Bool = false
    var launchAtLogin: Bool = false

    init() {}
    private enum CodingKeys: String, CodingKey {
        case idleOpacity, alwaysOnTop, collapseOnLeave, launchAtLogin
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        idleOpacity = try c.decodeIfPresent(Double.self, forKey: .idleOpacity) ?? 0.32
        alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? true
        collapseOnLeave = try c.decodeIfPresent(Bool.self, forKey: .collapseOnLeave) ?? false
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }
}

private struct StoreDocument: Codable {
    var version: Int = 2
    var categories: [String]
    var items: [TodoItem]
    var preferences: AppPreferences
}

private struct StoreSnapshot {
    let categories: [String]
    let items: [TodoItem]
}

enum TaskStoreError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    @Published private(set) var categories: [String] = ["work", "life", "content", "study"]
    @Published private var committedPreferences = AppPreferences()
    var preferencesPublisher: Published<AppPreferences>.Publisher { $committedPreferences }
    var preferences: AppPreferences {
        get { committedPreferences }
        set {
            guard !isLoading else { committedPreferences = newValue; return }
            var candidate = document
            candidate.preferences = newValue
            do {
                candidate = try Self.validate(candidate)
                try persist(candidate)
                committedPreferences = candidate.preferences
            } catch { lastError = error.localizedDescription }
        }
    }
    @Published var lastError: String?
    @Published private(set) var canUndo: Bool = false

    let directory: URL
    var dataFileURL: URL { directory.appendingPathComponent("tasks.json") }
    private var undoStack: [StoreSnapshot] = []
    private var isLoading = true
    private var persistenceBlocked = false
    private let fileManager = FileManager.default
    private let atomicWriter: (Data, URL) throws -> Void

    init(directory: URL? = nil, seedExamples: Bool = true,
         atomicWriter: @escaping (Data, URL) throws -> Void = { data, url in
             try data.write(to: url, options: .atomic)
         }) {
        self.atomicWriter = atomicWriter
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AtAGlance", isDirectory: true)
        do {
            try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: dataFileURL.path) {
                do {
                    let document = try Self.decode(Data(contentsOf: dataFileURL))
                    categories = document.categories
                    items = document.items
                    preferences = document.preferences
                    if document.version == 1 {
                        // Old files lack their originating time zone. Interpret their instants in
                        // this Mac's current time zone, retaining exact original bytes for recovery.
                        let preserved = self.directory.appendingPathComponent("tasks.v1-\(UUID().uuidString).json")
                        try Data(contentsOf: dataFileURL).write(to: preserved, options: .atomic)
                        var migrated = document
                        migrated.version = 2
                        try persist(migrated)
                    }
                } catch {
                    if let bytes = try? Data(contentsOf: dataFileURL), (try? Self.decode(bytes)) != nil {
                        persistenceBlocked = true
                        lastError = "旧版清单迁移保存失败，原文件已保留。请检查目录后重新打开。\(error.localizedDescription)"
                        isLoading = false
                        return
                    }
                    // Move instead of overwrite: keep the exact unreadable bytes for recovery.
                    let preserved = self.directory.appendingPathComponent("tasks.unreadable-\(UUID().uuidString).json")
                    do {
                        try fileManager.moveItem(at: dataFileURL, to: preserved)
                        lastError = "原清单无法读取，已原样保留为 \(preserved.lastPathComponent)。当前显示空白清单，可从备份导入。"
                    } catch {
                        persistenceBlocked = true
                        lastError = "原清单无法读取，且无法保留备份。为保护原数据已暂停保存；请导出当前清单。\(error.localizedDescription)"
                    }
                }
            } else if seedExamples {
                items = [
                    TodoItem(title: "点击方框，完成第一件小事", category: "work"),
                    TodoItem(title: "鼠标移开后，清单会轻轻淡出", category: "life"),
                    TodoItem(title: "在底部输入，按回车添加待办", category: "study")
                ]
            }
        } catch {
            persistenceBlocked = true
            lastError = "无法打开本地数据目录，请检查文件权限。\(error.localizedDescription)"
        }
        isLoading = false
        // New installations get durable tutorial entries; unreadable data stays untouched.
        if !fileManager.fileExists(atPath: dataFileURL.path), lastError == nil {
            do { try persist(document) } catch { lastError = error.localizedDescription }
        }
    }

    func sortedItems(for status: TodoStatus) -> [TodoItem] {
        return items.filter { $0.status == status }.sorted {
            // Fixed-width Gregorian dates sort chronologically in every time zone.
            let first = $0.dueDay ?? "9999-99-99"
            let second = $1.dueDay ?? "9999-99-99"
            return first == second ? $0.createdAt < $1.createdAt : first < second
        }
    }

    @discardableResult
    func add(title: String, category: String, dueDate: Date? = nil) -> Bool {
        let title = Self.trim(title)
        guard !title.isEmpty else { return false }
        return performValidatedChange {
            var candidate = document
            let category = ensureCategory(category, in: &candidate)
            candidate.items.append(TodoItem(title: title, category: category, dueDate: dueDate))
            try commit(candidate)
        }
    }

    @discardableResult
    func update(_ item: TodoItem) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        var normalized = item
        normalized.title = Self.trim(item.title)
        guard !normalized.title.isEmpty else { return false }
        normalized.category = Self.trim(item.category)
        if normalized.category.isEmpty { normalized.category = categories[0] }
        guard normalized != items[index] else { return true }
        return performValidatedChange {
            var candidate = document
            normalized.category = ensureCategory(normalized.category, in: &candidate)
            candidate.items[index] = normalized
            try commit(candidate)
        }
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        guard items.contains(where: { $0.id == id }) else { return false }
        return performValidatedChange {
            var candidate = document
            candidate.items.removeAll { $0.id == id }
            try commit(candidate)
        }
    }

    @discardableResult
    func setStatus(_ id: UUID, _ status: TodoStatus) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        guard items[index].status != status else { return true }
        return performValidatedChange {
            var candidate = document
            candidate.items[index].status = status
            try commit(candidate)
        }
    }

    @discardableResult
    func addCategory(_ name: String) -> Bool {
        let name = Self.trim(name)
        guard !name.isEmpty else { return false }
        guard !categories.contains(name) else { return true }
        return performValidatedChange {
            var candidate = document
            candidate.categories.append(name)
            try commit(candidate)
        }
    }

    @discardableResult
    func renameCategory(_ old: String, to newName: String) -> Bool {
        let name = Self.trim(newName)
        guard !name.isEmpty, let index = categories.firstIndex(of: old) else { return false }
        guard old != name else { return true }
        guard !categories.contains(name) else {
            lastError = "已有同名分类，请换一个名称。"
            return false
        }
        return performValidatedChange {
            var candidate = document
            candidate.categories[index] = name
            for index in candidate.items.indices where candidate.items[index].category == old {
                candidate.items[index].category = name
            }
            try commit(candidate)
        }
    }

    @discardableResult
    func deleteCategory(_ name: String) -> Bool {
        guard categories.contains(name) else { return false }
        guard categories.count > 1 else { lastError = "请至少保留一个分类。"; return false }
        return performValidatedChange {
            var candidate = document
            candidate.categories.removeAll { $0 == name }
            for index in candidate.items.indices where candidate.items[index].category == name {
                candidate.items[index].category = candidate.categories[0]
            }
            try commit(candidate)
        }
    }

    @discardableResult
    func undo() -> Bool {
        guard let snapshot = undoStack.last else { return false }
        return performValidatedChange {
            var candidate = document
            candidate.categories = snapshot.categories
            candidate.items = snapshot.items
            try persist(candidate)
            categories = candidate.categories
            items = candidate.items
            undoStack.removeLast()
            canUndo = !undoStack.isEmpty
        }
    }

    func exportData(to url: URL) throws {
        try Self.encode(document).write(to: url, options: .atomic)
    }

    /// Import replaces the active list only after full validation; the operation is undoable.
    func importData(from url: URL) throws {
        do {
        let document = try Self.decode(Data(contentsOf: url))
        // Machine-specific window/login choices remain local when importing tasks.
        var candidate = document
        candidate.preferences = preferences
        try commit(candidate)
        } catch { lastError = error.localizedDescription; throw error }
    }

    private var document: StoreDocument { StoreDocument(categories: categories, items: items, preferences: preferences) }

    private func remember() {
        undoStack.append(StoreSnapshot(categories: categories, items: items))
        if undoStack.count > 30 { undoStack.removeFirst() }
        canUndo = true
    }

    /// Only prepares a candidate; no live state changes until its write succeeds.
    private func ensureCategory(_ raw: String, in candidate: inout StoreDocument) -> String {
        let name = Self.trim(raw)
        if name.isEmpty { return candidate.categories[0] }
        if !candidate.categories.contains(name) { candidate.categories.append(name) }
        return name
    }

    private func performValidatedChange(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func commit(_ candidate: StoreDocument) throws {
        let validated = try Self.validate(candidate)
        try persist(validated)
        remember()
        categories = validated.categories
        items = validated.items
    }

    private func persist(_ candidate: StoreDocument) throws {
        guard !persistenceBlocked else { throw TaskStoreError.invalid("为保护原数据已暂停保存；请检查数据目录并重新打开应用。") }
        do {
            let data = try Self.encode(candidate)
            if fileManager.fileExists(atPath: dataFileURL.path) {
                let previous = try Data(contentsOf: dataFileURL)
                try atomicWriter(previous, directory.appendingPathComponent("tasks.backup.json"))
            }
            try atomicWriter(data, dataFileURL)
            lastError = nil
        } catch {
            throw TaskStoreError.invalid("保存失败，请导出备份并检查磁盘空间或目录权限。\(error.localizedDescription)")
        }
    }

    private static func trim(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static let maximumDataBytes = 50_000_000
    private static let maximumCategories = 100
    private static let maximumCategoryLength = 100
    private static let maximumTasks = 100_000
    private static let maximumTitleLength = 10_000

    private static func encode(_ document: StoreDocument) throws -> Data {
        var document = try validate(document)
        document.version = 2
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Creation timestamps remain lossless instants; deadlines encode as civil-day strings.
        encoder.dateEncodingStrategy = .deferredToDate
        let data = try encoder.encode(document)
        guard data.count <= maximumDataBytes else {
            throw TaskStoreError.invalid("清单超过 50 MB，操作未执行；请先精简任务。")
        }
        return data
    }

    private static func decode(_ data: Data) throws -> StoreDocument {
        guard data.count <= maximumDataBytes else { throw TaskStoreError.invalid("清单超过 50 MB，无法读取。") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        struct Header: Decodable { let version: Int }
        let version = try decoder.decode(Header.self, from: data).version
        guard version == 1 || version == 2 else { throw TaskStoreError.invalid("此备份版本暂不支持。") }
        decoder.userInfo[.storeVersion] = version
        return try validate(decoder.decode(StoreDocument.self, from: data))
    }

    /// Shared by every new/edited candidate, export, persistence and import/reopen.
    private static func validate(_ original: StoreDocument) throws -> StoreDocument {
        var document = original
        guard document.version == 1 || document.version == 2 else { throw TaskStoreError.invalid("此备份版本暂不支持。") }
        guard !document.categories.isEmpty, document.categories.count <= maximumCategories else {
            throw TaskStoreError.invalid("请保留 1 至 \(maximumCategories) 个分类，操作未执行。")
        }
        document.categories = document.categories.map(trim)
        guard document.categories.allSatisfy({ !$0.isEmpty && $0.count <= maximumCategoryLength }) else {
            throw TaskStoreError.invalid("分类名称须为 1 至 \(maximumCategoryLength) 字，操作未执行。")
        }
        guard Set(document.categories).count == document.categories.count else {
            throw TaskStoreError.invalid("已有同名分类，请换一个名称。")
        }
        guard document.items.count <= maximumTasks else {
            throw TaskStoreError.invalid("最多支持 \(maximumTasks) 条任务，操作未执行。")
        }
        guard Set(document.items.map(\.id)).count == document.items.count else {
            throw TaskStoreError.invalid("清单包含重复任务标识，操作未执行。")
        }
        let categorySet = Set(document.categories)
        for index in document.items.indices {
            document.items[index].title = trim(document.items[index].title)
            document.items[index].category = trim(document.items[index].category)
            guard !document.items[index].title.isEmpty, document.items[index].title.count <= maximumTitleLength else {
                throw TaskStoreError.invalid("待办标题须为 1 至 \(maximumTitleLength) 字，操作未执行。")
            }
            guard categorySet.contains(document.items[index].category) else {
                throw TaskStoreError.invalid("任务所用分类不存在，操作未执行。")
            }
            guard document.items[index].createdAt.timeIntervalSinceReferenceDate.isFinite,
                  document.items[index].hasValidDeadline else {
                throw TaskStoreError.invalid("任务日期无效，操作未执行。")
            }
        }
        guard document.preferences.idleOpacity.isFinite else { throw TaskStoreError.invalid("透明度须为有效数字。") }
        document.preferences.idleOpacity = min(1, max(0.15, document.preferences.idleOpacity))
        return document
    }
}
