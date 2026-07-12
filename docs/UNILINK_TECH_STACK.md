# UniLink Control 技术栈记录

更新时间：2026-07-09

## 产品定位

UniLink Control 基于 RustDesk 改造，目标是做一个跨 Windows、macOS、Android 的远控与跨设备协作工具。当前优先级是稳定远控、文件拖拽/传输、SSH 终端、自动更新，以及后续的 Mac 无缝窗口模式。

## 客户端与界面

- Flutter：主界面、首页、设置页、远控页面、文件管理、SSH 终端 UI。
- Dart：Flutter 业务逻辑、设置项读写、设备列表、终端与文件交互入口。
- Apple Glass 风格 UI：当前 UniLink 桌面端视觉方向，浅色、玻璃质感、克制阴影、macOS 感。
- Penpot：用于 UI 原型和视觉方向探索，先出设计，再落到 Flutter。

## 远控核心

- RustDesk/Rust：远控核心、连接、视频、输入、服务端能力、更新逻辑。
- Flutter FFI / bridge：Flutter 前端与 Rust 后端通信。
- RustDesk 公共服务能力：用于远控发现、中继和基础连接。

## Windows 端

- Flutter Windows Desktop：桌面客户端壳。
- Win32 / C++ runner：窗口、原生拖拽、安装与启动相关能力。
- PowerShell 脚本：本地构建、部署到当前用户安装目录。
- MSI / 安装脚本：后续正式安装包和自动更新链路的一部分。

## macOS 端

- Flutter macOS Desktop：Mac 客户端壳。
- Rust/macOS 捕获与输入：远控服务端能力。
- AppleScript：当前用于 Finder 选中文件读取、窗口枚举/激活等辅助能力。
- SSH/SFTP：当前用于 Windows 与 Mac 间的终端、文件直传、Finder 选中文件下载。
- SMB：用于 Windows 自动挂载 Mac 共享盘。
- 后续 Mac 无缝窗口模式：先做远控画面裁剪和输入坐标映射，真正单窗口采集后续可能走 ScreenCaptureKit。

## Android 端

- Flutter Android：移动端客户端 UI。
- Android Kotlin/Java service：常驻服务、悬浮窗、启动广播等 Android 能力。
- 当前 Android 重点：远控和基础连接；系统级磁盘挂载不作为短期目标。

## 更新与发布

- GitHub Releases：Windows 与 macOS 的自动更新来源。
- `latest.json` / 更新 manifest：记录版本、下载资源、哈希等。
- GitHub Actions：后续用于自动构建和发布安装包。
- 现阶段本地部署脚本：`scripts/update_user_build.ps1`。

## 设计与实现原则

- 首页只放高频入口：远控、文件传输、SSH、我的设备。
- Mac 窗口模式不是首页独立模式，而是远控中的一种高级能力。
- 设置页必须区分“真的能保存的开关”和“只是当前能力状态”，避免出现假按钮。
- 用户默认不需要懂技术术语，界面文案要按产品语言解释功能。
