import SwiftUI
import AppKit
import ServiceManagement

// Use the established property wrapper with the command-line SDK.
// macOS 27 also exports a same-named macro whose plugin ships with Xcode.
typealias LocalState<Value> = SwiftUI.State<Value>

enum PaperStyle {
    static let ink = Color(red: 0.22, green: 0.23, blue: 0.22)
    static let secondary = Color(red: 0.43, green: 0.44, blue: 0.42)
    static let accent = Color(red: 0.33, green: 0.42, blue: 0.33)
    static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)
}

struct SmallIcon: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @LocalState private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .background(hovered ? Color.black.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(PaperStyle.secondary)
        .onHover { hovered = $0 }.help(help).accessibilityLabel(help)
    }
}

struct TodoPanelView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var controller: PanelController
    @LocalState private var collapsed = Set<String>()
    @LocalState private var input = ""
    @LocalState private var selectedCategory = "work"
    @LocalState private var draftDue: Date? = nil
    @LocalState private var showingDate = false
    @LocalState private var editing: TodoItem?
    @FocusState private var inputFocused: Bool

    private var visibleItems: [TodoItem] { store.sortedItems(for: controller.activeStatus) }
    private var pendingCount: Int { store.items.filter { $0.status == .todo }.count }

    var body: some View {
        Group {
            if controller.compact { compactView }
            else { expandedView }
        }
        .foregroundStyle(PaperStyle.ink)
        .background { GlassBackground().overlay(Color(red: 0.98, green: 0.975, blue: 0.95).opacity(0.44)) }
        .clipShape(RoundedRectangle(cornerRadius: controller.compact ? 13 : 14, style: .continuous))
        .preferredColorScheme(.light)
        .onAppear {
            if !store.categories.contains(selectedCategory) { selectedCategory = store.categories.first ?? "work" }
        }
        .onChange(of: inputFocused) { controller.setInteracting("input", $0) }
        .onChange(of: input) { _ in controller.didEdit() }
        .onChange(of: draftDue) { _ in controller.didEdit() }
        .onChange(of: selectedCategory) { _ in controller.didEdit() }
        .onChange(of: controller.focusRequest) { _ in inputFocused = true }
        .onChange(of: showingDate) { controller.setInteracting("date", $0) }
        .onChange(of: editing) { controller.setInteracting("edit", $0 != nil) }
        .onChange(of: store.categories) { categories in
            if !categories.contains(selectedCategory) { selectedCategory = categories.first ?? "work" }
        }
        .popover(item: $editing, arrowEdge: .leading) { item in
            TaskEditor(item: item, categories: store.categories, error: store.lastError,
                       onSave: { if store.update($0) { editing = nil } },
                       onDelete: { if store.delete(item.id) { editing = nil } }, onCancel: { editing = nil })
        }
    }

    private var compactView: some View {
        HStack(spacing: 9) {
            Image(systemName: "checklist").font(.system(size: 13))
                .frame(width: 20, height: 30).overlay(DragHandle())
            Button { controller.show() } label: {
                HStack(spacing: 8) {
                    Text("to-do").font(.system(size: 12, weight: .medium, design: .monospaced))
                    Spacer(minLength: 0)
                    Text("\(pendingCount)").font(.system(size: 11, design: .monospaced)).foregroundStyle(PaperStyle.secondary)
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }.frame(maxHeight: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("展开待办，共 \(pendingCount) 项")
        }
        .padding(.horizontal, 16).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var expandedView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("to-do").font(.system(size: 11, weight: .medium, design: .monospaced))
                    Text("/ \(pendingCount)").font(.system(size: 10, design: .monospaced)).foregroundStyle(PaperStyle.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 32).overlay(DragHandle())
                SmallIcon(symbol: controller.pinned ? "pin.fill" : "pin", help: "保持清晰显示") { controller.togglePin() }
                SmallIcon(symbol: "minus", help: "收起待办") { controller.minimizeToPill() }
                Menu {
                    Button("添加待办", action: { inputFocused = true })
                    Button("撤销上一次操作", action: { store.undo() }).disabled(!store.canUndo)
                    Divider()
                    Button("设置与分类…", action: { controller.onSettings?() })
                    Button("导出备份…", action: { controller.onExport?() })
                    Button("导入备份…", action: { controller.onImport?() })
                    Divider()
                    Button("隐藏待办", action: { controller.panel.orderOut(nil) })
                    Button("退出常在待办", action: { NSApp.terminate(nil) })
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12)).frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("更多操作").accessibilityLabel("更多操作")
            }
            .padding(.leading, 18).padding(.trailing, 10).padding(.top, 5)

            HStack(spacing: 2) {
                ForEach(TodoStatus.allCases) { status in
                    Button {
                        controller.activeStatus = status
                        inputFocused = false
                    } label: {
                        Text(status.title)
                            .font(.system(size: 9.5, weight: status == controller.activeStatus ? .semibold : .regular, design: .monospaced))
                            .foregroundStyle(status == controller.activeStatus ? PaperStyle.ink : PaperStyle.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(status == controller.activeStatus ? Color.white.opacity(0.74) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(status == controller.activeStatus ? .isSelected : [])
                    .accessibilityLabel("\(status.title)，\(store.items.filter { $0.status == status }.count) 项")
                }
            }
            .padding(.horizontal, 15).padding(.top, 4).padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(store.categories, id: \.self) { category in
                        let tasks = visibleItems.filter { $0.category == category }
                        if !tasks.isEmpty || controller.activeStatus == .todo {
                            categorySection(category, tasks: tasks)
                        }
                    }
                    if visibleItems.isEmpty && controller.activeStatus != .todo {
                        VStack(spacing: 10) {
                            Image(systemName: emptySymbol).font(.system(size: 22, weight: .ultraLight))
                            Text(emptyTitle).font(.system(size: 11))
                            Text("右键任务可更改状态").font(.system(size: 10)).foregroundStyle(PaperStyle.secondary)
                        }
                        .foregroundStyle(PaperStyle.secondary).frame(maxWidth: .infinity).padding(.top, 66)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 7).padding(.bottom, 16)
            }
            .scrollIndicators(.hidden).frame(maxHeight: .infinity)

            if let error = store.lastError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).lineLimit(3)
                    Spacer(minLength: 0)
                    Button { store.lastError = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .font(.system(size: 10)).foregroundStyle(.red).padding(10)
            }
            entryView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        switch controller.activeStatus {
        case .todo: return "把下一件事放在这里"
        case .pending: return "没有暂停的任务"
        case .completed: return "完成的任务会留在这里"
        case .cancelled: return "没有已取消的任务"
        }
    }
    private var emptySymbol: String {
        switch controller.activeStatus {
        case .todo: return "plus"
        case .pending: return "pause.circle"
        case .completed: return "checkmark.circle"
        case .cancelled: return "minus.circle"
        }
    }

    private func categorySection(_ category: String, tasks: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                if collapsed.contains(category) { collapsed.remove(category) } else { collapsed.insert(category) }
            } label: {
                HStack(spacing: 6) {
                    Text(category).font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Text("\(tasks.count)").font(.system(size: 9, design: .monospaced)).foregroundStyle(PaperStyle.secondary.opacity(0.85))
                    Spacer()
                    Image(systemName: collapsed.contains(category) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 7, weight: .medium)).foregroundStyle(PaperStyle.secondary)
                }
                .padding(.vertical, 3).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("\(category)，\(tasks.count) 项，\(collapsed.contains(category) ? "展开" : "折叠")")
            if !collapsed.contains(category) {
                if tasks.isEmpty {
                    Button { selectedCategory = category; inputFocused = true } label: {
                        Text("+ 添加待办").font(.system(size: 10)).foregroundStyle(PaperStyle.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 19).padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }
                ForEach(tasks) { item in
                    TaskRow(item: item, onToggle: {
                        store.setStatus(item.id, item.status == .completed ? .todo : .completed)
                    }, onEdit: { editing = item }, onState: { store.setStatus(item.id, $0) },
                    onDelete: { store.delete(item.id) })
                }
            }
        }
    }

    private var entryView: some View {
        VStack(spacing: 7) {
            Rectangle().fill(PaperStyle.ink.opacity(0.08)).frame(height: 0.5)
            HStack(spacing: 7) {
                Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(PaperStyle.secondary)
                TextField("Add new todo…", text: $input)
                    .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced))
                    .focused($inputFocused).onSubmit(addTask)
                    .onExitCommand { inputFocused = false; controller.panel.makeFirstResponder(nil) }
                    .accessibilityLabel("添加待办，回车保存")
                Button(action: addTask) { Image(systemName: "return").font(.system(size: 11)).frame(width: 22, height: 24) }
                    .buttonStyle(.plain).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("回车添加").accessibilityLabel("添加待办")
            }
            HStack(spacing: 7) {
                Menu {
                    ForEach(store.categories, id: \.self) { category in
                        Button(category) { selectedCategory = category }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedCategory)
                        Image(systemName: "chevron.down").font(.system(size: 6))
                    }.font(.system(size: 9, design: .monospaced))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("新增任务的分类")
                Button { showingDate.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.system(size: 9))
                        if let date = draftDue { Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits)).font(.system(size: 9, design: .monospaced)) }
                    }
                }
                .buttonStyle(.plain).help("设置截止日期").accessibilityLabel("新增任务的截止日期")
                .popover(isPresented: $showingDate) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("截止日期").font(.headline)
                        DatePicker("日期", selection: Binding(get: { draftDue ?? Date() }, set: { draftDue = $0 }), displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden()
                        HStack {
                            Button("无截止日期") { draftDue = nil; showingDate = false }
                            Spacer()
                            Button("确定") { if draftDue == nil { draftDue = Date() }; showingDate = false }.keyboardShortcut(.defaultAction)
                        }
                    }.padding(16).frame(width: 280)
                }
                Spacer()
                if store.canUndo {
                    Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward").font(.system(size: 10)) }
                        .buttonStyle(.plain).help("撤销上一次操作").accessibilityLabel("撤销上一次操作")
                }
                Text("return ↵").font(.system(size: 8, design: .monospaced)).foregroundStyle(PaperStyle.secondary)
            }
            .foregroundStyle(PaperStyle.secondary)
        }
        .padding(.horizontal, 18).padding(.bottom, 13)
    }

    private func addTask() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard store.add(title: input, category: selectedCategory, dueDate: draftDue) else { return }
        input = ""; draftDue = nil
        controller.activeStatus = .todo
        collapsed.remove(selectedCategory)
    }
}

