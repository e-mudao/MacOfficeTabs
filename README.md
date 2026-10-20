<p align="center"><img src="./Resources/IconDesign/MacOfficeTabs-icon-v1.png" width="104" alt="MacOfficeTabs app icon: one document with blue, green, and orange tabs"></p>

# MacOfficeTabs

**Floating document tabs for Word, Excel, and PowerPoint on macOS.** Switch and reorder documents while Office keeps its native windows and handles saving.

[Download](https://github.com/e-mudao/MacOfficeTabs/releases) · [简体中文](README.zh-CN.md) · [How it works](#what-the-tab-bar-does) · [Limitations](#known-limitations)

> [!IMPORTANT]
> **0.2.9 (build 18) is the first GitHub Release.** Its Apple Silicon DMG is ad-hoc signed and **not Apple notarized**. macOS may require manual approval on first launch. Compatibility testing is still in progress.

<p align="center"><img src="./assets/readme/tab-bar-concept.svg" width="100%" alt="Concept diagram: a floating bar centered at the top of a Word window, with three document tabs and close controls"></p>

*Illustration of the tab bar, not an application screenshot. The bar appears inside the foreground Office document window; it does not merge documents into one window.*

## Download and install

Download `MacOfficeTabs-0.2.9-build18-arm64.dmg` from [GitHub Releases](https://github.com/e-mudao/MacOfficeTabs/releases). It is built for **Apple Silicon (arm64)** with a macOS 13 minimum deployment target; only the recorded environment below has been tested. Install Word, Excel, or PowerPoint separately. No development tools are needed to install the DMG.

1. Open the DMG and drag **MacOfficeTabs.app** onto **Applications**. Launch the copy in Applications.
2. If macOS blocks it, try opening the app once, then go to **System Settings → Privacy & Security → Open Anyway** and confirm. This manual step is needed because the DMG is not notarized; it does not mean Apple has verified the app.
3. In the initial **Office 窗口诊断** (Office Window Diagnostics) window, click **打开辅助功能设置** (Open Accessibility Settings). Allow the installed MacOfficeTabs app to control the computer, then return and click **刷新** (Refresh).
4. Bring an Office document editing window to the front and click a tab title to switch documents.

The interface starts in Simplified Chinese. For English, choose **MacOfficeTabs → 设置… → 语言 / Language → English**; the change applies immediately and persists after restart. There is no automatic updater, so install later versions from Releases yourself.

See [Permission details](#permission-details) if the app cannot find your Office windows. Developers can [build from source](#build-from-source).

## What the tab bar does

- **Current Office app only.** Word, Excel, and PowerPoint have separate tab lists and settings. The bar hides when another app is in front.
- **Inside the document window.** The bar sits near the top in normal, maximized, and native fullscreen modes. It may cover a small part of the Office toolbar.
- **Switch and reorder.** Click a title to switch, drag to reorder, or scroll horizontally for more tabs. Short runtime IDs distinguish identical titles.
- **Office controls closing.** An enabled × requests Office's native close command. Office presents any save or discard decision; MacOfficeTabs never answers it for you.

Shortcuts and launch at login are optional and off by default. All three apps' tab bars are on by default. Settings also provides the Chinese/English interface choice; diagnostics shows permissions, window candidates, focus verification, and panel visibility.

## Requirements and compatibility

| Item | Requirement / recorded environment |
| --- | --- |
| Deployment target | macOS 13.0 or later |
| Release download | Apple Silicon (arm64) DMG; Intel build is not available |
| Office | Microsoft Word, Excel, or PowerPoint installed separately |
| Permission | Accessibility control permission for MacOfficeTabs |
| Build tools (source only) | Swift tools 5.9 or later; Xcode or Command Line Tools with a compatible macOS SDK |
| Recorded test environment | Apple Silicon (arm64), macOS 27.0.1 (26A434), Office 16.113.4 |

The minimum deployment target is not a compatibility guarantee. Intel, other macOS and Office versions, multiple physical displays, and Stage Manager have not been verified. The public compatibility summary and remaining gaps are listed under [Known limitations](#known-limitations).

## Build from source

From the repository root:

```sh
bash scripts/build-app.sh
open build/MacOfficeTabs.app
```

The build script compiles the release executable, assembles `build/MacOfficeTabs.app`, signs it, and verifies the signature. Without local signing configuration, it uses ad-hoc signing. It builds for the current toolchain's architecture, rather than producing a universal app.

For a persistent local development signing identity, run this **before building and granting permission**:

```sh
bash scripts/setup-dev-signing.sh
bash scripts/build-app.sh
open build/MacOfficeTabs.app
```

The setup script creates a project-specific certificate and keychain in `.dev-signing/`. It does not change system root trust or the login/default keychain. This directory contains private keys and credentials and is ignored by Git; never upload or share it. Local development signing is not Developer ID distribution signing or notarization.

## Permission details

The initial window is **Office 窗口诊断** (Office Window Diagnostics). Its **打开辅助功能设置** button opens macOS app control permissions. Older macOS versions usually place this under **Privacy & Security → Accessibility**; the tested macOS 27 labels it **设备控制和数据访问**. If MacOfficeTabs is missing, use **+** to add the app from **Applications** (or `build/MacOfficeTabs.app` for a source build), enable it, then return to the app and click **刷新** (Refresh).

Grant permission after putting the app in its final location. Replacing or moving an ad-hoc signed build may require removing the old permission entry and adding the current app again. Check the app's actual diagnostic status rather than relying only on the system toggle.

## Everyday use

| Action | How |
| --- | --- |
| Switch documents | Click a tab title |
| Reorder tabs | Drag the title left or right; order is kept only for the current runtime |
| Find more tabs | Scroll horizontally inside the bar |
| Close a document | Click an enabled ×, then respond to Office's own save prompt |
| Open settings | **MacOfficeTabs → 设置…** (or **Settings…** in English), or `Command + ,` while the tool is foreground |
| Change interface language | In Settings, choose **简体中文** or **English** from **语言 / Language** (shown as **Language / 语言** in English); changes apply immediately and persist |
| Navigate with shortcuts | Enable **“启用 ⌃⌥⌘←/→ 切换当前应用标签”** (or **“Use ⌃⌥⌘←/→ to switch tabs in the current app”**), then click tabs to establish verified focus |
| Inspect a problem | Open **“显示窗口诊断”** (or **Show Window Diagnostics**) from the app menu |
| Quit the tool | **MacOfficeTabs → 退出 MacOfficeTabs** (or **Quit MacOfficeTabs**), or `Command + Q` while the tool is foreground |

The × stays disabled until a tab is reliably associated with a real window. With multiple documents, switching to another tab and back can establish that association. When identity or focus is uncertain, use Office's own close command.

The bar and shortcuts pause during save dialogs, permission failures, or unsafe/unknown window states. The app never chooses a save or discard action for you. Quitting MacOfficeTabs leaves Office running. Closing the last tool window also exits the app; minimize the diagnostics window to keep it running.

Shortcuts require at least two tabs, verified focus, and the corresponding Office app in front. If registration fails, both shortcuts are released; after resolving the conflict, turn the setting off and on to retry. Some non-exclusive shared shortcut registrations cannot be reliably detected.

## Privacy and permissions

Normal operation uses macOS Accessibility APIs to read window/menu metadata, verify focus, and request native switching or closure. It does not read document body content, edit documents, or automatically save them. The current source has no telemetry or network upload implementation.

Copied diagnostics and command-line reports can contain document titles and other window metadata. Review and redact them before sharing. A separate, explicitly invoked Word automation research probe exists in the source; it is not part of normal operation and is not required for tab management.

## Known limitations

- Only the foreground Office app's tabs are shown; there are no mixed groups spanning Word, Excel, and PowerPoint.
- Tab order is not persisted across tool restarts; short IDs are runtime identifiers, not permanent file IDs.
- PowerPoint slideshow windows are outside the editing scope. Excel's own restrictions on opening same-named workbooks still apply.
- Launch-at-login registration and removal have been tested locally; automatic launch after an actual logout/login has not.
- Multiple displays, other architectures/versions, and end-to-end window-following latency remain unverified. Full product acceptance is incomplete.
- The 0.2.9 DMG is Apple Silicon only and is not Developer ID signed or notarized. First launch may need manual approval; installation and launch on another Mac have not yet been verified. There is no automatic updater.

## Development and contributing

```text
Sources/OfficeTabsCore/    Identity, routing, ordering, preferences, and safety rules
Sources/MacOfficeTabs/     Accessibility integration, native UI, shortcuts, and diagnostics
Tests/OfficeTabsCoreTests/ Core logic tests
Resources/Info.plist       App metadata and version
scripts/                  Build, local signing, and targeted verification tools
docs/user-guide.md        Detailed Chinese user guide
```

Run `swift test` for core logic tests and `bash scripts/build-app.sh` to check the app build. Core tests do not replace real Office interaction testing. Follow [CONTRIBUTING.md](CONTRIBUTING.md) for manual checks of affected user flows. Some verification scripts actually switch documents or reserve shortcuts; use disposable documents for those experiments.

Bug reports should include the app version/build, macOS version, architecture, Office version, window mode, reproduction steps, and expected/actual behavior. Attach redacted diagnostics where useful. For contributions, explain the behavior change and relevant verification, preserving identity checks and native save dialogs.

## Documentation

- [Detailed user guide (Chinese)](docs/user-guide.md)
- [Contributing and testing](CONTRIBUTING.md)
- [Security reporting](SECURITY.md)

Local research notes, diagnostic logs, screenshots, and test documents are excluded from the public source tree because they can contain private document titles and machine paths.

## License

This project is source-available under the [Apache License 2.0, subject to Commons Clause 1.0](LICENSE). Both apply together.

Personal use, internal business use, modification, and free redistribution are permitted subject to the full license terms. Commons Clause restricts providing a product or service for a fee or other consideration when its value derives entirely or substantially from this software, including a renamed or cosmetically modified paid version. It does not prohibit every commercial integration or paid bundle; the full license controls. Redistribution must retain the required notices, including Commons Clause, and identify modified files as required by Apache 2.0.

Sponsorship is voluntary and does not change your rights under the license. Contributions are accepted under the same combined license unless separately agreed in writing.

MacOfficeTabs is an independent project and is not affiliated with or endorsed by Microsoft. Microsoft Office, Word, Excel, and PowerPoint are trademarks of Microsoft.
