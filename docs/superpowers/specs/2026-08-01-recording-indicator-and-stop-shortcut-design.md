# 录制指示层与自定义停止快捷键设计

## 目标

Clicker 在倒计时结束并成功开始录制后，为所有显示器显示红色呼吸边框，并在主屏顶部显示当前停止快捷键。用户可以在主窗口的录制设置弹窗中将停止手势配置为单键或组合键；默认仍为 Esc。

## 范围

本功能包括：

- 所有显示器上的录制中红色呼吸边框。
- 主屏顶部的“正在录制 · 按 … 停止”提示。
- 主窗口工具栏中的录制设置弹窗。
- 停止快捷键的捕获、校验、持久化、显示和恢复默认。
- EventRecorder 对自定义停止手势的检测与过滤。
- 录制成功、停止、失败和取消路径中的指示层生命周期。

本功能不包括：

- 录制过程中动态修改停止快捷键。
- 录制过程中响应显示器热插拔或排列变化；下一次录制使用最新屏幕布局。
- 自定义红框颜色、动画速度、边框宽度或提示位置。
- 修改现有全局“开始/停止录制”和“开始/停止回放”快捷键。

## 录制指示层

新增 `RecordingIndicatorPresenting` 协议和 AppKit 实现 `RecordingIndicatorController`。`AppState` 只负责在状态切换时调用 `show(shortcut:)` 与 `close()`，不直接管理窗口。

`RecordingIndicatorController` 为 `NSScreen.screens` 中的每块屏幕创建一个透明、无边框、不抢焦点、忽略鼠标的 `NSPanel`：

- panel 覆盖对应屏幕的完整 frame。
- panel 在 Clicker 失活时仍显示，并可出现在所有桌面空间和全屏应用之上。
- 内容层绘制圆角红色边框，透明度缓慢往返变化，形成呼吸效果。
- 所有屏幕都显示边框。
- `NSScreen.main` 对应的 panel 额外在顶部安全区域显示胶囊提示。
- 其他屏幕不重复显示文字提示。
- panel 不成为 key/main window，不接收鼠标或键盘事件。

倒计时期间不显示录制指示层。只有 `EventRecorder.start()` 返回成功、`AppState.phase` 即将进入 `.recording` 时才显示。停止录制、event tap 失败或录制启动失败时必须关闭所有指示 panel。重复调用 `close()` 必须安全。

视觉固定为：红色圆角边框、柔和透明度呼吸动画、深色半透明顶部胶囊，以及白色提示文字。提示格式为“正在录制 · 按 {shortcut.displayName} 停止”。

## 停止快捷键模型与持久化

新增值类型 `RecordingStopShortcut`：

- `keyCode: UInt16`
- `modifierFlags: UInt64`
- `default` 为 keyCode 53、无修饰键，即 Esc。
- `displayName` 使用现有按键显示能力生成，例如 `Esc`、`F8`、`⌥⌘S`。
- 匹配时只比较设备无关修饰键集合，忽略 Caps Lock、数字键盘等非配置修饰状态。

新增 `RecordingStopShortcutStore`，使用 `UserDefaults` 持久化 keyCode 与修饰键。数据缺失或非法时回退到 Esc。生产代码共享同一个 store：录制开始时读取一次快照，并将该快照同时交给 EventRecorder 和录制指示层。录制过程中修改设置被 UI 禁止，因此一次录制的检测规则和提示文字保持一致。

## 快捷键捕获与校验

主窗口工具栏新增“录制设置”按钮，弹出录制设置面板。面板显示：

- 当前停止快捷键。
- “修改快捷键”按钮。
- 捕获状态提示。
- 校验错误或风险提示。
- “恢复默认 Esc”按钮。

捕获通过 SwiftUI/AppKit 本地按键事件完成，不注册新的系统全局热键。用户进入捕获状态后，下一次有效 keyDown 形成候选值。

校验规则：

- 仅按 Command、Option、Control、Shift 等修饰键不形成候选值。
- 单个非修饰键合法。
- 修饰键加一个非修饰键合法。
- 与现有全局录制快捷键 `⌥⌘R` 或回放快捷键 `⌥⌘P` 相同的候选值被拒绝，并显示错误。
- 无修饰键的字母、数字或空格键可以保存，但显示“可能影响正常文字录制”的风险提示。
- 保存成功后立即持久化，但只影响下一次录制。
- `.countdown`、`.recording` 和 `.playing` 阶段禁用修改入口。

