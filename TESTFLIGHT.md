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

Native validation is in progress. No PawBoss IPA upload, internal invitation, external review approval or public TestFlight link has yet been verified. This section must be updated from Apple's actual responses after release. Metadata is prepared in `Docs/TestFlight-Metadata.json`; preparing it is not publication.

## Known Beta Boundaries

Cloud backup is not enabled. Saves are local and private to each installation. Generated fictional records, never the owner's existing business data, are used for tests. The game advances explicitly and does not simulate unattended real-time care. Business rules are gameplay assumptions. Content breadth and long-term balancing need testing; individual breed portrait art and a larger environmental sound library remain future polish. Physical VoiceOver and real paired Watch delivery are not yet verified.
