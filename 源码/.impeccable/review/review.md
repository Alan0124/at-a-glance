# 1. Disposition

**SHIP。** 本轮限定的三项实质发现均为 **resolved**，没有仍需修复的同范围阻塞项。主清单、完成态、紧凑状态和设置的已见部分达到这一原生桌面小工具的交付水平，无需 rebuild。此判定不表示已运行验证窗口拖动、空闲淡出或编辑 popover 的外观；这些限制见第 5 节。

# 2. Evidence & scope

- 本次为独立原生 macOS 完成审查，只读源码和提供的截图，没有操作用户应用、浏览器或修改应用源码。最终 pass 仅复核首轮 F1—F3 的修复与同范围截图，没有扩展审查范围。
- 参考：`reference.md`、`PRODUCT.md`、`Surface.md`；代码：`Sources/AppMain.swift`、`Sources/Views.swift`、`Sources/Models.swift`、`Sources/Automation.swift`；另读模型/桥接测试、构建与 CLI 说明。
- 亲眼查看最终覆盖后的 `expanded.png`（344 × 436 pt）、`compact.png`（174 × 42 pt）、`settings.png`（470 × 560 pt），以及 `category-restart.png` 和先前的 `completed.png`。最终 expanded 只留三条初次教学任务；category-restart 是清理测试任务前的回归证据。未使用 `editor.png`：该原生窗口截图不包含独立 popover，不能证明编辑器外观。
- 按 Operate 与原生 macOS 使用场景判断。用户视频锁定视觉方向；不生成替代概念、不使用 HTML/CSS detector、不套用手机触控尺寸。Impeccable context 对 `macOS native desktop utility` 的字段值发出 web 回退警告；这只是工具元数据限制，不能改变实际 SwiftUI/AppKit 平台。
- 主 agent 提供的运行证据与本审查的亲见内容分开：中文粘贴添加、完成、编辑日期、删除、紧凑点击恢复及真实 CLI 桥接已测试；Cmd+Q 退出并重启后，含中文与 `&` 的桥接任务及 10/30 日期仍在，实际进程持久化通过。最终应用已成功编译、签名、启动；模型测试 **115 项断言**、解析器 **29 项断言**及 CLI 编码验证通过。本审查读了最终源代码和新增边界断言，没有重复运行测试或独立操作二进制。

# 3. Passing observations

- 清单符合视频可证实的世界：浅暖灰白面板、柔和圆角、无普通标题栏、等宽英文四状态、小写分类、小方框与短日期。344 pt 宽度内四个标签完整；最终教学任务及回归截图中的中文、短日期均未遮挡其他控件。
- 信息顺序清楚：状态在顶部，分组与任务居中，快速录入固定在底部。分组间距大于任务间距；完成态以选中方框和删除线表达，状态不只靠颜色。设置使用原生 Form 与 Toggle，独立于轻量清单。
- 四状态由同一枚举驱动标签、编辑与右键菜单；分类折叠、快速录入、日期、编辑、删除与撤销具有实际模型调用，没有只画不做的控件。主输入支持回车和 Escape，空标题被禁用或忽略。
- 任务、分类和偏好均有本地存储；原子写入、上一版备份、损坏文件原样保留与共享读写校验有明确实现。撤销覆盖任务与分类操作；分类删除会迁移任务并保留至少一类。拒绝候选文档发生在 live mutation、undo 和持久化之前。
- 源码以窗口 level 控制置顶，以图钉保持清晰，二者语义在设置说明中区分。默认只淡出整张清单，可选自动收成小条符合参考证据的边界。跨 Spaces、拖动、空闲动态均有代码路径；菜单栏提供显示、设置、备份与退出入口。此处不将这些代码路径冒称为完整运行验证。
- AI 桥接提供真实的仅添加 URL 处理和本地 CLI，中文、空格、`&`、`+` 有编码与解析覆盖；说明没有冒称已内置 AI 模型、云同步或聊天服务集成。

# 4. Material findings

## F1 · P1 · 写入与重开限制不一致 — resolved

原实现 `Models.swift` 的 `add`、`update`、`addCategory`、`renameCategory` 未执行 `decode` 的标题长度、分类长度和分类数量限制。它可以写出一个下次启动即被拒绝的 `tasks.json`，随后将原文件移为 unreadable 并显示空清单；原字节仍在，但日常使用会表现为任务消失。AI URL 的单字段限制也不能阻止新增第 101 个分类。

