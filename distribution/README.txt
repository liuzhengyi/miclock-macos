MicLock 3.2.2 (build 14)
========================

MicLock keeps the macOS default input on the microphone you configure while
headphones can still handle playback. It does not record audio or change the
microphone hardware or speech recognition algorithm.

Install the website DMG
----------------------
1. Open the DMG and drag MicLock.app to Applications.
2. Open MicLock. Configure the built-in microphone and enable Automatic Lock.
3. Enable or install a voice input method. If it has a microphone setting,
   choose System Default and try a sentence in a text field. The menu
   Voice Input Recommendations opens the product guide to choosing one.

The menu bar remains available when the settings window is closed. It provides
microphone configuration, pause/resume, settings, voice input recommendations,
quick start and feedback. Version history, update checks, login startup,
temporary switching, diagnostics and uninstall are under More. New installations start with Automatic Lock OFF.

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

Source: https://github.com/liuzhengyi/miclock-macos/tree/v3.2.2