## EventRecorder 行为

`EventRecorder.start(stopShortcut:)` 接收本次录制的停止快捷键快照。EventRecorder 对键盘事件执行以下顺序：

1. 跳过 Clicker 自己投递的 synthetic marker 事件。
2. 如果已经锁存停止请求，忽略后续事件。
3. 判断 keyDown 是否与停止快捷键的 keyCode 和规范化修饰键匹配。
4. 首次匹配时锁存停止请求，并在主线程调用一次 `onStopRequest`。
5. 过滤停止手势自身的 keyDown、autorepeat keyDown 和对应 keyUp，不写入 `RecordedEvent`。
6. 不匹配的键盘事件按现有逻辑正常录制。

停止手势是录制器级控制，不再硬编码 Esc。Esc 默认行为保持兼容。

## 状态与数据流

录制启动顺序：

1. `AppState` 检查权限并捕获目标应用。
2. `AppState` 从 store 读取停止快捷键快照。
3. 显示 3、2、1 倒计时。
4. 隐藏 Clicker 普通界面但保持 app 生命周期。
5. 倒计时完成后调用 `recorder.start(stopShortcut:)`。
6. 成功后显示录制指示层并进入 `.recording`。
7. 失败时关闭倒计时和指示层、恢复 Clicker 并回到 `.idle`。

录制停止顺序：

1. UI、菜单栏、全局录制快捷键或自定义停止手势请求停止。
2. EventRecorder 停止并生成 `RecordingCapture`。
3. 立即关闭录制指示层。
4. 按现有来源规则生成并保存脚本。
5. 恢复 Clicker 主窗口。

`AppState` 的停止与失败入口必须收敛到关闭指示层的共同路径，避免残留覆盖层。

## 错误处理

- UserDefaults 数据损坏或无法解码时回退到 Esc，不阻止应用启动。
- 快捷键冲突或候选无效时保留旧设置，并在弹窗中显示原因。
- 无法取得屏幕列表时不阻止录制；指示层为空，但菜单栏和停止快捷键仍可用。
- 某个 panel 创建失败不得影响其他屏幕；`close()` 清理所有已创建 panel。
- EventRecorder 启动失败时不得显示红框，并恢复 Clicker。

## 测试策略

严格执行 RED、GREEN、REFACTOR，每个生产行为先运行能因该行为缺失而失败的测试。

模型和持久化测试覆盖：

- 默认 Esc。
- 合法单键与组合键。
- 修饰键规范化和显示名称。
- UserDefaults 往返及非法数据回退。
- 全局快捷键冲突。
- 普通文字键风险提示。

EventRecorder 测试覆盖：

- 默认 Esc 和自定义单键停止。
- 组合键必须同时匹配 keyCode 与修饰键。
- 错误修饰键不停止。
- autorepeat 只请求停止一次。
- 停止手势的 down/up 不进入录制事件。
- 非停止键仍正常录制。

AppState 测试覆盖：

- recorder 启动成功后才显示指示层。
- 指示层收到与 recorder 相同的快捷键快照。
- UI、菜单栏、自定义快捷键、tap 失败和启动失败路径均关闭指示层。
- 倒计时取消时不显示指示层。

AppKit 窗口测试覆盖：

- 每块注入屏幕创建一个 panel。
- panel 不抢焦点并忽略鼠标。
- 所有 panel 显示红框，只有主屏显示文字提示。
- 失活、显式关闭和重复关闭的生命周期。

最终验证包括完整 `swift test`、`swift build`、Release app bundle 构建、plist 校验、签名校验、Git 状态检查，以及真实多显示器下的视觉和停止快捷键验收。自动化测试不得向系统投递真实键盘或鼠标输入。

## 工程约束

- Swift 5.9、SwiftUI、AppKit，macOS 14+。
- 不引入第三方依赖。
- 所有 Swift 文件少于 800 行，优先保持 200 至 400 行。
- 不修改 TCC、`.netrc` 或 Git identity。
- 不做远程 Git 操作。
- `.omc/` 和 `docs/superpowers/clicker-handoff.md` 保持未跟踪。
- 精确暂存当前任务文件，使用 Conventional Commits。
