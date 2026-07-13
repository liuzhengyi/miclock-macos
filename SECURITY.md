# Security

## Reporting a vulnerability

Please avoid publishing exploit details in a public issue. Open a GitHub
security advisory for this repository or contact the owner through GitHub.

## Scope

MicLock does not capture audio or communicate over the network. It executes a
bundled or Homebrew-provided <code>SwitchAudioSource</code> binary, writes
per-user configuration, and manages two per-user LaunchAgents.

Release DMGs are currently ad-hoc signed and not Apple-notarized. Users should
verify the published SHA-256 checksum and review the source before installation.
