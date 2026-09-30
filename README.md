<div align="center">

<img src="Assets/AppIcon.png" width="112" alt="WakeMac 应用图标">

<h1>WakeMac</h1>

<p><strong>合盖继续工作，完成后自动收尾。</strong></p>

[![Release](https://img.shields.io/github/v/release/OrxHsu/WakeMac?color=002FA7)](https://github.com/OrxHsu/WakeMac/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-15%2B-555555)](#下载与安装)
[![CI](https://github.com/OrxHsu/WakeMac/actions/workflows/compatibility.yml/badge.svg)](https://github.com/OrxHsu/WakeMac/actions/workflows/compatibility.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-002FA7.svg)](LICENSE)

**[下载应用](https://github.com/OrxHsu/WakeMac/releases/latest)** · **[功能清单](FEATURES.md)** · **[报告问题](https://github.com/OrxHsu/WakeMac/issues/new/choose)**

</div>

WakeMac 是一款原生 macOS 菜单栏工具，用来管理保持唤醒、合盖运行与工作结束后的休眠。你可以手动控制，也可以让它等到指定时间、应用退出、下载完成或命令执行成功后再收尾。

应用自带合盖服务，无需安装其他保活软件。界面采用浅色白银与克莱因蓝，提供主窗口和菜单栏快捷面板，目前支持简体中文。

![WakeMac 工作模式主界面](Assets/Screenshots/main-window.png)

## 核心功能

| 功能 | 可以做什么 |
| --- | --- |
| **工作模式** | 切换后台工作、桌面工作与正常休眠，直接控制保持唤醒和合盖运行。 |
| **工作会话** | 保持运行一段时间，或等到指定时间、应用／进程退出、所选下载完成；支持延长会话。 |
| **自动触发** | 根据应用、电源、电量、显示器、设备、网络、闲置状态或每周时间表开始工作。 |
| **自动收尾** | 定时恢复正常休眠，低电量时提醒并提供休眠保护。 |
| **命令任务** | 在终端式编辑区执行多行 zsh 命令；成功后倒计时 60 秒再请求休眠，失败时保留状态。 |
| **会话效果** | 控制显示器休眠和屏保，按需轻移鼠标或定期访问所选磁盘目录。 |
| **快捷操作** | 菜单栏面板、全局快捷键、AppleScript、系统通知、提示音与本机运行记录。 |

详细选项、行为限制和已验证范围见 [FEATURES.md](FEATURES.md)。

## 下载与安装

| 项目 | 要求 |
| --- | --- |
| 操作系统 | **macOS 15 或更新版本** |
| 芯片 | **Apple Silicon（M 系列）** |
| 发布包 | `WakeMac-1.0.0-arm64.zip` |

不支持 Intel Mac 或 macOS 14。

1. 从 **[GitHub Releases](https://github.com/OrxHsu/WakeMac/releases/latest)** 下载应用压缩包。
2. 解压，将 `WakeMac.app` 移到「应用程序」文件夹，即 `/Applications`。
3. 打开 WakeMac，通过菜单栏图标使用快捷面板；再次打开应用可显示主窗口。
4. 如需合盖工作，按下方的[服务启用步骤](#合盖服务与权限)完成一次系统批准。

> [!IMPORTANT]
> 当前下载包使用 **Apple Development 签名，尚未进行 Developer ID 公证**。首次打开可能被 macOS 阻止。确认下载来源后，可查看「系统设置 → 隐私与安全性」中的「仍要打开」选项；若系统仍拒绝运行，请提交 Issue，或使用自己的开发者证书从源码构建。

<details>
<summary>核对下载文件</summary>

同时下载发布页的 `SHA256SUMS.txt`，在两个文件所在的目录执行：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

显示 `WakeMac-1.0.0-arm64.zip: OK` 表示压缩包与发布的校验值一致。

</details>

## 开始使用

在主窗口的「工作模式」页或菜单栏面板选择模式：

| 模式 | 适合的场景 | 默认行为 |
| --- | --- | --- |
| **后台工作** | 合盖后继续编译、下载或运行任务 | 保持系统唤醒、允许熄屏，使用内置合盖服务。 |
| **桌面工作** | 开盖使用，暂时不希望 Mac 自动休眠 | 保持系统唤醒、允许熄屏，不启用合盖服务。 |
| **正常休眠** | 工作结束，恢复系统原有休眠行为 | 释放 WakeMac 的保活效果和合盖会话。 |

几个常见用法：

- **保持运行一小时**：在「工作会话」选择时长和工作模式，然后开始会话。
- **等下载完成再收尾**：选择下载结束条件，再选择正在下载的文件或 `.download` 包。
- **编译成功后休眠**：在「命令任务」选择工作目录、输入命令，点击「运行，成功后休眠」。
- **固定时段自动工作**：在「自动触发」创建每周时间规则，保存后启用。

开启「合盖继续运行」会同时保持唤醒；关闭合盖运行仍可保持桌面唤醒。关闭「保持唤醒」会一并结束合盖运行。

**结束工作会话会释放保活，恢复正常休眠；不会关闭应用或终止进程。**「立即休眠」、命令成功后的倒计时和低电量保护则会在核验通过后向系统请求休眠。

## 合盖服务与权限

桌面保持唤醒无需管理员权限。合盖运行需要批准应用自带的后台服务：

1. 确认 WakeMac 已放进 `/Applications`。
2. 在「工作模式」或菜单栏面板点击「启用合盖服务…」。
3. 在「系统设置 → 通用 → 登录项与扩展」批准 WakeMac；系统可能要求管理员认证。
4. 返回应用，选择「后台工作」。

合盖工作时请保持设备通风，避免放在包中持续高负载运行。移除服务前，应用会先恢复正常休眠。

**锁屏策略默认要求即时密码保护，也可在偏好设置中选择跟随系统设置。** 系统认证由用户本人完成，WakeMac 不读取或保存登录密码，也不自动解锁已锁定的 Mac。

轻移鼠标、Wi-Fi 和蓝牙相关功能只在用户显式启用或点击授权入口时请求对应权限；未授权或无法读取的状态不会被当作自动规则命中。

<details>
<summary>合盖服务如何工作</summary>

服务通过 Apple 的 `SMAppService` 登记，只接受同一 Apple 开发者签名的主程序调用固定电源接口，不接受任意命令或路径，不修改 sudoers。

主程序通过租约维持合盖会话。仅在有效租约下处理电池／接电切换造成的系统重置；断线、超时或退出后释放自己的会话。每次切换都会读取系统状态核验，失败不会显示为已启用。

合盖控制依赖系统 `SleepDisabled` 行为；`disablesleep` 并非 Apple 文档保证长期兼容的公开参数。电源切换后的恢复窗口也无法区分系统重置与其他程序同期关闭，需要停止保活时请在 WakeMac 结束工作。

</details>

## AppleScript

脚本、快捷键和界面共用相同的状态核验与收尾逻辑。例如，开始一个 30 分钟的桌面会话，再延长 15 分钟：

```applescript
tell application "WakeMac"
    start session mode "desktop" for minutes 30
    session status
    extend session for minutes 15
end tell
```

结束会话：

```applescript
tell application "WakeMac"
    end session
end tell
```

`mode` 可选 `desktop` 或 `background`；省略 `for minutes` 为无限期。完整命令见 [WakeMac.sdef](Resources/WakeMac.sdef)，包含显示器、屏保、合盖、自动规则和磁盘保活控制。

## 从源码构建

需要 Apple Silicon Mac、**Xcode 26+（macOS 26 SDK）**和 **Swift 6**。项目使用 SwiftUI、AppKit 和系统接口，没有第三方 Swift 库依赖。

```sh
git clone https://github.com/OrxHsu/WakeMac.git
cd WakeMac
git checkout v1.0.0
swift test --scratch-path /tmp/wakemac-test-build
./scripts/build-app.sh
```

产物位于 `/tmp/wakemac-dist/WakeMac.app`。默认使用 ad hoc 签名，可使用无需合盖服务的功能。启用合盖服务需要主程序和辅助程序使用同一 Apple Development 或 Developer ID 证书签名：

```sh
WAKEMAC_SIGN_IDENTITY='你的证书名称或 SHA-1' ./scripts/build-app.sh
```

可用 `WAKEMAC_BUILD_DIR` 和 `WAKEMAC_OUTPUT_DIR` 覆盖构建、输出目录。开发当前分支时可省略 `git checkout v1.0.0`。贡献流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 常见问题

<details>
<summary>为什么切到正常休眠后，Mac 仍没有睡眠？</summary>

正常模式只释放 WakeMac 自己的保活效果，之后由 macOS 决定何时休眠。其他应用的保活、系统闲置设置或正在进行的任务仍可能影响睡眠。需要立即休眠时，可使用 WakeMac 的「立即休眠」。

</details>

<details>
<summary>下载监测会读取 Safari 浏览记录吗？</summary>

不会。你需要手动选择下载文件或 `.download` 包，WakeMac 观察文件增长、完成重命名和稳定时长，不读取浏览记录或 Safari 私有下载元数据。

暂停的下载可能达到稳定阈值，重要传输可选择手动结束。系统未提供可判定进度时，应用不会推测百分比。

</details>

<details>
<summary>命令任务支持哪些命令？</summary>

支持非交互的前台 zsh 命令，包括多行脚本。不要使用 `&`、`nohup` 或需要密码输入的命令。WakeMac 只跟踪这里启动的前台 shell，不判断其他应用或 Codex 任务是否完成。

命令退出码为 0 时进入 60 秒休眠倒计时；失败则记录并通知。手动切模式或取消自动休眠后，原命令可继续运行。退出应用时若命令仍在运行，会提示等待。

</details>

<details>
<summary>数据保存在哪里？重启会恢复上次任务吗？</summary>

偏好、运行记录、命令日志和可选统计都保存在本机，不上传使用记录。运行记录与命令日志位于 `~/Library/Application Support/WorkModes/`；保留的内部 bundle ID 为 `local.orx.WorkModes`。

运行记录最多保存 200 条，命令输出日志最多保存前 5 MB。分享日志前请检查其中的私人信息。

重新打开应用默认恢复正常模式，不重放旧命令、下载或倒计时。可显式配置在启动／唤醒后开始一个新的默认会话。

</details>

## 反馈与贡献

遇到问题请使用 **[Issue 模板](https://github.com/OrxHsu/WakeMac/issues/new/choose)**，提供 WakeMac 版本、macOS 版本、芯片、复现步骤和预期／实际结果。界面问题可附截图；设备问题请补充设备或客户端型号。

GitHub Actions 在 ARM64 macOS 15 与 26 上运行测试和 Release 构建。真实合盖、首次授权与外接设备行为需要实际环境验证，不能由云端构建推定。外接设备、可移动磁盘和 Cisco 客户端的兼容问题按具体 Issue 处理。

[贡献指南](CONTRIBUTING.md) · [行为准则](CODE_OF_CONDUCT.md) · [安全问题私密报告](SECURITY.md) · [更新记录](CHANGELOG.md)

## License

本项目采用 **[GNU GPL v3，仅第 3 版（GPL-3.0-only）](LICENSE)**。允许使用、修改和商业分发。分发受 GPL 覆盖的程序或修改版时，须按 GPL v3 提供对应源码、保留版权和许可声明，并以相同许可授权受覆盖的作品。软件不提供担保，完整权利与义务以许可正文为准。

版权及资源范围见 [NOTICE](NOTICE)。随包字体继续采用独立的 [SIL Open Font License](Assets/Licenses/README.md)。
