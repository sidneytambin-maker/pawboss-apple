# PawBoss 0.1.0 (2): audio and business variety

## Changes

- 23 licensed audio assets replace 11 procedural sounds. Recorded office, garden, rain, dog and arrival sounds; six complete music tracks, over 13 minutes in total.
- All six sliders default to 50%, with no VoiceOver-specific multiplier. Legacy untouched defaults move to 50%; mute and other personal values remain. Reset is available.
- Music uses a shuffled bag and preserves position across navigation and foreground interruptions. Office, care and outdoor screens select their soundscape; weather changes outdoor ambience. Previews pause backgrounds and stop after 15 seconds or when leaving the library.
- 36 fictional dog profiles, at least 30 breed descriptions, six communication preferences and six returning-booking patterns.
- 48 equipment choices. Suitable, maintained equipment complements individual rest, enrichment, hygiene and team routines. Benefits are capped and do not replace essential care. Purchases show remaining cash and recurring commitments.
- 14 conditional business events, with lessons about margins, retention, seasonal preparation, staffing and reserves. Existing IDs and save schema remain intact.
- Directly selectable premises grids replace row/column pickers. Every square names its coordinate and all contents, including boundaries, underlying flooring and multi-square footprints. Both starter rooms have direct links and their own grids. Actions support adding, moving and removing items without dragging; purchases show costs and fence-replacement credit before confirmation.
- Item language follows the actual activity: place portable equipment, install fitted equipment, fit flooring, lay paths, plant gardens and build boundaries/buildings. Results and history identify the affected square.
- A six-stage opening guide follows actual registration, premises, essentials, insurance and inspection rules. It does not bypass council checks or require debt.
- Three daily-priority pickers swap duplicate choices and keep Save available. Inbox messages have sender, date, subject, preview and status, with filters and a direct priorities link.
- Three providers each for vets, suppliers, trainers, groomers and community support. Thirty-day agreements have distinct upfront fees and trade-offs, no automatic renewal and at most one provider per category. Discounts affect actual care/course ledger entries; support depends on essential care; referrals are capped. Less reliable suppliers can require a retail top-up, recorded as a cost and business lesson. Old saves acquire the new choices without replacing dogs, customers, bookings or competitor prices.

## Price and care model

Prices are gameplay estimates, not supplier quotations or a complete business plan. Basic bowls, beds and enrichment are modest purchases; machinery and expansion carry larger commitments. The established 7,500-pound debt-free opening remains available, with essential-equipment and cash-reserve regression coverage.

Sources checked 15 September 2026:

- [Pets at Home dog bowls](https://www.petsathome.com/product/collections/dog-bowl): examples around 8-12 pounds support the basic 10-pound bowl assumption.
- [Pets at Home cooling range](https://www.petsathomeplc.com/news-and-media/product/the-12-method-to-cool-your-dog-down-by-9-c/): mats span roughly 6-18 pounds; the game uses 18 pounds.
- [Claire's Comfy Canines services](https://www.clairescomfycanines.co.uk/services-and-prices): regular day care around 37 pounds supports the 35-pound starting rate; local prices vary.
- [England day-care licensing guidance](https://www.gov.uk/government/publications/animal-activities-licensing-guidance-for-local-authorities/dog-day-care-licensing-statutory-guidance-for-local-authorities): welfare, staffing, rest, hygiene and appropriate equipment inform the model. Day care and overnight boarding remain separate permissions. The game is not a legal compliance simulator.

Other prices are design estimates for modest or used fixtures. A 450-pound grooming station represents basic equipment, not a premium electric salon table.

## Audio provenance

Audio-Sources.json records author, source page, free download and licence. The bundled manifest adds source and mastered-file hashes, durations and modifications. Most recordings are CC0. The Office by Iwan 'qubodup' Gabovitch is CC BY 3.0, with in-app attribution and licence links. Barks are neutral recorded vocalisations, not a claim that barking indicates happiness. No private customer recordings or saved business data are bundled.

## Verification boundary

Native run 34975608698 passed 77 shared, 10 iPhone screen and six Watch screen tests, plus physical-target Release compilation and archive checks. Fifteen local release-safety tests also passed. Apple approved build 2 for external TestFlight testing; see TESTFLIGHT.md for the verified publication details.

The import decodes each asset and rejects silence or clipping after AAC mastering. Archive and signing checks require every audio file and the licence manifest to match tested source. Native tests cover controls and gameplay, but cannot judge perceived sound quality, physical Watch output or a complete VoiceOver listening experience. Physical listening remains required.
