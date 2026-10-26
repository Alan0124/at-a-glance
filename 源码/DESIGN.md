---
name: 常在待办
description: 留在桌面旁的一张轻量玻璃清单
colors:
  ink: "rgb(22% 23% 22%)"
  secondary-ink: "rgb(43% 44% 42%)"
  completed-sage: "rgb(33% 42% 33%)"
  overdue-clay: "rgb(66% 29% 23%)"
  glass-tint: "rgb(98% 97.5% 95% / 44%)"
  selected-white: "rgb(100% 100% 100% / 74%)"
  row-hover-white: "rgb(100% 100% 100% / 32%)"
  icon-hover-shade: "rgb(0% 0% 0% / 6%)"
  divider-ink: "rgb(22% 23% 22% / 8%)"
typography:
  compact-title:
    fontFamily: "macOS system, monospaced design"
    fontSize: "12pt"
    fontWeight: 500
  body:
    fontFamily: "macOS system, monospaced design"
    fontSize: "11pt"
    fontWeight: 400
  group-label:
    fontFamily: "macOS system, monospaced design"
    fontSize: "10pt"
    fontWeight: 600
  navigation:
    fontFamily: "macOS system, monospaced design"
    fontSize: "9.5pt"
    fontWeight: 400
  detail:
    fontFamily: "macOS system, monospaced design"
    fontSize: "9pt"
    fontWeight: 400
  hint:
    fontFamily: "macOS system, monospaced design"
    fontSize: "8pt"
    fontWeight: 400
rounded:
  row: "4pt"
  control: "5pt"
  compact: "13pt"
  panel: "14pt"
spacing:
  micro: "3pt"
  control: "4pt"
  tight: "6pt"
  row: "7pt"
  group: "15pt"
  compact-inset: "16pt"
  entry-inset: "18pt"
  content-inset: "20pt"
components:
  panel-glass:
    backgroundColor: "{colors.glass-tint}"
    textColor: "{colors.ink}"
    rounded: "{rounded.panel}"
    width: "344pt"
    height: "436pt"
  panel-compact:
    backgroundColor: "{colors.glass-tint}"
    textColor: "{colors.ink}"
    typography: "{typography.compact-title}"
    rounded: "{rounded.compact}"
    padding: "0 16pt"
    width: "174pt"
    height: "42pt"
  status-tab:
    textColor: "{colors.secondary-ink}"
    typography: "{typography.navigation}"
    rounded: "{rounded.control}"
    padding: "7pt 0"
  status-tab-selected:
    backgroundColor: "{colors.selected-white}"
    textColor: "{colors.ink}"
    typography: "{typography.navigation}"
    rounded: "{rounded.control}"
    padding: "7pt 0"
  task-row:
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.row}"
    padding: "3pt 4pt"
  icon-button:
    textColor: "{colors.secondary-ink}"
    rounded: "{rounded.control}"
    size: "24pt"
  quick-entry:
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    padding: "0 18pt 13pt"
  task-editor:
    padding: "20pt"
    width: "304pt"
---

# Design System: 常在待办

## Overview

**Platform: macOS. Mode: Operate.** SwiftUI + AppKit 原生桌面工具；尺寸使用 macOS 逻辑点（pt）。

**Creative North Star: "桌面旁的一张轻清单"**

设计来源是用户提供的小红书视频，观察依据见 [reference.md](reference.md)。方向已由用户锁定：浅暖白半透明小面板、深灰小字、四个等宽状态标签、分组与方形复选框。这里记录已完成实现的视觉系统，不将视频里的摄影比例当作原作精确尺寸，也不推定原作使用了哪一种玻璃技术。

任务清单保持紧凑、安静，编辑与设置使用原生弹层和独立设置窗口。控件以熟悉的 Mac 行为完成操作，品牌感来自字距、分组节奏与克制的材质。菜单栏提供常驻入口，应用不显示 Dock 图标。

