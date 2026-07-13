# Contributing

Thank you for helping improve MicLock.

## Development

Requirements:

- Apple Silicon Mac
- macOS Tahoe 26 or later
- Xcode Command Line Tools
- Homebrew and <code>switchaudio-osx</code>

~~~zsh
brew install switchaudio-osx
./build-menu-app.sh
./build-dmg.sh
~~~

## Pull requests

- Keep input switching independent from output-device selection.
- Do not add audio capture, telemetry, or network access without discussion.
- Preserve command-line compatibility when changing the menu app.
- Run <code>zsh -n</code> on scripts and <code>plutil -lint</code> on plists.
- Explain user-visible behavior and verification steps.

## Bug reports

Include the macOS version, Mac model, input-device list, relevant MicLock logs,
and reproduction steps. Remove personal device names before posting if needed.
