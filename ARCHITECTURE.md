# Architecture

## Shared Rules

`Apple/Sources/PawBossCore` owns the Codable business, catalog, premises layers, simulation, finance and persistence models. Currency uses integer pence. Business, dog, customer, staff, booking, message and command identities survive saving and companion transfers.

`GameEngine.apply` validates the business/day, applies a command to a candidate state, checks invariants and commits it atomically. Successful and rejected commands retain receipts. Replaying a receipt cannot repeat its financial effect. Ledger validation reconciles every movement with the current bank balance; borrowing is not operating revenue.

Time advances explicitly. Daily simulation combines actual bookings, welfare, staffing, expenses, maintenance, communication and events. A seeded generator makes simulation scenarios reproducible. Catalog prices are UK-inspired gameplay assumptions, not advice.

## Presentation

Both native targets compile the same SwiftUI screens with platform-appropriate roots. `BusinessStore` saves before publishing a successful phone change. `Destination` identifies specific records and forms for navigation, notification responses and custom actions. Images and audio are bundled independently in each app.

The Release build excludes UI-test fixtures and reset arguments. Test fixtures use a separate save directory and preferences suite, with real companion transport disabled.

## Persistence and Sync

The file repository preserves a current and previous atomic save. Envelope version 2 verifies a SHA-256 payload digest; version 1 migrates without replacing record IDs. This is accidental-corruption detection, not encryption or an authenticity guarantee. Unsupported versions fail without overwriting saved data. Restoring a previous timeline assigns a new business ID so old Watch commands cannot mutate it.

Watch receives validated snapshots and queues commands durably. Small snapshots use application context; larger snapshots use file transfer. Commands use queued delivery and a live path when reachable. Receipts remove only matching queued commands. A new business or changed day rejects stale commands with a reason. Unreachable does not mean unpaired or uninstalled.

An unreadable Watch queue is preserved and new actions pause rather than overwrite it. A corrupt business cache can be replaced independently from iPhone. Automatic recovery of a corrupt queue itself is not implemented.

The repository and snapshot boundaries allow future CloudKit work. There is no CloudKit implementation or cloud-backup entitlement in this release.