**Key Characteristics:**
- 暖白玻璃、石墨色文字、低饱和完成态。
- 英文状态与分类采用系统等宽字形，中文由系统字体回退。
- 分组间距大于任务行间距，快速录入固定在面板底部。
- 默认保留完整清单；可选收成小条，图钉用于保持清晰。

当前实现依据为 `Sources/Views.swift`、`Sources/AppMain.swift`、`Sources/Models.swift`。原生工具截图：[展开](.impeccable/review/expanded.png)、[空闲淡出](.impeccable/review/idle.png)、[小条](.impeccable/review/compact.png)、[设置](.impeccable/review/settings.png)。审查状态以 [review.md](.impeccable/review/review.md) 为准；本文不代替审查 verdict。截图不是生成图像。此项目没有 Web UI，因此不使用 HTML/CSS detector。

## Colors

浅暖中性色为主，颜色仅帮助辨认状态；前置 token 保留 SwiftUI 源码的 RGB 比例与透明度。

### Primary
- **Completed Sage / 完成鼠尾草绿**：完成方框的低饱和强调色，避免将整行染色。
- **Overdue Clay / 逾期陶土色**：仅标记未完成、未取消且已逾期的日期。

### Neutral
- **Graphite Ink / 石墨墨色**：任务正文、活动状态与主要标签。
- **Secondary Ink / 浅石墨色**：非活动状态、日期、计数、辅助符号与完成/取消文本。
- **Warm Glass Tint / 暖白玻璃覆色**：叠加于 AppKit 原生材质之上；它不是独立的不透明背景色。
- **Selected White / 选中白**：选中的状态标签。
- **Row Hover White / 行悬停白**、**Icon Hover Shade / 图标悬停灰**：局部反馈。
- **Divider Ink / 分隔墨色**：录入区上方的轻分隔线。

**The Status Rule.** 完成与取消同时使用删除线；完成还使用选中方框。不要只凭颜色传达状态。错误提示沿用原生语义红色，不把系统动态色固化为自造色值。

## Typography

主体为 macOS 系统字体的 monospaced design，保持视频中的打字机式小字感。没有展示型标题。设置、编辑器标题和系统控件采用 SwiftUI 语义字级，继承系统字体与本机指标。

### Hierarchy
- **Compact title**：小条的 `to-do` 标题，中等字重。
- **Body**：任务正文与快速录入；任务正文允许换行，额外行间距为源码中的 3pt。
- **Group label**：分类名，半粗体；分类计数另用 detail 字级。
- **Navigation**：四状态标签；活动项变为 semibold，字号不变。
- **Detail**：短日期、分类选择和计数；日期使用等宽数字。
- **Hint**：底部回车提示。符号采用 SF Symbols，不引入图标字体。

**The Small-Type Rule.** 小字服务于这张窄面板；扩展设置时沿用系统 Form 字级，不把任务清单的密度照搬到设置正文。

## Layout

已实现展开面板为 344 × 436pt，小条为 174 × 42pt，设置内容为 470 × 560pt。这些是本次实现值，不是测得的原作尺寸。面板默认放在主屏可见区域右上方，距上侧和右侧各 26pt；随后保存用户移动的位置，并在显示器变化时限制在可见区域内。

主面板依次为拖动与工具区、四状态栏、滚动清单、底部录入。状态栏使用等分宽度，标签间距 2pt；不能按文字长短分配宽度。清单水平内容边距使用 content-inset，分类间距使用 group；组内标题与任务间距 5pt。行内方框、正文、短日期横排，间距使用 row；正文可折行，日期保持短格式。

底部快速录入与分类/日期工具构成两行，始终留在滚动区之外。小条缩放以右上角为锚点，左侧符号区域用于拖动，正文区域用于展开。设置使用原生 grouped Form 和可滚动内容，不建立 Web 断点或响应式栅格。

## Elevation & Depth

