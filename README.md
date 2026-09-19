# TinyWatchdog

一个用原生 **Swift + SwiftUI** 编写的 macOS 菜单栏系统监控小工具。

菜单栏常驻显示一个小狗图标，后面跟着当前勾选的指标。为了尽量少占宽度，每个指标排成**上下两行**（上排数值、下排名称），指标之间用 `｜` 分隔：

```
                12%   14%   46%   1.2M/s
       🐶   ｜ CPU ｜GPU ｜MEM ｜ 345K/s
                                  ↑ 上排：上行数据
                                  ↓ 下排：下行数据
```

点击图标弹出原生下拉菜单，可以随时开关要显示的指标、打开偏好设置、退出应用。

> 设计目标只有一个：**尽量省资源**。不显示的指标绝不采集，全部关闭时应用不做任何采样。

---

## 一、功能特性

- **菜单栏常驻**：最左侧小狗图案（App 图标），随后按顺序展示 CPU / GPU / 内存 / 网络上行 / 网络下行；每个指标上下两行（数值在上、说明在下），列间用 `｜` 分隔，紧凑省宽度。
- **下拉菜单控制**：5 个开关（CPU / GPU / 内存 / 网络上行 / 网络下行），勾选即显示、取消即隐藏；隐藏后完全不采集对应数据。网络的上行、下行是两个独立开关，但共用一次网卡读取。
- **偏好设置窗口**：使用 macOS 原生 `Settings` 场景（⌘, 可打开），可配置指标开关、刷新间隔、登录时启动、是否显示 Dock 图标。
- **菜单项顺序**：开关列表 → 分隔线 → 「偏好设置」（倒数第二）→ 「退出」（最后）。
- **登录时启动**：基于 `SMAppService` 的官方登录项注册，可在偏好设置里开关。
- **Dock 图标可切换**：默认显示 Dock 图标（`LSUIElement = NO`），也可在偏好设置里关掉，变成纯菜单栏工具。
- **无窗口、无后台进程**：不 fork 任何子进程（例如不用解析 `netstat`），全部通过系统接口读取。

---

## 二、技术栈

| 项目 | 选型 |
| --- | --- |
| 语言 | Swift 5（Xcode 27 默认 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`） |
| UI 框架 | SwiftUI（`MenuBarExtra` + `Settings` 场景） |
| 架构模式 | MVVM（Model / Service / ViewModel / View） |
| 响应式 | Combine（`ObservableObject` / `@Published` / `@ObservedObject`） |
| 系统接口 | Darwin / Mach（CPU、内存）、`getifaddrs`（网络）、IOKit（GPU） |
| 登录项 | ServiceManagement 的 `SMAppService` |
| 自绘菜单栏 | AppKit（`NSImage` / `NSAttributedString` 绘制两行标签） |
| 持久化 | `UserDefaults` |
| 部署目标 | macOS 27.0 |
| Bundle ID | `com.max.TinyWatchdog` |

---

## 三、目录结构

```
TinyWatchdog/
├── TinyWatchdog.xcodeproj/          # Xcode 工程（使用文件夹同步组，新增文件自动加入编译）
├── TinyWatchdog/
│   ├── TinyWatchdogApp.swift        # 入口：声明 MenuBarExtra 与 Settings 两个场景
│   ├── Assets.xcassets/             # 图标 / 强调色资源
│   │
│   ├── Models/                      # 【Model 层】纯数据结构与设置
│   │   ├── MetricType.swift         # 四个可开关指标的枚举（cpu/gpu/memory/network）
│   │   ├── SystemMetrics.swift      # 一次采样的数据快照（全部是可选值）
│   │   └── AppSettings.swift        # 用户偏好：显示哪些指标、刷新间隔、Dock 图标，负责存取 UserDefaults
│   │
│   ├── Services/                    # 【Service 层】采集系统数据 + 系统能力封装
│   │   ├── CPUCollector.swift       # CPU 占用率
│   │   ├── GPUCollector.swift       # GPU 占用率
│   │   ├── MemoryCollector.swift    # 内存占用率
│   │   ├── NetworkCollector.swift   # 网络上行 / 下行速率
│   │   ├── MetricsSampler.swift     # 采集调度器：按勾选项只调用需要的采集器
│   │   ├── LaunchAtLogin.swift      # 「登录时启动」开关（SMAppService）
│   │   └── DockIconController.swift # 运行时切换 Dock 图标显示 / 隐藏
│   │
│   ├── ViewModels/                  # 【ViewModel 层】
│   │   └── MenuBarViewModel.swift   # 持有采样结果 + 驱动采样循环
│   │
│   └── Views/                       # 【View 层】纯界面
│       ├── MenuBarLabelView.swift    # 菜单栏标签入口（数据变化 → 重新生成图片）
│       ├── MenuBarLabelRenderer.swift# 把指标画成「两行 + ｜分隔」的菜单栏图片
│       ├── MenuBarContentView.swift # 点击图标后的下拉菜单
│       ├── SettingsView.swift       # 偏好设置窗口内容
│       └── MetricFormatter.swift    # 数字 → 显示文字（百分比、速率）
```

---

## 四、架构与数据流

采用 MVVM，数据单向流动：

```
                 ┌─────────────────────┐
                 │  AppSettings        │  用户勾选项 / 刷新间隔（存 UserDefaults）
                 └──────────┬──────────┘
                            │ onChange 回调（设置变了）
                            ▼
   ┌──────────────┐   ┌─────────────────────┐   ┌──────────────┐
   │ MetricsSampler│──▶│ MenuBarViewModel    │──▶│ MenuBarLabel │ 菜单栏文字
   │  (采集数据)   │   │ @Published metrics  │   │  View        │
   └──────────────┘   └─────────────────────┘   └──────────────┘
                            ▲                          ▲
                            │                          │
                    ┌───────────────┐          ┌───────────────┐
                    │ SettingsView  │          │ MenuBarContent│ 下拉菜单
                    │ （偏好设置）   │          │  View         │
                    └───────────────┘          └───────────────┘
