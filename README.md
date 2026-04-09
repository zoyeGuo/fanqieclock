# FanqieClock

一个原生 macOS 的顶部刘海专注岛，参考了 Nook X 一类的交互形态，目前先聚焦两件事：

- 番茄钟
- Todoist 今日任务

项目使用 `SwiftUI + AppKit` 构建，主屏会尽量贴合真实刘海，副屏或无刘海屏幕会自动生成模拟刘海，并共享同一套番茄与任务状态。

## 当前能力

- 顶部刘海式收起 / 展开交互
- 主屏真实刘海贴合，副屏自动模拟刘海
- 三栏展开布局：
  - 今日任务
  - 专注统计
  - 番茄钟
- 番茄钟外环拖拽设时
- 点击中心开始 / 暂停
- Todoist `today` 任务读取
- 在任务列表中直接勾选完成 Todoist 任务
- 今日 / 本周专注统计持久化
- 可选强提醒和提醒声音
- Swift Package 可执行程序与 Xcode `.app` 两种运行方式

## 当前交互

- 收起态：
  - 在有刘海的屏幕上尽量与系统刘海重合
  - 在无刘海屏幕上显示模拟刘海
- 展开态：
  - 鼠标移入刘海区域展开
  - 鼠标移出后自动回收
  - 三个小组件保持统一高度
- 番茄钟：
  - 拖动外环设定时长
  - 点击中心开始或暂停
- 今日任务：
  - 支持滚动查看全部任务
  - 点击勾选可直接调用 Todoist API 完成任务

## 技术栈

- Swift 6
- SwiftUI
- AppKit
- Swift Package Manager
- Xcode project

## 项目结构

```text
Sources/fanqie/
  AppDelegate.swift
  AppSettings.swift
  CompletionOverlayController.swift
  DialWidgetView.swift
  DisplayMetrics.swift
  FanqieApp.swift
  FloatingPanelController.swift
  FloatingWidgetRootView.swift
  FocusStatsStore.swift
  SettingsWindowController.swift
  TodayTasksStore.swift
  TodayTasksWindowController.swift
  TimerStore.swift
  TodoistClient.swift
```

## 本地运行

### 方式 1：终端直接运行 Swift Package

适合日常快速调 UI。

```bash
cd "/Users/guoziyi/Documents/New project 2/fanqie"
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" \
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift build

./.build/arm64-apple-macosx/debug/fanqie
```

### 方式 2：Xcode 运行 `.app`

```text
FanqieClock.xcodeproj
```

1. 用 Xcode 打开 `FanqieClock.xcodeproj`
2. 选择 `FanqieClock` scheme
3. 点击 `Run`

### 方式 3：终端打包可见目录下的 `.app`

```bash
cd "/Users/guoziyi/Documents/New project 2/fanqie"
mkdir -p dist
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project FanqieClock.xcodeproj \
  -scheme FanqieClock \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./.release-build \
  CONFIGURATION_BUILD_DIR="$PWD/dist" \
  build
```

生成后的应用位于：

```text
dist/FanqieClock.app
```

## Todoist 配置

项目通过环境变量 `TODOIST_API_TOKEN` 读取 Todoist token。

### 终端运行时

```bash
export TODOIST_API_TOKEN="your_todoist_token"
```

### 从桌面直接打开 `.app` 时

```bash
launchctl setenv TODOIST_API_TOKEN "your_todoist_token"
```

然后完全退出 `FanqieClock.app` 再重新打开。

如果要清掉：

```bash
launchctl unsetenv TODOIST_API_TOKEN
```

## 现在这个版本更适合什么

- 想把番茄钟和 Todoist 放到顶部常驻区域
- 主屏和副屏都希望有一致的“灵动岛”体验
- 希望在一个界面里同时看到：
  - 今日任务
  - 专注统计
  - 当前番茄状态

## 说明

- 当前版本已经从最早的桌面悬浮挂件，演进为顶部刘海式交互形态。
- 动画和视觉细节还在继续打磨中，但整体交互、任务联动和专注统计已经可用。