struct TaskRow: View {
    let item: TodoItem
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onState: (TodoStatus) -> Void
    let onDelete: () -> Void
    @LocalState private var hovered = false
    private var overdue: Bool {
        item.status != .completed && item.status != .cancelled &&
            item.dueDay.map { $0 < (CivilDay.string(from: Date()) ?? $0) } == true
    }
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Button(action: onToggle) {
                Image(systemName: item.status == .completed ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(item.status == .completed ? PaperStyle.accent : PaperStyle.secondary)
                    .frame(width: 13, height: 17)
            }
            .buttonStyle(.plain).help(item.status == .completed ? "恢复为待办" : "标记完成")
            .accessibilityLabel("\(item.status == .completed ? "恢复" : "完成")：\(item.title)")
            Button(action: onEdit) {
                Text(item.title).font(PaperStyle.mono).lineSpacing(3)
                    .strikethrough(item.status == .completed || item.status == .cancelled, color: PaperStyle.secondary.opacity(0.7))
                    .foregroundStyle(item.status == .completed || item.status == .cancelled ? PaperStyle.secondary : PaperStyle.ink)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 1)
            }.buttonStyle(.plain).help("点击编辑；右键更改状态")
            if let day = item.dueDay {
                Text(DeadlinePresentation.short(day))
                    .font(.system(size: 9, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(overdue ? Color(red: 0.66, green: 0.29, blue: 0.23) : PaperStyle.secondary)
                    .padding(.top, 3).help("截止：\(DeadlinePresentation.full(day))")
            }
        }
        .padding(.vertical, 3).padding(.horizontal, 4).padding(.leading, -4)
        .background(hovered ? Color.white.opacity(0.32) : .clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle()).onHover { hovered = $0 }
        .contextMenu {
            Button("编辑任务…", action: onEdit)
            Divider()
            ForEach(TodoStatus.allCases) { status in
                Button { onState(status) } label: {
                    Label(status.title, systemImage: item.status == status ? "checkmark" : status.symbol)
                }
            }
            Divider()
            Button("删除任务", role: .destructive, action: onDelete)
        }
    }
}