主面板使用 `NSVisualEffectView` 的 `.popover` 材质、`.behindWindow` 混合、`.active` 状态和 Aqua 外观，叠加 glass-tint，外层裁切为 continuous 圆角。窗口背景透明，启用 AppKit 原生窗口阴影；系统控制阴影的具体外观，项目没有自定义阴影数值。

源码实现鼠标进入时恢复清晰，离开后延迟 1.15 秒，再用 0.28 秒动画变淡；默认空闲不透明度为 32%。设置滑块可调 18%—85%。图钉、文本输入、编辑、日期、菜单与文件对话框交互会阻止空闲淡出。减少动态效果将动画时长置零，减少透明度时保持不透明。展开与空闲的前后截图已证明闲置后的整体淡出状态；精确延迟、动画过程、鼠标进入恢复和自动收起动态仍未完整验证。

**The Native-Material Rule.** 保留原生玻璃与系统阴影，不用渐变、假背景截图或额外发光模拟桌面材质。

## Shapes

面板与小条使用连续圆角；任务行和状态标签使用更小圆角。方形 checkbox 使用 SF Symbols 的 `square` / `checkmark.square.fill`，与轻薄文字保持同一视觉尺度。图标按钮为固定方形命中区域，悬停底色只出现在局部。

编辑器、日期选择器、菜单、开关与设置分组沿用原生形状和焦点反馈，不通过自绘重置系统控件。资源图标使用几何纸片、方框和勾线，由 [GenerateIcon.swift](Resources/GenerateIcon.swift) 可重复生成；来源说明见 [icon-provenance.md](Resources/icon-provenance.md)。

## Components

### Status navigation

四个标签固定为 `To-do`、`Pending`、`Completed`、`Cancelled`，同一枚举驱动列表筛选、编辑和右键菜单。选中态使用 selected-white 与半粗字重；辅助技术标签包含任务数及选中状态。

### Group and task row

分类名、当前状态任务数与右侧展开符号组成可点击组头。空 To-do 分类显示轻量“+ 添加待办”；其他状态不显示空分类。任务左侧方框直接完成/恢复，点击任务文字进入编辑，右键更改状态或删除。同分类、同状态内的拖动排序有实现；实际拖动手势未被自动化可靠验证。

### Quick entry

无边框输入提示 `Add new todo…`；回车提交，空白标题不提交。下方选择分类与可选日期；成功添加后清空草稿，失败时保留输入与日期。新任务进入 To-do 并展开所在分类。按 Escape 结束输入焦点。

### Panel controls and compact strip

图钉保持清晰显示，和设置里的“始终置于其他窗口上方”是两个功能。减号手动收起；小条可点击恢复。更多菜单提供添加、撤销、设置、导入导出、隐藏与退出。菜单栏左键显示/隐藏，右键打开管理菜单；隐藏清单不退出应用。

### Editor and settings

点击任务文字打开编辑 popover，提供标题、分类、状态、可选截止日期、删除、取消与保存。校验失败时保持草稿并显示错误。设置分为窗口、分类、本地数据；登录启动默认关闭，必须由用户自行开启。设置里的分类删除会把任务移到首个现有分类，并保留至少一个分类。

## Do's and Don'ts

### Do:
- **Do** 将用户视频视为视觉来源，并区分观察事实与实现补充。
- **Do** 保持四状态等宽、任务正文可换行和底部录入固定。
- **Do** 使用原生 macOS 材质、SF Symbols、系统设置与编辑控件。
- **Do** 用错误提示和保留草稿支持用户修正失败的输入。
- **Do** 把截图证据、源码实现与实际运行验证分别表述。

### Don't:
- **Don't** 声称 344 × 436pt 是原视频应用的精确尺寸。
- **Don't** 把可选小条、菜单栏或 AI 桥接称为已证实的原作机制。
- **Don't** 让图钉和窗口置顶共用一个含糊语义。
- **Don't** 把原生动态的源码存在当成手势或透明效果已实测。
