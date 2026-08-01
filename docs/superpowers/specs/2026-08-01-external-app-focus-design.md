# 录制与回放外部应用焦点设计

## 目标

用户从其他应用切到 Clicker 并点击录制或回放后，Clicker 自动隐藏，焦点切回正确的外部应用。录制或回放结束、取消或失败后，Clicker 窗口自动恢复并取得焦点。

## 目标应用规则

Clicker 持续记录最近一次激活的外部应用。外部应用必须满足：

- bundle identifier 非空。
- bundle identifier 不是 Clicker 自身的 `local.rayscripts.clicker`。

录制目标始终是最近外部应用。该 bundle identifier 随录制生成的脚本持久化。

回放目标按以下优先级决定：

1. 脚本保存的目标应用存在且能成功激活时，使用保存目标。
2. 保存目标缺失、未运行或激活失败时，使用最近外部应用。
3. 两者均不可用时，不阻止回放，但不得声称已经激活目标。

## 外部应用追踪

新增 `ExternalApplicationTracking` 协议与 `SystemExternalApplicationTracker`：

- 监听 `NSWorkspace.didActivateApplicationNotification`。
- 初始化时读取当前前台应用；若为外部应用则记录。
- 后续只用合法外部应用更新 `mostRecentExternalBundleIdentifier`。
- Clicker 自身重新激活不能覆盖已记录的外部应用。
- 重复启动监听必须幂等。
- 追踪器由应用级协调器持有，与状态对象生命周期一致。

生产实现只保存 bundle identifier，不持有 `NSRunningApplication`，避免应用退出后的陈旧引用。

## 录制流程

录制启动顺序：

1. `AppState` 检查权限。
2. 从 tracker 读取最近外部应用，保存为本次录制目标快照。
3. 读取停止快捷键快照。
4. 显示 3、2、1 倒计时。
5. 隐藏 Clicker 普通窗口。
6. 主动激活本次录制目标；找不到或激活失败时使 Clicker 失活。
7. 倒计时完成后启动 EventRecorder 和录制指示层。

目标应用快照在倒计时开始后保持不变。倒计时期间其他应用激活通知不得改变本次录制目标。

录制结束、取消、event tap 失败或 recorder 启动失败时，关闭指示层并恢复 Clicker 窗口与焦点。录制成功生成脚本时写入目标 bundle identifier。

## 回放流程

点击回放后：

1. 检查权限、脚本与回放计划。
2. 获取 tracker 当前最近外部应用作为回退快照。
3. 隐藏 Clicker 普通窗口。
4. 尝试激活脚本保存目标；失败后尝试回退快照。
5. 完成焦点处理后才启动 PlaybackEngine。

PlaybackEngine 不再自行捕获 Clicker 作为“前一个应用”并在结束时恢复它。AppState 统一负责 Clicker 窗口生命周期，避免录制和回放出现两套互相竞争的恢复机制。

自然完成、用户停止、回放替换失败或应用终止清理后，Clicker 窗口恢复最多一次并取得焦点。迟到回调不能恢复或结束新的回放会话。

## 应用控制边界

录制与回放共享一个外部应用激活能力，但保留清晰接口：

- `mostRecentExternalBundleIdentifier`：读取最近外部应用。
- `activateExternalApplication(bundleIdentifier:) -> Bool`：尝试激活指定应用。
- `hideClicker()`：保持主窗口生命周期，同时透明、忽略鼠标并使 Clicker 失活。
- `restoreClicker()`：恢复主窗口并激活 Clicker。

激活使用 `NSRunningApplication.runningApplications(withBundleIdentifier:)` 查找运行实例，并调用 `activate(options: [.activateAllWindows])`。本功能不自动启动尚未运行的应用。

## 错误与边界处理

- 没有最近外部应用：录制和回放继续，Clicker 隐藏并失活。
- 保存目标等于 Clicker：视为无效，转用最近外部应用。
- 保存目标激活失败：尝试最近外部应用；两者相同时不重复激活。
- 最近外部应用已经退出：激活返回失败，但不阻止录制或回放。
- 倒计时取消或启动失败：恢复 Clicker，不能留下透明主窗口。
- 回放自然结束和显式停止竞争时：仅第一次完成恢复操作。

## 测试策略

严格执行 RED、GREEN、REFACTOR。自动测试不得切换真实应用或投递真实键鼠输入。

追踪器测试：

- 初始化捕获外部前台应用。
- 忽略 Clicker 自身与空 bundle identifier。
- 外部应用激活更新最近值。
- Clicker 再激活保留原值。
- 重复 start 不重复注册观察者。

录制控制测试：

- 最近外部应用在隐藏 Clicker 前被快照。
- 顺序为读取目标、显示倒计时、隐藏 Clicker、激活目标。
- 目标激活失败仍使 Clicker 失活。
- 倒计时期间 tracker 更新不改变脚本目标。
- 取消、启动失败、tap 失败与正常停止均恢复 Clicker。

回放控制测试：

- 保存目标优先于最近外部应用。
- 保存目标激活失败时回退。
- 保存目标与回退相同只尝试一次。
- 启动引擎前已隐藏 Clicker并完成目标激活。
- 自然完成和显式停止恢复 Clicker一次。
- 迟到完成不影响替代回放。

最终验证包括完整 `swift test`、`swift build`、Release bundle 重建、plist 与签名校验，以及真实应用间录制和回放焦点切换的人工验收。

## 工程约束

- Swift 5.9、SwiftUI、AppKit，macOS 14+。
- 不引入第三方依赖。
- 所有 Swift 文件少于 800 行。
- 不修改 TCC、`.netrc` 或 Git identity。
- 不执行远程 Git 操作。
- `.omc/` 与 `docs/superpowers/clicker-handoff.md` 保持未跟踪。
- 测试不得向系统投递真实键鼠输入或真实切换应用。
- 精确暂存任务文件并使用 Conventional Commits。