```

- **Model**：`MetricType`、`SystemMetrics`、`AppSettings`。
- **Service**：四个 Collector + 一个 Sampler，只负责“拿数据”，不认识界面。
- **ViewModel**：`MenuBarViewModel` 是唯一的状态中心，界面全部订阅它。
- **View**：只读状态、发动作，不直接调用系统接口。

### 谁通知谁

1. 用户在任意界面拨动开关 → 修改 `AppSettings.enabledMetrics`；
2. `AppSettings` 的 `didSet` 触发 `onChange` 回调（带原因：`.metrics` 或 `.interval`）；
3. `MenuBarViewModel` 收到回调后：
   - `.metrics`（指标集合变了）→ 取消旧循环、清空基线、重新开始；
   - `.interval`（只改刷新间隔）→ **保留现有数据和基线**，只换采样节奏，菜单栏数值不会闪 `--`；
4. 每次采样结果写入 `@Published var metrics` → SwiftUI 自动刷新菜单栏文字。

---

## 五、核心实现说明

### 1. 菜单栏：`MenuBarExtra`（`TinyWatchdogApp.swift`）

```swift
MenuBarExtra {
    MenuBarContentView(viewModel: viewModel, settings: viewModel.settings) // 点击后的下拉内容
} label: {
    MenuBarLabelView(viewModel: viewModel, settings: viewModel.settings)   // 常驻的图标+文字
}
.menuBarExtraStyle(.menu)   // 用原生菜单样式弹出
```

- `.menu` 样式让下拉内容渲染成和系统菜单一致的样子，`Toggle` 会显示成带勾选的菜单项。
- `label` 用一个 `Image(nsImage:)`：内容是 `MenuBarLabelRenderer` 现画的一张模板图（见下一节）。
- 图片设成 `isTemplate = true`，系统会按菜单栏文字颜色自动上色，浅色 / 深色模式都能看清。
- 文字用等宽数字字体绘制，数值刷新时菜单栏宽度不会抖动。

### 2. 菜单栏两行标签的绘制（`MenuBarLabelRenderer.swift`）

`MenuBarExtra` 的 label 对多行、任意 Stack 这类复杂布局支持有限，最稳的做法是**自己把内容画成一张图片**再交给它显示。

布局规则（每个指标一列，共两行；列间用 `｜` 分隔）：

| 指标 | 上排（数值） | 下排（说明） |
| --- | --- | --- |
| CPU | `12%` | `CPU` |
| GPU | `14%` | `GPU` |
| 内存 | `46%` | `MEM` |
| 网络上行 | `2M` | `UPLOAD` |
| 网络下行 | `345K` | `DOWN` |

实现要点：

- 用 `NSAttributedString.size()` 量出每列宽度，取上下行较宽者，保证列内内容水平居中；
- 用 `NSImage(size:flipped:drawingHandler:)` 创建图片，在 handler 里依次画小狗图标和各列文字；
- 上排 `y = 底行高度`、下排 `y = 0`，即下排在下、上排在上；
- 网络上行 / 下行各占一列，可独立开关；
- 小狗用 App 图标，垂直居中放在最左侧。

> 相关代码：`MenuBarLabelRenderer.swift`、`MenuBarLabelView.swift`。

### 3. 下拉菜单：`MenuBarContentView.swift`

- `Section` 分组显示 5 个 `Toggle`（CPU / GPU / 内存 / 网络上行 / 网络下行），直接绑定 `AppSettings.binding(for:)`。
- `Divider()` 分隔开关与操作按钮。
- 「偏好设置…」用 `@Environment(\.openSettings)` 打开：先 `NSApp.activate()` 激活应用再 `openSettings()`，避免窗口创建在后台看起来“点了没反应”。
- `Button { NSApp.terminate(nil) }` 退出整个应用（最后一个）。菜单栏应用没有窗口，必须显式退出。

### 4. 偏好设置：`Settings` 场景 + `SettingsView.swift`

- `Settings { SettingsView(...) }` 就是 macOS 原生首选项窗口，系统会自动处理它不出现在 Dock / 程序切换里。
- `Form` + `.formStyle(.grouped)` 得到经典的系统设置外观。
- 三组内容：**菜单栏显示**（显示图标、指标开关）、**采样**（刷新间隔）、**通用**（登录时启动、在 Dock 中显示图标）。
- 与下拉菜单共用同一个 `AppSettings` 实例，所以两处开关永远同步。

### 5. 各采集器原理

| 采集器 | 系统接口 | 原理 | 开销 |
| --- | --- | --- | --- |
| `CPUCollector` | `host_processor_info` | 内核为每个核心累加各状态 tick（只增不减）。用两次采样的差值算「非空闲 tick / 总 tick」。 | 微秒级 |
| `MemoryCollector` | `host_statistics64` | 读取 VM 页统计，`active + wired + compressed` 换算字节后除以物理内存总量。 | 微秒级 |
| `NetworkCollector` | `getifaddrs` | 读取每块网卡累计收发字节，按网卡缓存上次值求差，再除以时间得到字节/秒。排除回环 `lo0`。 | 微秒级，无子进程 |
| `GPUCollector` | IOKit `IOAccelerator` | 找到显卡加速器服务，读 `PerformanceStatistics` 字典里的 `Device Utilization %`。句柄找到后缓存复用。 | 首次稍慢，之后很轻 |

一些实现细节：

- **必须释放 C 接口分配的内存**：`host_processor_info` 返回的缓冲区用 `defer { vm_deallocate(...) }` 释放，否则会内存泄漏。
- **差值要处理回绕**：网卡计数是 32 位，万兆网卡数秒就回绕；用 `delta(current:previous:)` 补偿。CPU 用允许溢出的 `&-` 运算。
- **GPU key 兼容**：不同 GPU/驱动暴露的键名不同，依次尝试 `Device Utilization %` → `GPU Activity(%)` → `Renderer Utilization %`，读不到就返回 `nil`（界面显示 `--`）。
- **首次采样返回 `nil`**：CPU / 网络需要基线，第一次没有对比数据，界面显示 `--`，第二次起才准确。

### 6. 采样循环与「省资源」设计（`MenuBarViewModel.swift`）

没有使用 `Timer`，而是用**一个可取消的 `Task` 循环**：

```swift
loop = Task { [weak self] in
    while !Task.isCancelled {
        guard let self else { break }
        let enabled = self.settings.enabledMetrics
        self.metrics = self.sampler.sample(enabled: enabled)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}
```

- **全部关闭时直接 `return`**，连循环都不创建，CPU 占用归零。
- **按需采集**：`MetricsSampler.sample(enabled:)` 只调用被勾选的采集器，没勾选的完全不会触发系统调用。
- **`Task.sleep` 可取消**：设置一变，`loop?.cancel()` 立刻结束旧循环（sleep 会抛错退出），不会残留两个循环。
- **不同指标共享一次网络读取**：只要上行或下行任一被勾选，就只调用一次 `getifaddrs`。
- **默认 2 秒刷新**，间隔可在偏好设置里改，最小 0.5 秒做保护。

### 7. 格式化（`MetricFormatter.swift`）

- `percent(_:)`：`0.1234 → "12%"`，`nil → "0%"`。
- `rate(_:)`：整数 + 单位，不显示小数点，单位自动换档，**最小单位是 K**，取整用**向上取整**（有流量就 ≥1K）：`1536 → "2K"`、`512 → "1K"`、`0 → "0K"`、`1572864 → "2M"`；固定整数让菜单栏宽度稳定。

### 8. 设置持久化（`AppSettings.swift`）

- 勾选项以 `"cpu,gpu,memory"` 形式的字符串存进 `UserDefaults`，启动时解析还原成 `Set<MetricType>`。
- 刷新间隔、Dock 图标开关按各自类型存入 `UserDefaults`。
- 第一次运行默认全部指标打开、显示 Dock 图标。
- 提供 `Binding<Bool>` 给 `Toggle` 使用，读写都经过统一方法，方便集中处理“变化后重采样 / 切换激活策略”。

### 9. 登录时启动（`LaunchAtLogin.swift`）

- 使用 macOS 13+ 官方推荐的 `ServiceManagement.SMAppService`，不需要手写 `LaunchAgent` plist，也不要用已废弃的 `SMLoginItemSetEnabled`。
- 打开：`try SMAppService.mainApp.register()`；关闭：`try SMAppService.mainApp.unregister()`。
- **真实状态以 `SMAppService.mainApp.status` 为准**，不自己用 `UserDefaults` 记，否则用户在「系统设置 → 通用 → 登录项」里手动改了，界面会显示错误。
- 状态为 `.requiresApproval` 时提示用户去系统设置允许；`register()` 抛错时把系统错误显示在设置窗口。
- 注意：登录项注册要求 App 有正常签名，用 Xcode 运行时可用；未签名的命令行构建可能注册失败（会显示错误信息）。

### 10. Dock 图标开关（`DockIconController.swift`）

- 是否显示 Dock 图标由 **`NSApplication.setActivationPolicy`** 控制：
  - `.regular` → 显示 Dock 图标、出现在 ⌘Tab；`.accessory` → 纯菜单栏工具。
- **初始形态**由工程设置 `INFOPLIST_KEY_LSUIElement` 决定（现在是 `NO`，即默认显示 Dock 图标）。
- **运行时可切换**：`AppSettings.showDockIcon` 变化时调用 `DockIconController.apply(_:)`，并写入 `UserDefaults`。
- **下次启动**：`AppDelegate.applicationDidFinishLaunching` 调 `DockIconController.applySaved()` 读取并应用。
- 点击 Dock 图标时通过 `applicationShouldHandleReopen` 打开偏好设置窗口。

---

## 六、关键工程配置

这些设置在 `TinyWatchdog.xcodeproj/project.pbxproj` 中：

| 设置 | 值 | 作用 |
| --- | --- | --- |
| `INFOPLIST_KEY_LSUIElement` | `NO` | App 的**初始**形态：`NO` = 显示 Dock 图标。运行时可被 `DockIconController` 切换 |
| `ENABLE_APP_SANDBOX` | `NO` | 允许读取 IOKit 获取 GPU 数据（沙盒下 IOKit 受限） |
| `GENERATE_INFOPLIST_FILE` | `YES` | Info.plist 由构建设置自动生成，无需手写文件 |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor` | 类型默认主线程隔离，简化并发安全 |
| `MACOSX_DEPLOYMENT_TARGET` | `27.0` | 部署目标 |

工程使用了 **FileSystemSynchronizedRootGroup（文件夹同步）**：往 `TinyWatchdog/` 目录里新增 `.swift` 文件会自动加入编译，不需要手动往工程里拖。

---

## 七、构建与运行

### 用 Xcode

1. 打开 `TinyWatchdog.xcodeproj`；
2. 选择 `TinyWatchdog` scheme，⌘R 运行；
3. 运行后到菜单栏右上角找到 🐶 图标（Dock 里也会有一个图标，可在偏好设置里关掉）。

### 用命令行

```bash
# 调试构建
xcodebuild -project TinyWatchdog.xcodeproj -scheme TinyWatchdog \
  -configuration Debug -destination 'platform=macOS' build

# 发布构建
xcodebuild -project TinyWatchdog.xcodeproj -scheme TinyWatchdog \
  -configuration Release -destination 'platform=macOS' build
```

---

## 八、单位与约定

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `cpu` / `gpu` / `memory` | `Double?` | `0.0 ~ 1.0` 的占比（`nil` 表示暂无数据） |
| `upload` / `download` | `Double?` | 字节 / 秒（`nil` 表示暂无数据） |

界面显示时统一由 `MetricFormatter` 转换：占比显示成百分数，速率按大小显示成 `K/M/G/T` 每秒（最小单位是 `K/s`）。

---

## 九、已知限制与注意事项

- **左键 / 右键都会弹出菜单**：这是 SwiftUI `MenuBarExtra` 的原生行为，本项目未用 `NSStatusItem` 自绘，所以没有单独区分左右键。
- **GPU 数据依赖 IOKit**：个别机器或驱动可能不暴露 `PerformanceStatistics`，此时 GPU 显示 `--`。这也是关闭 App Sandbox 的原因。
- **菜单栏标签是自绘图片**：如果发现菜单栏空白，先确认 `MenuBarLabelRenderer` 能正确生成 `NSImage`；一个指标都没勾选时会退化成只显示小狗图标。
- **登录项注册需要签名**：用 Xcode 运行（自动签名）可正常注册；若用 `CODE_SIGNING_ALLOWED=NO` 的命令行构建，`register()` 可能失败并在设置窗口显示错误。
- **CPU / 网络首次显示 `--`**：需要两次采样才能算出速率，属正常现象。
