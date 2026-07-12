# UniLink Control 开发交接文档

更新时间：2026-07-04  
仓库：`D:\agents\codex\hanako-control\client\rustdesk`

## 一句话目标

用户想要的是一个“傻瓜式跨设备控制工具”：Windows、Mac、手机之间能稳定远控；Windows 文件可以直接拖进 Mac；Mac 文件可以拿回 Windows；后续 Mac 应用窗口最好像本地窗口一样无缝使用。

用户不懂技术，需求表达可能模糊。下一轮继续开发时请先按产品经理方式翻译需求，再落到工程实现，不要要求用户给专业术语。

## 当前重要状态

- 工作区非常脏，很多文件已经改过，不要 `git reset --hard`，不要回滚不确定来源的改动。
- 当前用户版已部署到：
  - `C:\Users\温工\AppData\Local\Programs\UniLink Control\UniLink Control.exe`
- 最近一次部署成功，安装目录中：
  - `librustdesk.dll` 更新时间约为 `2026-07-04 17:10:49`
  - `data` 更新时间约为 `2026-07-04 17:11:43`
- 用户桌面快捷方式历史上有：
  - `C:\Users\Public\Desktop\UniLink Control.lnk`
  - 用户目录桌面也可能有 `UniLink Control.lnk`

## 已经实现的功能

### 1. Windows -> Mac 拖文件上传

入口：远控 Mac 时，把 Windows 文件拖进远控画面。

当前行为：

- 优先走 SSH/SFTP 直传到 Mac。
- 目标目录优先取 Mac Finder 的 `insertion location`。
- 取不到 Finder 目录时 fallback 到 Mac 的 `~/Downloads`。
- 如果 SSH/SFTP 直传失败，再打开原来的文件传输窗口。

关键文件：

- `flutter/lib/hanako/remote_drop_uploader.dart`
- `flutter/lib/desktop/pages/remote_page.dart`
- `src/lang/cn.rs`
- `src/lang/en.rs`

### 2. Mac -> Windows 选中文件下载

入口：远控 Mac 时，在 Mac Finder 里先选中文件，然后用 UniLink 的下载/拖出入口。

当前行为：

- 通过 SSH + AppleScript 读取 Finder selection。
- 通过 SFTP 下载到 Windows：
  - `Downloads\UniLink Control\<device>\<timestamp>`
- 下载后会打开本地文件夹。
- 远控画面右下角有“先在 Mac 选中文件，再点这里”。
- 准备完成后可点/拖“拖到 Windows”。

关键文件：

- `flutter/lib/hanako/remote_selection_downloader.dart`
- `flutter/lib/hanako/windows_file_drag.dart`
- `flutter/lib/desktop/pages/remote_page.dart`
- `flutter/windows/runner/flutter_window.cpp`
- `flutter/lib/common/widgets/toolbar.dart`

### 3. Windows 原生拖出

当前已做 Windows 端 OLE/CF_HDROP 拖拽支持。

关键文件：

- `flutter/lib/hanako/windows_file_drag.dart`
- `flutter/windows/runner/flutter_window.cpp`

说明：

- 当前不是直接捕捉 Mac Finder 原生拖拽路径。
- 当前产品路径是“Mac Finder 选中文件 -> UniLink 准备 -> Windows 端原生拖出”。
- 真正无感拖出还需要更深的远端文件路径识别或远端 agent 配合。

### 4. SSH 终端

当前已有 Flutter 侧 SSH 终端实现，使用 `dartssh2` + `xterm`。

关键文件：

- `flutter/lib/hanako/ssh_terminal.dart`
- `flutter/lib/hanako/endpoint_resolver.dart`
- `flutter/pubspec.yaml`

默认 Mac 配置：

- user: `hp`
- password: `123456`
- host 候选由 resolver 决定，包含 `192.168.137.2` 和旧地址 `169.254.178.183`

### 5. 磁盘挂载

当前已有 Windows 自动挂载 SMB 盘逻辑。

关键文件：

- `flutter/lib/hanako/drive_mounter.dart`
- `flutter/lib/hanako/endpoint_resolver.dart`
- `flutter/lib/desktop/pages/remote_page.dart`

当前策略：

- 只在 Windows 客户端执行系统盘符挂载。
- 默认 Mac share 名：`UniLinkDrive`
- 默认盘符逻辑在 `drive_mounter.dart`。
- 如果盘符被其他盘占用，不强删，显示中文提示。

### 6. Mac 窗口模式 v1/v2

当前已做两层：

1. 列出 Mac 可见应用窗口，并能切到前台。
2. 可以点击“打开独立窗口”，新开一个 UniLink 远控窗口，并携带所选 Mac 窗口信息。

当前不是最终真单窗口采集。现在只是“单窗口模式骨架”：

- 新远控窗口标题会显示 Mac 窗口名。
- 新远控窗口左上角显示“Mac 窗口模式预览”。
- 会传递 appName/title/pid/index/x/y/width/height/visible。

关键文件：

- `flutter/lib/hanako/mac_window_mode.dart`
- `flutter/lib/common/widgets/toolbar.dart`
- `flutter/lib/common.dart`
- `flutter/lib/desktop/pages/desktop_home_page.dart`
- `flutter/lib/utils/multi_window_manager.dart`
- `flutter/lib/desktop/pages/remote_tab_page.dart`
- `flutter/lib/desktop/pages/remote_page.dart`

## 新增/重点 Hanako 模块

目录：`flutter/lib/hanako`