extension TodoStatus {
    var symbol: String {
        switch self {
        case .todo: return "square"
        case .pending: return "pause"
        case .completed: return "checkmark"
        case .cancelled: return "xmark"
        }
    }
}

struct TaskEditor: View {
    @LocalState var item: TodoItem
    let categories: [String]
    let error: String?
    let onSave: (TodoItem) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    @FocusState private var titleFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑待办").font(.headline)
            TextField("待办内容", text: $item.title, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...5).focused($titleFocused)
            Picker("分类", selection: $item.category) {
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }
            Picker("状态", selection: $item.status) {
                ForEach(TodoStatus.allCases) { Text($0.title).tag($0) }
            }
            Toggle("设置截止日期", isOn: Binding(get: { item.dueDay != nil }, set: { item.dueDate = $0 ? Date() : nil }))
            if item.dueDate != nil {
                DatePicker("截止日期", selection: Binding(get: { item.dueDate ?? Date() }, set: { item.dueDate = $0 }), displayedComponents: .date)
            } else if let day = item.dueDay {
                Text("截止日期：\(DeadlinePresentation.full(day))。当前时区没有此日期，原日期已保留。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("重新选择截止日期") { item.dueDate = Date() }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.help("删除任务，可撤销")
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存") { onSave(item) }.keyboardShortcut(.defaultAction)
                    .disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20).frame(width: 304).onAppear { titleFocused = true }
    }
}

