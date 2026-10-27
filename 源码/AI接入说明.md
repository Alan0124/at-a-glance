# 从 AI 聊天或命令行添加待办

常在待办提供一个本地、仅允许添加任务的桥接。它没有内置 AI 模型，也不会把任务上传到服务器。AI 助手需要具有在你的 Mac 上运行命令的能力，才能把你确认要加入的事项交给本工具。

## 直接使用

在本目录运行：

```sh
./todo add '买咖啡' --category life --due 2026-10-28
./todo add '完成报告' --category work
./todo add '买 咖啡 & 茶+点心' --category life --print-url
./todo --help
./todo add --help
```

`--print-url` 仅输出地址用于检查，不启动应用、不添加任务。执行普通 `add` 时，脚本通过系统的 `/usr/bin/open` 将 URL 交给交付目录中的 `常在待办.app`，由正在运行的同一应用实例处理。

标题必填；分类默认 `work`，新分类会自动创建。日期可省略；提供时须为真实存在的 `YYYY-MM-DD` 日期，按年月日保存，切换时区后保持不变。若当前时区曾跳过某个历史日期，新增指令会明确拒绝该日；已有清单中的日期仍会保留。

请保持交付目录结构：

```text
桌面待办/
  常在待办.app
  源码/
    todo
```

## 给本地 AI 助手的指令

可以把以下要求放入助手的工具说明或聊天中：

> 当我明确要求把事项加入桌面待办时，使用本机 `/Users/alan/Desktop/GitHub项目/桌面待办/源码/todo` 脚本。例如通过进程参数数组调用 `todo add 任务标题 --category work --due 2026-10-28`。不要把任务标题拼接为未转义的 shell 命令。不要默认给任务添加日期；只有我提供日期或日期已在对话中明确时才传 `--due`。脚本只负责添加，不能读取、修改或删除现有任务。

如果助手只能够展示文字或打开网页，不能运行本机命令，可让它生成下面的 URL，由你在 Mac 上打开。文字中的空格、中文、`&`、`+` 等须进行 URL 百分号编码；推荐用 `urllib.parse.urlencode(params, quote_via=urllib.parse.quote)`，不要直接拼接用户输入。

```text
ataglance://add?title=%E4%B9%B0%E5%92%96%E5%95%A1&category=life&due=2026-10-28
```

支持的参数仅为 `title`、`category`、`due`。重复参数、未知参数、空标题、非法日期和删除等其他命令都会被拒绝。通过 URL 传入的待办与手动新增一样保存在本机，并支持撤销。

运行 `./test-automation.sh` 可验证 Swift 解析器及命令行编码；测试不启动应用。
