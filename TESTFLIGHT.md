# TestFlight

## Identity

- App: PawBoss. Personal project by Sidney Tambin.
- Version: 0.1.0. Initial build: 1.
- App Store Connect record: 6812075156.
- iPhone: com.sidneytambin.pawboss.
- Watch: com.sidneytambin.pawboss.watchkitapp, embedded at `PawBoss.app/Watch/PawBossWatch.app`.
- No iPad, Mac compatibility or standalone Watch business authority.

## Verified Setup

The App Store Connect record and exact phone/Watch identifiers exist. Separate active App Store distribution profiles were issued for both targets and matched to the protected local distribution certificate. Private keys, passwords and profiles remain outside source control.

The private GitHub build was stopped by the account's billing restriction. With the owner's explicit approval, this PawBoss repository became public and standard Mac jobs started successfully. No spending increase or paid runner was enabled. See [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions). Build downloads are retained briefly and preserved locally for release verification.

## Release Gates

1. All shared and native screen tests pass at the exact source revision.
2. The Release archive contains both PawBoss targets, icons, privacy manifests, catalog and audio.
3. Local signing applies the proper App Store profile and distribution entitlements to Watch first, then phone. Watch remains in `Watch`, never `PlugIns`.
4. Independent inspection checks native code/data, resource seals, CMS signer, entitlements and package integrity. This is not a claim of Apple's platform trust evaluation.
5. Direct upload verifies every received file part and requires Apple's upload state COMPLETE plus the matching build's processing state VALID.
6. Configure internal/external groups, testing notes and review contact; submit Beta App Review.
7. Enable a public link only after APPROVED and IN_BETA_TESTING are confirmed.

The scripts are `local_sign.py`, `inspect_local_ipa.py`, `direct_upload.py` and `testflight.py`. Keep their ignored JSON receipts with the downloaded native evidence. They do not accept a failed native run as a release candidate.

## Current Publication State

Verified on 15 September 2026:

- Native run 34912120697 passed: 45 core tests, eight iPhone UI tests, four Watch UI tests and physical iPhone/Watch Release compilation and archive.
- Tested native revision: cd09a2b2e8884e7228175e1b7a3ab9409aab810d.
- Local package inspection passed for both apps: CMS signatures, distribution entitlements/profiles, native code/data and resource seals.
- IPA SHA-256: a229ea6b06eb1646e1bb068ec27cd3ce867e1467c34dfcf6dea635e38c34543f.
- Apple upload COMPLETE with no reported errors or warnings. Build processing VALID.
- Apple build ID: ebbaa695-2e95-4d2a-af4a-3ac813120351, version 0.1.0 (1).
- Internal TestFlight: IN_BETA_TESTING. Account-holder tester membership verified.
- External group has this build. Beta App Review submitted: WAITING_FOR_REVIEW; external build WAITING_FOR_BETA_REVIEW.
- Beta description, testing instructions and review contact are saved and verified. Mac and Apple Vision availability are disabled on both groups.
- Public link is disabled pending approval. No public-link email has been sent.

Native evidence is retained locally in ignored `Artifacts/Run34912120697`. Signing, upload and beta receipts are in ignored `Artifacts/Release-0.1.0-1-verified`. The earlier `Artifacts/Release-0.1.0-1` package failed inspection and was never uploaded; do not distribute it.

An hourly thread follow-up is configured to verify Apple's decision, enable the external public link after approval, verify its PawBoss page, and email it once through the owner's Gmail. It remains quiet on unchanged waiting states. Apple review is an external dependency, not a completed release.

## Known Beta Boundaries

Cloud backup is not enabled. Saves are local and private to each installation. Generated fictional records, never the owner's existing business data, are used for tests. The game advances explicitly and does not simulate unattended real-time care. Business rules are gameplay assumptions. Content breadth and long-term balancing need testing; individual breed portrait art and a larger environmental sound library remain future polish. Physical VoiceOver and real paired Watch delivery are not yet verified.
