# Contributing

Thank you for helping improve MicLock.

## Development

Requirements:

- An Apple Silicon or Intel Mac
- macOS 13 or later
- Xcode Command Line Tools

~~~zsh
./scripts/fetch-sparkle.sh
./tests/run.sh
~~~

## Pull requests

- Keep input switching independent from output-device selection.
- Do not add audio capture, telemetry, or network access without discussion.
- Preserve command-line compatibility when changing the menu app.
- Keep CoreAudio work off polling timers and external subprocesses.
- Store and compare devices by UID, never by localized display name alone.
- Run <code>./tests/run.sh</code>; CI treats compiler warnings as errors.
- Explain user-visible behavior and verification steps.

## Bug reports

Prefer **Report an Issue…** inside MicLock: describe the problem in one field. Redacted diagnostics are attached by default and may be previewed or excluded. There is no need to manually fill in your system version or hardware. If opening a GitHub issue instead, include a concise description and reproduction steps; diagnostic output is optional and should be reviewed before sharing.
