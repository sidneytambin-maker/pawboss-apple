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
- External group has this build. Beta App Review APPROVED; external build IN_BETA_TESTING.
- Beta description, testing instructions and review contact are saved and verified. Mac and Apple Vision availability are disabled on both groups.
- Public link enabled: https://testflight.apple.com/join/WU2jJvtN, limit 100 testers. The public page returned HTTP 200 and identified PawBoss.
- The shareable public link was emailed once to the owner's Gmail on 15 September. The message clearly identifies build 1; this sprint's changes are not yet published.

Native evidence is retained locally in ignored `Artifacts/Run34912120697`. Signing, upload and beta receipts are in ignored `Artifacts/Release-0.1.0-1-verified`. The earlier `Artifacts/Release-0.1.0-1` package failed inspection and was never uploaded; do not distribute it.

The build-1 review follow-up is paused after approval, public-page verification and the successful email. The ignored public-link-email.json receipt records completion to prevent duplicate mail.

## Build 2 Release

- Native run 34975608698 passed at revision ca5793d9353ee9131fe9d15802ad62a010aa38e2: 77 shared tests, 10 iPhone UI tests, six Watch UI tests, both physical Release targets and archive validation. There were no failed or skipped screen tests.
- The tests exercise grid descriptions, item placement/movement, Watch purchase confirmation and cancellation, all six Watch volume screens, individual sound previews, priority saving and large-text accessibility.
- Fifteen local signing/upload safety tests also passed. Native screenshots were inspected, including the wider room grid, Watch controls and audio library.
- Version 0.1.0 (2) was signed locally. Independent inspection verified both CMS signers, distribution profiles/entitlements, unchanged native code and complete resource seals. The Watch app remains at `Watch/PawBossWatch.app`.
- IPA SHA-256: 8af5534ccb00be8a1b83047b4e55a343cadf6b1488cbb649c5a5103670e02f4a.
- Apple upload 02753594-934d-457f-829d-f10cb46f0120 received all 13 parts with verified checksums and completed without errors or warnings. The matching Apple build is VALID.
- Beta App Review is APPROVED. Internal and external states are both IN_BETA_TESTING; both existing groups contain build 2. Account-holder access was verified and automatic tester notifications are enabled.
- The external group's public link remains enabled: https://testflight.apple.com/join/WU2jJvtN. Build 2 is available through that same shareable link, which was already emailed to the owner. No duplicate link email was sent.
- Native evidence: ignored `Artifacts/Run34975608698`. Signed package and upload receipts: ignored `Artifacts/Release-0.1.0-2-verified`.

Earlier failed or cancelled runs were not signed or uploaded. Do not distribute their artifacts. Build 1 remains historical release evidence; build 2 is the current verified external beta. No review follow-up is pending, and the completed heartbeat remains paused.

## Known Beta Boundaries

Cloud backup is not enabled. Saves are local and private to each installation. Generated fictional records, never the owner's existing business data, are used for tests. The game advances explicitly and does not simulate unattended real-time care. Business rules are gameplay assumptions. Content breadth and long-term balancing need testing; individual breed portrait art and a larger environmental sound library remain future polish. Physical VoiceOver and real paired Watch delivery are not yet verified.
