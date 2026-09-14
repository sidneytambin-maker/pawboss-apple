# PawBoss

A Dog Day Care Simulation. Native iPhone and Apple Watch development, in its own project and repository. No iPad target.

The Windows game, Design Bible, Galleonaire and Court Story are read-only references. No existing user game saves are bundled here.

## The Game

Start with savings, two empty rooms and an outdoor area. Configure the site, buy equipment, arrange registration, insurance and a council inspection, then earn your first customers through enquiries. Run care days, build relationships, employ and develop staff, adjust prices, manage cash and expand carefully. Decisions affect welfare, loyalty, reputation and operating costs. Time advances only when you complete a game day.

iPhone has Today, Office, Dogs, Premises and More tabs. Watch has a Menu with eight management sections, shared dog and customer records, quick actions and a persistent offline queue. The iPhone remains the authoritative business.

Native screens include semantic premises coordinates, VoiceOver custom actions, reports and Swift Charts, optional reminders, six audio categories, eleven original sound assets, haptics, generated PawBoss artwork, dark appearance and Dynamic Type.

This is an early beta under native validation, not a claim of commercial completion. See [TESTING.md](TESTING.md) and [TESTFLIGHT.md](TESTFLIGHT.md) for the evidence boundary. iCloud backup is not enabled. Long-term balance, content breadth and physical VoiceOver/Watch testing still need player feedback.

## Build

Use stable Xcode 26 or newer and XcodeGen on macOS. Generate the project from `Apple/project.yml`, or run `python3 Scripts/ci.py --stage all` for shared tests, iPhone UI tests, Watch UI tests and an inspected unsigned Release archive. The project excludes iPad and Mac compatibility.

The public repository uses standard GitHub Mac runners. No signing key, upload key, profile, personal save or private reference document belongs in the repository. Signing and direct Apple upload take place locally after native validation. Artifacts are short-lived and are downloaded locally for release evidence.

Run the offline release-safety tests with `python3 -m unittest discover -s Scripts -p test_release.py -v`. Python signing tools require `cryptography` and OpenSSL; they accept protected credential file paths, never literal passwords.

Run shared tests with `cd Apple` and `swift test` on a Swift 5.9+ host. Native Apple builds use Xcode on a Mac runner.
