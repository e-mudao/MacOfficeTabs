<p align="center"><img src="./Resources/IconDesign/MacOfficeTabs-icon-v1.png" width="104" alt="MacOfficeTabs 应用图标：带有蓝、绿、橙色标签的文档"></p>

# MacOfficeTabs

**为 macOS 上的 Word、Excel 和 PowerPoint 添加浮动文档标签。** 切换文档、调整顺序；窗口和保存操作仍由 Office 处理。

[下载](https://github.com/e-mudao/MacOfficeTabs/releases) · [English](README.md) · [功能说明](#标签栏如何工作) · [已知限制](#已知限制)

> [!IMPORTANT]
> **0.2.9（构建 18）是首个 GitHub Release。** Apple Silicon 版 DMG 使用 ad-hoc 签名，**未经 Apple 公证**；首次启动可能需要在系统设置中手动允许。兼容性验证仍在进行。

<p align="center"><img src="./assets/readme/tab-bar-concept.svg" width="100%" alt="示意图：Word 窗口顶部居中的浮动标签栏，包含三个文档标签和关闭按钮"></p>

*标签栏示意图，非应用实机截图。浮条出现在前台 Office 文档窗口内，不会把多个文档合并到同一个窗口。*

## 下载与安装

从 [GitHub Releases](https://github.com/e-mudao/MacOfficeTabs/releases) 下载 `MacOfficeTabs-0.2.9-build18-arm64.dmg`。安装包面向 **Apple Silicon（arm64）**，最低部署目标为 macOS 13；目前只验证了下表所列环境。Word、Excel 或 PowerPoint 需另行安装。安装 DMG 不需要 Xcode 或命令行工具。

1. 打开 DMG，将 **MacOfficeTabs.app** 拖到 **Applications（应用程序）**，再从“应用程序”启动。
2. 若 macOS 阻止打开，请先尝试启动一次，再到**系统设置 → 隐私与安全性 → 仍要打开**确认。DMG 未经公证，因此需要手动放行；这不代表 Apple 已验证应用。
3. 在初始的“Office 窗口诊断”中打开辅助功能设置，允许“应用程序”中的 MacOfficeTabs 控制电脑；返回应用点击“刷新”。
4. 打开 Office 文档并将编辑窗口置于前台，点击标签标题切换文档。

界面首次安装默认简体中文。如需英文，选择“MacOfficeTabs → 设置… → 语言 / Language → English”，切换立即生效，重启后保留。应用没有自动更新功能，后续版本需从 Releases 自行安装。

若应用无法识别 Office 窗口，参阅[权限详情](#权限详情)。开发者可[从源码构建](#从源码构建)。

## 标签栏如何工作

- **当前 Office 应用的文档标签。** Word、Excel 和 PowerPoint 分别维护文档列表与设置；其他应用在前台时隐藏标签栏。
- **窗口内的浮动栏。** 普通、铺满和原生全屏模式均显示在窗口内部顶部附近，可能覆盖少量 Office 工具栏。
- **点击切换，拖动排序。** 标签过多时可横向滚动，运行期短 ID 帮助区分同名文档。
- **原生关闭。** 标签 × 请求 Office 执行关闭，保存、放弃修改和取消均由 Office 原生提示处理。

快捷键和登录启动为可选功能，默认关闭；三个应用的标签栏默认开启。设置还提供中英文界面选择；窗口诊断可查看权限、文档候选、焦点核验与浮条显示状态。

## 环境要求与兼容性

| 项目 | 要求 / 已记录环境 |
| --- | --- |
| 最低部署目标 | macOS 13.0 及以上 |
| Release 下载包 | Apple Silicon（arm64）DMG；暂不提供 Intel 版本 |
| Office | 自行安装 Microsoft Word、Excel 或 PowerPoint |
| 必要权限 | MacOfficeTabs 的辅助功能控制权限 |
| 构建工具（仅源码构建） | Swift 工具版本 5.9 及以上；配备适用 macOS SDK 的 Xcode 或 Command Line Tools |
| 已记录实机环境 | Apple Silicon（arm64）、macOS 27.0.1（26A434）、Office 16.113.4 |

最低部署目标不代表全部版本兼容。Intel、其他 macOS / Office 版本、多物理屏和 Stage Manager 尚未验证。公开的兼容性摘要和剩余缺口见下方[已知限制](#已知限制)。

## 从源码构建

在仓库根目录执行：

```sh
bash scripts/build-app.sh
open build/MacOfficeTabs.app
```

构建脚本执行 release 编译，组装 `build/MacOfficeTabs.app`，签名并核验签名。未配置本地签名时使用 ad-hoc 签名。默认面向当前工具链架构构建，不是 Universal 通用应用构建。

如需固定本地开发签名身份，请在**构建和授权前**执行：

```sh
bash scripts/setup-dev-signing.sh
bash scripts/build-app.sh
open build/MacOfficeTabs.app
```

脚本在 `.dev-signing/` 中创建项目专用证书和钥匙串，不修改系统根信任、登录钥匙串或默认钥匙串。该目录包含私钥和凭据，已被 Git 忽略；切勿上传或分享。本地开发签名不等于 Developer ID 发行签名或公证。

## 权限详情

应用的初始窗口是“Office 窗口诊断”。点击其中的“打开辅助功能设置”可进入 macOS 的应用控制权限页面。旧版 macOS 通常位于“隐私与安全性 → 辅助功能”；已测 macOS 27 页面名为“设备控制和数据访问”。如果列表中没有 MacOfficeTabs，点击“＋”添加“应用程序”中的应用（源码构建则添加 `build/MacOfficeTabs.app`）并启用，再返回应用点击“刷新”。

请先把应用放在最终位置，再授权。替换或移动 ad-hoc 签名的应用后，可能需要移除旧权限条目并添加当前应用。以工具实际诊断的权限状态为准，不能只看系统开关。

## 日常操作

| 操作 | 方法 |
| --- | --- |
| 切换文档 | 点击标签标题 |
| 调整顺序 | 左右拖动标签标题；顺序仅在运行期保留 |
| 查看更多标签 | 在标签栏内部横向滚动 |
| 关闭文档 | 点击已启用的 ×，再处理 Office 原生保存提示 |
| 打开设置 | “MacOfficeTabs → 设置…”，或工具前台时按 `Command + ,` |
| 切换界面语言 | 在设置的“语言 / Language”（英文界面显示为“Language / 语言”）中选择“简体中文”或“English”；立即生效，重启后保留 |
| 快捷键切换 | 开启“启用 ⌃⌥⌘←/→ 切换当前应用标签”，再点击标签建立真实焦点关联 |
| 诊断问题 | 从应用菜单打开“显示窗口诊断” |
| 退出工具 | “MacOfficeTabs → 退出 MacOfficeTabs”，或工具前台时按 `Command + Q` |

标签只有与真实窗口可靠关联后才启用 ×。多文档时可先切到另一个标签再返回，帮助建立关联。身份或焦点无法确认时，请使用 Office 原生关闭命令。

保存提示、权限异常或窗口状态不安全 / 不明确时，浮条和快捷键暂停。工具不会替你选择保存或放弃修改。退出 MacOfficeTabs 后 Office 继续运行。关闭工具最后一个窗口也会退出应用；需要保持运行时，可最小化诊断窗口。

快捷键要求至少两个标签、已核验的焦点，以及对应 Office 应用处于前台。注册失败时会释放两个组合；解决冲突后，关闭再开启快捷键设置以重试。部分非独占共享快捷键不能保证被检测。

## 隐私与权限

日常功能通过 macOS 辅助功能接口读取窗口 / 菜单元数据、核验焦点，并请求原生切换或关闭。不读取文档正文，不编辑文档，也不自动保存。当前源码没有遥测或网络上传实现。

复制的诊断与命令行报告可能包含文档标题和其他窗口元数据，分享前请检查并脱敏。源码另有显式调用的 Word 自动化研究探针，未接入日常功能，标签管理无需运行它。

## 已知限制

- 只显示前台 Office 应用的标签，不支持 Word、Excel 和 PowerPoint 跨应用混合分组。
- 标签顺序不跨工具重启持久化；短 ID 是运行期标识，不是永久文件编号。
- PowerPoint 放映窗口不属于文档编辑管理范围；Excel 同名工作簿的原有限制仍然适用。
- 登录启动的注册与注销已在本机验证，实际注销账户后重新登录自动启动尚未验证。
- 多屏、其他架构 / 版本、端到端窗口跟随延迟尚未验证，完整产品验收仍未完成。
- 0.2.9 DMG 仅支持 Apple Silicon，未使用 Developer ID 签名且未经公证；首次启动可能需要手动允许，尚未在其他 Mac 上验证安装与启动。当前没有自动更新功能。

## 开发与贡献

```text
Sources/OfficeTabsCore/    身份、路由、排序、偏好与安全规则
Sources/MacOfficeTabs/     辅助功能集成、原生 UI、快捷键与诊断
Tests/OfficeTabsCoreTests/ 核心逻辑测试
Resources/Info.plist       应用元数据与版本
scripts/                  构建、本地签名与专项核验工具
docs/user-guide.md        中文详细使用说明
```

使用 `swift test` 运行核心逻辑测试，使用 `bash scripts/build-app.sh` 检查应用构建。核心测试不能替代真实 Office 交互验证；涉及用户操作的修改，请按[贡献与测试说明](CONTRIBUTING.md)核验对应流程。部分核验脚本会真实切换文档或占用快捷键，请使用可丢弃的测试文档。

反馈问题时，请提供应用版本 / 构建号、macOS 版本、架构、Office 版本、窗口模式、复现步骤，以及预期和实际结果。必要时附脱敏诊断。贡献修改时请说明行为变化与相关验证，并保留身份核验和原生保存提示保护。

## 文档

- [详细使用说明](docs/user-guide.md)
- [贡献与测试](CONTRIBUTING.md)
- [安全问题反馈](SECURITY.md)

本机研究记录、诊断日志、截图和测试文档不纳入公开源码，因为其中可能包含私有文档标题及本机路径。

## 许可证

本项目源码公开，采用 [Apache License 2.0，并附加 Commons Clause 1.0 条件](LICENSE)。两者同时适用。

在遵守完整许可的前提下，允许个人使用、企业内部使用、修改和免费再分发。Commons Clause 限制以收费或其他对价向第三方提供、其价值完全或主要来自本软件的产品或服务，包括改名或仅做外观修改后收费销售的版本。它不禁止所有商业集成或付费捆绑，具体以完整许可为准。再分发须保留必要声明（包括 Commons Clause），并按 Apache 2.0 要求标注修改文件。

赞助完全自愿，不改变使用者依许可证享有的权利。除另有书面约定外，贡献按相同的组合许可证提交。

MacOfficeTabs 是独立项目，与 Microsoft 无隶属关系，也未获得其背书。Microsoft Office、Word、Excel 和 PowerPoint 为 Microsoft 的商标。
