# Accessibility

Accessibility is always present; there is no separate accessibility mode.

## Implemented

- Native headings, navigation, buttons, text fields, toggles and pickers; no drag-only premises operations.
- Combined dog, staff, customer and navigation summaries, with relevant custom actions for care, contact, editing and direct forms.
- Explicit row/column selection and the top object on each premises square; floor layers do not hide the useful object name.
- Destructive/purchase confirmations and cancellation paths. State changes are announced only after saving or with an explicit queued status on Watch.
- Notification destinations identify the business, record and relevant task, rather than opening a generic list.
- Swift Charts have spoken labels, values and summaries, with the same report values available as text.
- Dynamic Type, light/dark appearance, system and optional reduced motion, independent audio volumes and optional haptics.
- Decorative artwork and redundant symbols are hidden from VoiceOver. Large accessibility sizes omit decorative row icons to keep text clear.

## Evidence and Remaining Checks

The native audits identified dashboard contrast, large-text overlap and duplicate navigation semantics. These were corrected. Run 34912120697 passed the eight iPhone and four Watch UI tests, including largest-text dashboard audits, dark settings and report contrast/semantics. Screenshots were inspected for reports and Watch care. Compilation and automated accessibility checks do not prove independent VoiceOver completion.

Physical iPhone and Watch checks must cover initial focus, rotor actions, cancel/delete focus restoration, premises coordinates, charts, notification cold launch, audio competition, Digital Crown navigation, queued actions and reconnection. Test all major forms at the largest text size, in both appearances and with Reduce Motion. Do not mark these passed until actually exercised.
