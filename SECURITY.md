# Security

## Reporting a vulnerability

Please avoid publishing exploit details in a public issue. Open a GitHub
security advisory for this repository or contact the owner through GitHub.

## Scope

MicLock does not capture audio. Version 3 uses Apple CoreAudio directly. Version 3.2 adds the checksum-pinned official Sparkle update framework. Update checks and feedback connect only when requested; optional anonymous usage statistics are off by default and require explicit consent. Configuration is stored atomically with user-only
permissions, and diagnostics redact device identifiers by default.

Release DMGs are currently ad-hoc signed and not Apple-notarized. Users should
verify the published SHA-256 checksum and review the source before installation.
The current CI workflow verifies native source changes; it does not produce a
Developer ID signed or notarized release. Those release steps and real upgrade
acceptance remain pending until an Apple Developer membership and signing
identity are available.


## Update trust and private signing material

Sparkle 2.10.0 verifies both the feed and update archive using Ed25519. The application's `SUPublicEDKey` is public; the private key must never enter Git, source archives, website bundles, diagnostics or logs. `tests/verify-update-signatures.py` validates published bytes with only the public key and rejects altered archives, feeds and keys. Explicit confirmation is required before an update installs and restarts the app.

`MLAnalytics` sends only its fixed event schema with a random opt-in installation ID. It contains no hardware ID, username, account, voice, input text or feedback description. Revocation cancels pending requests and clears the local random ID. A successfully received configuration/activity event is committed locally only after an exact matching receipt. These voluntary observations do not count all installations or prove speech recognition improvement.