最终 `Models.swift:274` 的 `commit` 先调用共享 `validate` 并编码候选文档，成功后才记录 undo、更新 live state 和写入；`encode`、`decode` 都使用 `validate`。`add`、`update`、新增分类与重命名均走该候选提交。`Tests/ModelTests.swift:102` 起的新增断言覆盖 10001 字标题、101 字分类、第 101 类的显式/隐式新增与编辑，检查错误、items/categories、undo、磁盘 bytes 和重开结果；合法极限标题/分类及第 100 类可重开。最终 115 断言与重建结果已由主 agent 确认，原持久化缺陷闭环。

## F2 · P2 · 重启后复活已移除的 work 分类 — resolved

旧 `Views.swift` 仅在 categories 运行中变化时修正选择，遗漏首次载入。最终 `Views.swift:58` 的 `.onAppear` 把无效 `selectedCategory` 归一到现有首类，同时保留运行中的 `onChange`。主 agent 已将 work 重命名为 projects、Cmd+Q 后重启，再中文快速添加；亲见 `category-restart.png` 的底部选择为 projects，新增任务也在 projects，未出现 work。之后已撤销测试添加并改回 work；最终截图显示三条教学任务。源码与实际回归证据共同支持 resolved。

## F3 · P2 · 校验拒绝时清空/关闭用户草稿 — resolved

旧 `Views.swift` 在模型调用后无条件清空/关闭输入，不能处理共享校验的拒绝结果。最终模型的 `add`、`update`、`addCategory`、`renameCategory` 均返回 Bool；失败返回 false，幂等成功返回 true。新增测试明确覆盖这些返回值。

最终 `Views.swift:283` 的快速添加仅在 true 后清空文本与日期；`:68` 的编辑保存仅在 `update` 为 true 时关闭；`:474` 的分类新增/重命名也仅在成功后清空/结束。TaskEditor 的错误文本在 `:387`，Settings 的就地错误区域在 `:412`。因此原无条件草稿丢失路径已从源码消除，模型返回值有断言，最终二进制已编译通过。**限制：没有新的拒绝态 UI 运行截图，错误 popover 的视觉布局与实际焦点未验证；resolved 针对此处的逻辑缺陷，不扩大为错误界面全部视觉通过。**

三项状态汇总：**resolved 3 / partial 0 / unresolved 0**。没有同范围必须修复的剩余发现，也没有要求更换视觉方向或重做布局的发现。

# 5. Verification limitations

- 编辑器外观未获有效截图。已提供的 AX 运行记录只支持日期编辑与保存行为成功，不能支持对 popover 排版、全部字段、错误样式或边缘定位的视觉结论。
- 本审查未亲自操作应用；完整键盘/VoiceOver 路径、焦点可见性与系统辅助设置未测。截图可见文字未溢出，但没有对不同桌面背景及空闲透明态逐像素测量对比度。
- 截图只覆盖设置首屏，下方本地数据区在可滚动区域；不能据该截图判定它被裁掉，也不能确认滚动后的实际布局。
- **补充静态证据：** 已亲眼对比新增 `idle.png` 与最终 `expanded.png`。两张图保留相同三条教学任务与布局，idle 中容器、文字及控件整体明显变淡。结合主 agent 记录的取消 pin、Escape 离开输入、闲置后截屏过程，空闲自动淡出现已具有真实前后状态证据。静态图不能证明精确延迟、动画过程或鼠标进入后恢复，不能把它扩大为全部空闲交互运行通过；SHIP 与原三项 resolved 判定不变。
- 窗口拖拽、跨屏/Spaces、实际置顶、可选自动收起与鼠标悬停进入后恢复仍未完整验证。主 agent 多次模拟 drag 后 AX 树与 defaults frame 未动，当前原生自动化不能据此证明拖动成功，也不足以确定真实鼠标拖动失效。DragHandle 已显式配置 movable 与 acceptsFirstMouse；这里仍保留验证限制，不冒称通过。
- AppMain 已为 `NSMenu.didBeginTrackingNotification` / `didEndTrackingNotification` 增加 menu 交互 token，源码覆盖先前菜单打开时可能触发收起的风险。菜单在面板外停留超过 1.15 秒的实际动态仍未验证；未发现运行故障，不据此单独判 fix。
- 最终截图中有系统鼠标指针，完成态截图早于紧凑恢复按钮修复；已知修复与完成态外观无关，因此只将它用于完成态作用域。新的校验拒绝态未补抓视觉证据。
- **Questions skipped:** 本次为基于锁定视频方向的委托完成审查，问题已发送主 agent 处理，无需向最终用户再发概念或审批问题。
