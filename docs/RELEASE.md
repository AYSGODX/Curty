# Release process

Development builds are ad-hoc signed and are only for the developer's own Mac. They must not be presented to another person as a trusted release.

A shareable build requires an Apple Developer Program Developer ID Application certificate:

1. Set `SIGNING_IDENTITY` to the exact Developer ID identity and run `Scripts/build-app.sh release`.
2. Run `Scripts/security-check.sh` and the full test suite.
3. Run `Scripts/verify-release.sh .build/Products/Curty.app`.
4. Package the app, submit it with `xcrun notarytool`, staple the ticket, and validate it on a separate standard macOS account.
5. Publish the SHA-256 digest alongside the notarized artifact.

Signing, notarization, Gatekeeper, or security-check failures are release blockers and must never be converted to warnings.
