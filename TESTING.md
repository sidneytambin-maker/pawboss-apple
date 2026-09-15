# Testing

## Automated Suites

The shared XCTest suite covers debt-free startup, inspections, enquiry acceptance, stable identities, care, medication, refunds, prices, capacity, staffing, finance, premises layers, migration, save corruption, replay, stale commands, forecasts, maintenance and a full year of progression. Renewal regressions check that an expired licence cannot bypass application or charge the application twice.

iPhone UI tests cover first run, all five tabs, office navigation, non-drag premises controls, large-text accessibility, dark settings, returning to the main menu, actual dog care saved across relaunch and accessible reports. Watch tests cover waiting for a real business, Menu sections, enquiry navigation and populated dog-care actions.

Thirteen offline Python tests protect release boundaries, upload chunk coverage, destinations, checksums, distribution entitlements, Windows signing paths and app-scoped account-holder invitations. All passed on 15 September 2026. Run with `python3 -m unittest discover -s Scripts -p test_release.py -v`.

`Scripts/validate_source.py` checks Swift syntax trees, device families, catalog, colour/image assets and distinct non-silent audio. It requires tree-sitter, tree-sitter-swift, PyYAML and Pillow. It does not type-check Swift or prove accessibility.

## Current Evidence

- Run 34901352701: all 42 then-current shared tests passed; a Canvas type error stopped native screen compilation. Corrected.
- Run 34902406410: shared tests passed; five of six iPhone UI tests passed. The large-text contrast audit failed and exposed an icon/text overlap. Corrected; not waived.
- Run 34909579142: all 44 shared, eight iPhone UI and four Watch UI tests passed. The physical Watch Release archive then exposed its 32-bit `Int` currency limit. Currency now uses `Int64`, with a 45th core test covering large balances and saved-data round trips.
- Run 34911421764 caught one remaining attendance-to-currency conversion, now corrected. Physical-device compilation runs before simulator suites so architecture errors fail early.
- Run 34912120697: all 45 shared tests, eight iPhone UI tests and four Watch UI tests passed with zero failures or skipped tests. Physical iPhone/Watch Release compilation, archive and content inspection passed. This is the source of TestFlight build 1.

CI retains each stage's logs and xcresult summaries/screenshots. It runs both screen suites to collect failures, but creates a Release archive only when every test stage succeeds. Local signing also rejects unfinished or failed runs, mismatched sources, missing/skipped tests, wrong identifiers or a missing Watch app.

## Physical Acceptance

Install via TestFlight on a paired iPhone and Apple Watch. Start a new business, finish opening readiness, accept an enquiry and run a complete care day. Exercise Watch check-in, medication and customer responses with the phone active, asleep and temporarily disconnected. Verify exactly one business change on reconnection, persistence after restart, no duplicate payments, correct focus/announcements and all audio sliders. Test notification record destinations and a stale action after advancing the phone's day.

These physical checks have not yet been completed for PawBoss. Simulator tests do not substitute for them.
