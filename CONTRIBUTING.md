# Contributing / 贡献说明

MacOfficeTabs is source-available under [Apache-2.0 with Commons Clause 1.0](LICENSE). Contributions are submitted under that combined license unless agreed otherwise in writing. Please read the license before contributing.

MacOfficeTabs 的源码采用 [Apache-2.0 加 Commons Clause 1.0](LICENSE) 组合许可。除另有书面约定，贡献也按该组合许可提交。参与前请阅读完整许可证。

## Build and check / 构建与检查

On macOS 13 or later with Xcode or Command Line Tools:

```sh
swift test
bash scripts/build-app.sh
```

The build script uses an ad-hoc signature unless you explicitly configure the local development identity described in the README. No third-party Swift package is required. The CI workflow checks unit tests and an ad-hoc app build; it does not verify real Office interaction.

构建脚本默认使用 ad-hoc 签名；只有按 README 显式配置后才会使用本地开发身份。项目没有第三方 Swift 包依赖。CI 检查单元测试和应用构建，不能代替真实 Office 交互验收。

## Manual checks / 人工检查

For a change to window discovery, switching, closing, panel placement, shortcuts, or login launch, test the affected path with disposable Word, Excel, or PowerPoint documents on a real Mac. Verify the target document receives keyboard input, and that Office's save prompt remains in control when closing an unsaved document. Record the macOS version, Office version, app version, and what you actually observed. A passing unit test or successful Accessibility request alone is not evidence that the right Office window received focus.

涉及窗口发现、切换、关闭、浮条位置、快捷键或登录启动时，请在真实 Mac 上用可丢弃的 Office 文档检查受影响路径。核对键盘输入进入目标文档；关闭未保存文档时，核对 Office 原生保存提示仍由用户处理。记录 macOS、Office、应用版本及实际观察结果。单元测试或辅助功能调用成功本身不足以证明焦点正确。

The optional fixture scripts write local files under `docs/evidence/`, which Git ignores. `scripts/verify-fixtures.sh` actively switches Word documents; `scripts/test-hotkey-conflict.sh` reserves shortcuts. Run them only in a disposable test session. `scripts/create-office-fixtures.py` additionally needs `openpyxl` and `python-pptx`; these are not needed to build the app.

可选样本脚本会把本地文件写入已被 Git 忽略的 `docs/evidence/`。`scripts/verify-fixtures.sh` 会实际切换 Word 文档，`scripts/test-hotkey-conflict.sh` 会占用快捷键，请只在可丢弃的测试会话中运行。`scripts/create-office-fixtures.py` 另需 `openpyxl` 和 `python-pptx`，构建应用不需要它们。

## Reports / 反馈

In a bug report, include reproduction steps, expected and actual behavior, app build, macOS version and architecture, Office version, and window mode. Diagnostics may include private document titles and machine paths. Redact them before attaching logs or screenshots. For sensitive security issues, follow [SECURITY.md](SECURITY.md).

反馈问题时请提供复现步骤、预期及实际结果、应用构建号、macOS 版本与架构、Office 版本和窗口模式。诊断日志可能含私有文档标题及本机路径，上传日志或截图前请脱敏。敏感安全问题请按 [SECURITY.md](SECURITY.md) 反馈。