- `control_client.dart`：设备/控制服务客户端。
- `control_settings.dart`：控制相关设置。
- `device_list_panel.dart`：设备列表 UI。
- `drive_mounter.dart`：Windows SMB 盘符挂载。
- `endpoint_resolver.dart`：每设备 host/IP 候选解析、端口探测、last-success host。
- `mac_window_mode.dart`：Mac 窗口枚举、激活、独立窗口模式入口。
- `public_server.dart`：公共服务器相关配置。
- `remote_drop_uploader.dart`：Windows 拖入 Mac 的 SFTP 直传。
- `remote_selection_downloader.dart`：Mac Finder selection 下载到 Windows。
- `ssh_terminal.dart`：SSH profile、host key 校验、终端 UI。
- `top_device_dropdown.dart`：顶部设备列表。
- `windows_file_drag.dart`：Windows 原生文件拖出 MethodChannel。

## 验证过的命令

Flutter/Dart 路径：

```powershell
D:\tools\flutter\bin\cache\dart-sdk\bin\dart.exe
D:\tools\flutter\bin\flutter.bat
```

Dart analyze 示例：

```powershell
& D:\tools\flutter\bin\cache\dart-sdk\bin\dart.exe analyze flutter\lib\hanako\mac_window_mode.dart flutter\lib\common\widgets\toolbar.dart flutter\lib\common.dart flutter\lib\desktop\pages\desktop_home_page.dart flutter\lib\utils\multi_window_manager.dart flutter\lib\desktop\pages\remote_tab_page.dart flutter\lib\desktop\pages\remote_page.dart
```

最近一次结果：

- exit code 0
- 只有旧 Flutter API 的 info 级提示，例如 `withOpacity`、`WillPopScope`、`MaterialStateProperty` 等。

格式化：

```powershell
& D:\tools\flutter\bin\cache\dart-sdk\bin\dart.exe format <files>
```

用户版部署：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\update_user_build.ps1
```

最近一次部署成功：

- Flutter Windows build 成功。
- Rust release build 成功。
- 启动了新 `UniLink Control` 进程。
- 构建日志中的 Rust warning 和 file_picker warning 是旧问题，不是本轮功能失败。

## 下一步建议开发顺序

### P0：先实测基础体验

需要用户配合 Mac 在线，按下面顺序测：

1. Windows 连 Mac 远控是否稳定。
2. Windows 文件拖进远控画面，Mac 是否收到文件。
3. Mac Finder 选中文件，右下角准备拖出，Windows 是否能拖出文件。
4. 顶部菜单进入 Mac 窗口模式，是否能列出窗口。
5. 点“打开独立窗口”，是否打开新 UniLink 远控窗口并显示预览提示。

### P1：Mac 单窗口模式真正裁剪

当前只是携带窗口 metadata。下一步要做：

1. 在 `RemotePage` 中识别 `widget.macWindowTarget != null`。
2. 裁剪远控画面到 `(x, y, width, height)`。
3. 把本地鼠标坐标映射回 Mac 全桌面坐标：
   - local x -> `target.x + scaledLocalX`
   - local y -> `target.y + scaledLocalY`
4. 处理 DPI/缩放/多显示器坐标差异。

风险：

- 当前远控图像渲染和输入坐标可能在 `ImagePaint`、`CanvasModel`、`InputModel` 等层处理。
- 不要只做视觉裁剪而忘了输入映射，否则点的位置会错。

### P2：真正单窗口采集

更理想路线是 Mac 被控端使用系统 API 采集指定窗口：

- macOS 新路线：ScreenCaptureKit。
- 老路线：CGWindowListCreateImage 可尝试，但权限和性能不一定好。

这属于更底层 Rust/macOS server-side 改造，不能只在 Flutter UI 完成。

### P3：更无感的文件拖出/拖入

当前“Mac -> Windows”依赖 Finder selection。真正无感拖出需要：

- 能从远端拖拽动作识别出 Finder 选中文件路径，或
- 在 Mac 被控端 agent 里监听/暴露拖拽文件路径，或
- 做一个 UniLink 文件面板替代系统 Finder 原生拖拽。

短期产品建议：

- 把右下角提示做成更强引导：“先在 Mac 选中文件，然后点这里准备拖回 Windows”。
- 准备完成后，让拖出 chip 更明显。

## 已知限制

- Android 暂不做系统级磁盘挂载，只做远控和 SSH 更现实。
- 当前 SSH 只做 LAN/可达 IP 直连，不走 RustDesk relay 隧道。
- 当前 Mac 窗口模式不是最终无缝，只是独立远控窗口 + metadata + 预览提示。
- 当前公共 RustDesk 服务器可用于远控发现/relay，但 SMB/SSH/磁盘挂载仍要求网络层可达或另做隧道。
- Mac 上无屏/重启后是否可连，取决于服务自启动、权限、网络/IP、无人值守密码等配置。

## 常用检查命令

查看 UniLink 进程：

```powershell
Get-Process | Where-Object { $_.ProcessName -like '*UniLink*' } | Select-Object ProcessName,Id,Path | Format-Table -AutoSize
```

查看用户安装目录：

```powershell
Get-ChildItem -Force -LiteralPath "C:\Users\温工\AppData\Local\Programs\UniLink Control" | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize
```

查看工作区状态：

```powershell
git -c safe.directory=D:/agents/codex/hanako-control/client/rustdesk status --short
```

## 给下个对话的开场建议

可以直接说：

> 继续 UniLink Control。先读 `docs/UNILINK_HANDOFF_2026-07-04.md`，不要重置工作区。下一步优先做 Mac 窗口模式的画面裁剪和输入坐标映射，或者按我当时测试结果先修基础远控/拖文件问题。