struct SettingsView: View {
    @ObservedObject var store: TaskStore
    let onExport: () -> Void
    let onImport: () -> Void
    @LocalState private var categoryName = ""
    @LocalState private var renamingCategory: String?
    @LocalState private var renameText = ""
    @LocalState private var loginError: String?
    @LocalState private var launchEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            if let error = store.lastError {
                Section {
                    HStack(alignment: .top) {
                        Text(error).font(.caption).foregroundStyle(.red)
                        Spacer(minLength: 4)
                        Button { store.lastError = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).help("关闭提示")
                    }
                }
            }
            Section("窗口") {
                Toggle("始终置于其他窗口上方", isOn: $store.preferences.alwaysOnTop)
                Toggle("鼠标离开后收成小条", isOn: $store.preferences.collapseOnLeave)
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("离开后的不透明度"); Spacer(); Text("\(Int(store.preferences.idleOpacity * 100))%").monospacedDigit().foregroundStyle(.secondary) }
                    Slider(value: $store.preferences.idleOpacity, in: 0.18...0.85, step: 0.01)
                    Text("默认保留整张清单；鼠标移入时恢复清晰。图钉可保持清晰显示。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("登录 Mac 时启动", isOn: Binding(get: { launchEnabled }, set: setLogin))
                if let error = loginError { Text(error).font(.caption).foregroundStyle(.red) }
                if SMAppService.mainApp.status == .requiresApproval {
                    Button("前往系统设置允许登录项") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            Section("分类") {
                ForEach(store.categories, id: \.self) { category in
                    HStack {
                        if renamingCategory == category {
                            TextField("分类名称", text: $renameText).onSubmit(commitRename)
                            Button("保存", action: commitRename)
                            Button("取消") { renamingCategory = nil }
                        } else {
                            Text(category).font(.system(.body, design: .monospaced))
                            Spacer()
                            Button { renamingCategory = category; renameText = category } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless).help("重命名分类")
                            Button { store.deleteCategory(category) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).disabled(store.categories.count <= 1)
                                .help("删除分类，任务移到首个分类；可撤销")
                        }
                    }
                }
                HStack {
                    TextField("新增分类…", text: $categoryName).onSubmit(addCategory)
                    Button("添加", action: addCategory).disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Section("本地数据") {
                HStack {
                    Button("导出备份…", action: onExport)
                    Button("导入备份…", action: onImport)
                    Spacer()
                    Button("撤销操作") { store.undo() }.disabled(!store.canUndo)
                }
                Text("任务自动保存在此 Mac。导入会替换任务和分类，可以撤销。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding(.vertical, 6).frame(width: 470, height: 560)
        .preferredColorScheme(.light)
    }

    private func addCategory() { if store.addCategory(categoryName) { categoryName = "" } }
    private func commitRename() {
        guard let original = renamingCategory else { return }
        if store.renameCategory(original, to: renameText) { renamingCategory = nil }
    }
    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchEnabled = SMAppService.mainApp.status == .enabled
            store.preferences.launchAtLogin = launchEnabled
            loginError = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置中允许此登录项。" : nil
        } catch { loginError = "未能更改登录项：\(error.localizedDescription)"; launchEnabled = SMAppService.mainApp.status == .enabled }
    }
}
