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

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var category: String
    var status: TodoStatus = .todo
    var dueDate: Date? = nil
    var createdAt: Date = Date()
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
    var version: Int = 1
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
    @Published var preferences = AppPreferences() {
        didSet {
            guard !isLoading else { return }
            guard preferences.idleOpacity.isFinite else {
                preferences = oldValue
                lastError = "透明度须为有效数字，已保留原设置。"
                return
            }
            // Avoid a malformed imported value making the window inaccessible.
            let safe = min(1, max(0.15, preferences.idleOpacity))
            if safe != preferences.idleOpacity { preferences.idleOpacity = safe }
            persist()
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

    init(directory: URL? = nil, seedExamples: Bool = true) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AtAGlance", isDirectory: true)
        do {
            try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: dataFileURL.path) {
                do {
                    let document = try Self.decode(Data(contentsOf: dataFileURL))
                    categories = document.categories
                    items = document.items
                    preferences = document.preferences
                } catch {
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
        if !fileManager.fileExists(atPath: dataFileURL.path), lastError == nil { persist() }
    }

    func sortedItems(for status: TodoStatus) -> [TodoItem] {
        let calendar = Calendar.current
        return items.filter { $0.status == status }.sorted {
            let first = $0.dueDate.map { calendar.startOfDay(for: $0) } ?? .distantFuture
            let second = $1.dueDate.map { calendar.startOfDay(for: $0) } ?? .distantFuture
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

    func delete(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        remember()
        items.removeAll { $0.id == id }
        persist()
    }

    func setStatus(_ id: UUID, _ status: TodoStatus) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].status != status else { return }
        remember()
        items[index].status = status
        persist()
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

    func deleteCategory(_ name: String) {
        guard categories.contains(name) else { return }
        guard categories.count > 1 else {
            lastError = "请至少保留一个分类。"
            return
        }
        remember()
        categories.removeAll { $0 == name }
        for index in items.indices where items[index].category == name { items[index].category = categories[0] }
        persist()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        categories = snapshot.categories
        items = snapshot.items
        canUndo = !undoStack.isEmpty
        persist()
    }

    func exportData(to url: URL) throws {
        try Self.encode(document).write(to: url, options: .atomic)
    }

    /// Import replaces the active list only after full validation; the operation is undoable.
    func importData(from url: URL) throws {
        let document = try Self.decode(Data(contentsOf: url))
        // Machine-specific window/login choices remain local when importing tasks.
        var candidate = document
        candidate.preferences = preferences
        try commit(candidate)
    }

    private var document: StoreDocument { StoreDocument(categories: categories, items: items, preferences: preferences) }

    private func remember() {
        undoStack.append(StoreSnapshot(categories: categories, items: items))
        if undoStack.count > 30 { undoStack.removeFirst() }
        canUndo = true
    }

    /// Only prepares a candidate: validation and undo happen before any live mutation.
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
        let data = try Self.encode(validated)
        remember()
        categories = validated.categories
        items = validated.items
        persist(encoded: data)
    }

    private func persist(encoded: Data? = nil) {
        guard !isLoading, !persistenceBlocked else { return }
        do {
            // Validate before touching the previous successful document or its backup.
            let data = try encoded ?? Self.encode(document)
            if fileManager.fileExists(atPath: dataFileURL.path) {
                let previous = try Data(contentsOf: dataFileURL)
                try previous.write(to: directory.appendingPathComponent("tasks.backup.json"), options: .atomic)
            }
            try data.write(to: dataFileURL, options: .atomic)
        } catch {
            lastError = "保存失败，请导出备份并检查磁盘空间或目录权限。\(error.localizedDescription)"
        }
    }

    private static func trim(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static let maximumDataBytes = 50_000_000
    private static let maximumCategories = 100
    private static let maximumCategoryLength = 100
    private static let maximumTasks = 100_000
    private static let maximumTitleLength = 10_000

    private static func encode(_ document: StoreDocument) throws -> Data {
        let document = try validate(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Foundation's lossless Date representation retains subsecond edits and ordering.
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
        return try validate(decoder.decode(StoreDocument.self, from: data))
    }

    /// Shared by every new/edited candidate, export, persistence and import/reopen.
    private static func validate(_ original: StoreDocument) throws -> StoreDocument {
        var document = original
        guard document.version == 1 else { throw TaskStoreError.invalid("此备份版本暂不支持。") }
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
                  document.items[index].dueDate?.timeIntervalSinceReferenceDate.isFinite ?? true else {
                throw TaskStoreError.invalid("任务日期无效，操作未执行。")
            }
        }
        guard document.preferences.idleOpacity.isFinite else { throw TaskStoreError.invalid("透明度须为有效数字。") }
        document.preferences.idleOpacity = min(1, max(0.15, document.preferences.idleOpacity))
        return document
    }
}
