# MicLock for macOS
> Source version: 3.2.0, build 12. Developer ID signing, notarization, and broader device acceptance remain pending.

<p align="center">
  <img src="docs/MicLock-icon.png" width="160" alt="MicLock icon">
</p>

MicLock keeps the macOS global default input on a selected microphone while
AirPods or another headset can remain the output device.

[简体中文](README.zh-CN.md)

## Highlights

- Event-driven native CoreAudio implementation; no polling subprocesses.
- Stable device UID storage, independent of display name and system language.
- Separate actions for a one-time switch and a persistent lock target.
- Real health states for healthy, waiting, conflict, paused, and error.
- Built-in, Bluetooth, external, virtual, and other device badges.
- English and Simplified Chinese UI, VoiceOver status, and increased contrast.
- Native CLI, login-item control, in-app redacted feedback, signed Sparkle updates, version history and safe uninstall.
- A native Status and Settings window shows the real input, saved target, health, and automatic-lock control.
- No Homebrew dependency, audio capture, or root daemon. Usage statistics are off by default; users may explicitly enable a small set of anonymous events. Update checks and reports connect only when requested.

## Compatibility

- Deployment target: macOS 13 or later. Broad OS/device acceptance remains pending.
- Universal app for Apple Silicon and Intel Macs.

## Install from the product website

1. Download the DMG from the [product website](https://ecnkfnba0c1r.feishuapp.com/app/app_17ftjhzb3vs#download), checking its displayed version and release status.
2. Open the DMG and drag `MicLock.app` to `Applications`.
3. Open `MicLock` from Applications or Spotlight. Follow the initial guide to choose a target microphone and enable Automatic Lock.

The local 3.2.0 build is currently ad-hoc signed. Apple notarization and formal Gatekeeper acceptance remain pending. The website must switch to a formal package only after Developer ID signing, notarization, and installation acceptance succeed; a successful build alone does not establish installation readiness.

The [3.2.0 source branch](https://github.com/liuzhengyi/miclock-macos/tree/codex/native-3.2.0) matches this native version. The main branch may remain on an earlier version while the pull request is reviewed.

## Install from source

For this native version, first fetch the checksum-pinned official framework with `./scripts/fetch-sparkle.sh`, then build in the complete source directory:

~~~zsh
./install.sh
~~~

This advanced installer also places CLI commands in `~/.local/bin`. Users who drag the app to Applications do not need it. No Homebrew package is required by this native source. A target can be selected explicitly after installation with either its exact name or stable UID:

~~~zsh
mic-list
miclock use "BuiltInMicrophoneDevice"
~~~

## Command line

~~~text
mic-status                       Show current input and health
mic-list                         List devices, transport, and stable UID
mic-pick                         Select a persistent lock target
mic-set "NAME_OR_UID"            Set and switch to a persistent target
mic-fix                          Restore the configured target once
mic-off                          Pause automatic locking
mic-start                        Enable locking and start the app
mic-quit                         Disable locking and quit the app
miclock switch "NAME_OR_UID"     Switch once and pause automatic locking
miclock diagnostics              Print redacted diagnostics
miclock show-menu                Open the menu bar menu, starting MicLock if needed
miclock show-status              Open Status and Settings, starting MicLock if needed
~~~

Commands are installed in `~/.local/bin`. Add that directory to `PATH` if your
shell does not already include it.

## Menu-bar states

| Badge | Meaning |
| --- | --- |
| `M` | Mac built-in input |
| `B` | Bluetooth input |
| `E` | External hardware input |
| `V` | Virtual or aggregate input |
| `O` | Other transport |
| `!` | Target unavailable, repeated conflict, or error |

Selecting **Switch Input Now** pauses automatic locking so the chosen device is
not immediately reverted. Selecting **Lock Target** changes the persistent UID.

Choose **Status and Settings…** from the menu to inspect the actual input, target, and health, or change the target and Automatic Lock directly. Closing this window leaves MicLock running in the menu bar. Reopening the app shows the status window again.

## How it works

The menu-bar app listens for CoreAudio default-input and device-list property
changes. It acts only after an event instead of launching a command every two
seconds. Repeated external routing conflicts trigger a temporary backoff rather
than an infinite device-selection fight.

Configuration and health are atomically stored with user-only permissions in:

~~~text
~/Library/Application Support/MicLock/
~~~

MicLock controls only the macOS global default. Apps such as Zoom or Teams can
override it when configured to use a specific microphone; choose **System
Default** inside those apps.

## Build and verify

~~~zsh
./scripts/fetch-sparkle.sh
./tests/run.sh
python3 -m venv .layout-venv
.layout-venv/bin/pip install ds_store==1.3.2 mac_alias==2.2.3
MICLOCK_LAYOUT_PYTHON="$PWD/.layout-venv/bin/python" MICLOCK_LAYOUT_MODULES="" ./build-dmg.sh
~~~

Builds are universal and warning-clean, with ad-hoc signing by default. The included Sparkle 2.10.0 framework comes from its official release and is verified against a pinned SHA-256 before extraction. The DMG layout dependencies above are build tools and are not included in the app. `SIGNING_IDENTITY` can supply a Developer ID identity; Apple notarization remains a separate release step.

The native regression workflow runs on each push and pull request. It checks isolated device, state, correction, lifecycle, feedback, and analytics models; compiles both architectures; and verifies the app signature. It does not install or uninstall an app, change the real microphone, send feedback, or establish acceptance on physical Intel Macs and headsets. Website and support-service tests are maintained separately from this native repository.

## Uninstall

For an installation in `/Applications` or your personal `~/Applications`, choose **Uninstall MicLock…** in the menu or settings window. Confirm to stop locking, unregister this app’s own login item, and move the app to the Trash. Saved settings and feedback drafts are retained unless you explicitly select their removal. Only known MicLock files are removed; unknown files are preserved. Developer builds and apps running from a DMG are refused by this uninstall action.

If you installed CLI commands from source, run the following in the matching source directory:

~~~zsh
./uninstall.sh
~~~

The uninstaller refuses root execution and symlink traversal, and deletes CLI
aliases only when their ownership can be verified.

## Privacy and security

MicLock reads CoreAudio device metadata and changes the default input. It does
not record audio. Updates and reports connect only when chosen; optional anonymous statistics are off by default and may be disabled at any time. Diagnostics redact device names and UIDs by default. Users can inspect or exclude the diagnostic attachment before submitting a report. See [SECURITY.md](SECURITY.md).

**Report an Issue…** opens an in-app description field. A redacted system snapshot is attached by default and can be previewed or excluded before sending. Failed reports remain drafts for a user-initiated retry.

## License

MicLock is released under the [MIT License](LICENSE).

New installations start with automatic locking off. Enable it after checking the target and selecting System Default in the voice app. The source installer preserves existing lock and login preferences on upgrade. Run `build/MicLock.app/Contents/MacOS/MicLock --guide` to preview the real guide without initializing state or changing the microphone.
