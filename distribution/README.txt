MicLock 3.2.0 (build 12)
========================

MicLock keeps the macOS default input on the microphone you configure while
headphones can still handle playback. It does not record audio or change the
microphone hardware or speech recognition algorithm.

Install the website DMG
----------------------
1. Open the DMG and drag MicLock.app to Applications.
2. Open MicLock. Configure the built-in microphone and enable Automatic Lock.
3. In your voice-input app, choose System Default as its microphone.

The menu bar remains available when the settings window is closed. It provides
microphone configuration, pause/resume, feedback, version history, update checks
and uninstall. New installations start with Automatic Lock OFF.

Feedback needs one problem description. You can preview or exclude its redacted
system diagnostics. Failed reports remain local drafts for a manual retry.
Anonymous usage statistics are OFF by default and require explicit opt-in.

Source tools
------------
The install.command and uninstall.command files in this source directory are
advanced source-installation helpers; they are not shipped inside the normal
DMG. Fetch the verified official Sparkle framework before building from source.
See README.md for build commands and CLI installation details.

Compatibility and release verification
--------------------------------------
macOS 13+ is the build target. The app includes arm64 and x86_64; real Intel,
headset, clean-install, upgrade/restart and uninstall acceptance remain separate
release checks. Current builds use ad-hoc signing and are not Apple-notarized.

Source: https://github.com/liuzhengyi/miclock-macos/tree/codex/native-3.2.0
