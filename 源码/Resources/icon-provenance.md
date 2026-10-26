# 图标与界面截图来源

## 应用图标

- 源文件：`Resources/GenerateIcon.swift`。
- 方式：使用 AppKit 的几何路径绘制圆角底、纸片、勾线、方框和横线；按各尺寸输出 PNG，再由系统 `iconutil` 打包为 `AppIcon.icns`。
- 产物：`Resources/AppIcon.iconset/*.png`、`Resources/AppIcon.icns`，以及构建应用包中的图标副本。
- 来源：本项目代码绘制；没有下载照片、第三方图标素材、原作图标或使用图像生成工具。
- 界面里的功能符号来自系统 SF Symbols；菜单栏使用系统 `checklist` 模板符号。

## 界面预览

`.impeccable/review/expanded.png`、`idle.png`、`compact.png`、`settings.png` 等是运行中的 SwiftUI/AppKit 应用通过本机原生工具截取的界面截图，不是 ImageGen 生成图或设计效果图。截图中的任务文本用于演示与验证；指针等系统叠加物不属于应用设计。

## 视频参考

视觉方向来自用户提供的小红书视频 `6ad82106000000002b01e4be`，只用于观察界面特征。来源、可见事实与证据局限记录于 `reference.md`；项目未复制原作二进制、源代码或图标素材。
