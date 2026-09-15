import SwiftUI
import PawBossCore

struct SettingsView: View {
    @EnvironmentObject private var store: BusinessStore
    var body: some View {
        List {
            Section("Appearance") {
                Picker("Appearance", selection: $store.preferences.appearance) { ForEach(["System", "Light", "Dark"], id: \.self) { Text($0) } }
                    .accessibilityIdentifier("appearancePicker")
                Toggle("Reduce motion", isOn: $store.preferences.reduceMotion)
                Toggle("Business adviser suggestions", isOn: $store.preferences.adviser)
                Toggle("Haptics", isOn: $store.preferences.haptics)
            }
            Section("Audio") {
                ForEach(AudioMix.categories, id: \.self) { category in
                    VStack(alignment: .leading) {
                        HStack { Text(category).font(.headline); Spacer(); Text("\(Int((AudioMix.gain(category, volumes: store.preferences.volumes) * 100).rounded()))%").monospacedDigit() }.accessibilityHidden(true)
                        Slider(value: Binding(get: { AudioMix.gain(category, volumes: store.preferences.volumes) }, set: { store.preferences.volumes[category] = $0; store.savePreferences() }), in: 0...1, step: 0.05)
                            .accessibilityLabel("\(category) volume")
                            .accessibilityValue("\(Int((store.preferences.volumes[category, default: 0] * 100).rounded())) percent")
                            .accessibilityIdentifier("volume-\(category)")
                    }
                }
                Button("Reset all volumes to 50 percent", systemImage: "arrow.counterclockwise") { store.preferences.volumes = AudioMix.defaults; store.savePreferences(); store.announce("All six volumes set to 50 percent.") }
                NavigationLink("Sound Library", destination: SoundLibraryView())
            }
            Section("Notifications") {
                Toggle("Business reminders", isOn: Binding(get: { store.preferences.notificationEnabled }, set: { enabled in
                    if !enabled { store.preferences.notificationEnabled = false; store.savePreferences() }
                    else { Task { do {
                        store.preferences.notificationEnabled = try await store.notificationService.requestPermission()
                        store.savePreferences()
                        if !store.preferences.notificationEnabled { store.errorMessage = "Notifications are not permitted. You can change this in system Settings." }
                    } catch { store.errorMessage = error.localizedDescription } } }
                }))
                ForEach(store.preferences.notifications.keys.sorted(), id: \.self) { category in
                    Toggle(category, isOn: Binding(get: { store.preferences.notifications[category, default: false] }, set: { store.preferences.notifications[category] = $0; store.savePreferences() }))
                }
            }
            Section("Save and Companion") {
                ValueRow(title: "Save", value: store.isWatch ? "iPhone business snapshot; Watch actions are queued locally" : "Automatic local save after each change")
                ValueRow(title: "Cloud backup", value: "Not enabled")
                ValueRow(title: "Connection", value: store.syncStatus)
                Button("Refresh Sync", systemImage: "arrow.triangle.2.circlepath") { store.refreshSync() }
                if store.isWatch {
                    ValueRow(title: "Pending actions", value: "\(store.outbox.pending.count)")
                    ForEach(store.outbox.results.suffix(10).reversed()) { result in ValueRow(title: result.applied ? "Applied" : "Not applied", value: result.message) }
                } else if store.state != nil {
                    #if os(iOS)
                    ShareLink(item: store.repository.url) { Label("Export My Business Save", systemImage: "square.and.arrow.up") }
                    #endif
                }
                if !store.status.isEmpty { ValueRow(title: "Last action", value: store.status) }
            }
            NavRow(title: "About PawBoss", icon: "info.circle", destination: .about)
        }.listStyle(.plain).navigationTitle("Settings")
            .onChange(of: store.preferences.appearance) { _, _ in store.savePreferences() }
            .onChange(of: store.preferences.reduceMotion) { _, _ in store.savePreferences() }
            .onChange(of: store.preferences.adviser) { _, _ in store.savePreferences() }
            .onChange(of: store.preferences.haptics) { _, _ in store.savePreferences() }
    }
}
struct HelpView: View {
    @State private var search = ""
    private let topics: [(String, String)] = [
        ("Your first opening", "Name the business. In Premises, configure a room for play and rest and fit washable flooring. Add a bed, water bowl, enrichment toys, cleaning cupboard and first aid cabinet. Build the boundary, then replace one panel with a gate. In Office, Business, register, insure, apply for a licence and book an inspection. Complete two days for the inspection to take place. Correct any findings, then open for care."),
        ("Finding your first customers", "A new business has no dogs, customers or bookings. Start a local campaign or form a community partnership. Complete a game day to receive enquiries. Read each dog's profile, quote, request information, accept, waitlist or decline. Acceptance creates one customer, one dog and the first booking."),
        ("Running a care day", "Today lists arrivals, collections, staffing and care records. Check dogs in, record care and medication, add observations, and check out with a handover. Complete Day handles remaining scheduled arrivals, normal routines and collections. It does not invent medication records. Missed medication damages welfare and triggers a care guarantee refund."),
        ("Choosing priorities", "In Office, Business, choose up to three daily priorities. Rest and enrichment support individual welfare; cleaning protects hygiene; maintenance tackles wear. Consider what your current dogs and staff need before changing these choices."),
        ("VoiceOver actions", "On dog, customer, staff and message rows, use the Actions rotor for relevant shortcuts. Activate a row for its profile. Destructive decisions ask for confirmation. Each area has row and column pickers, a spoken selected square and direct build, move and remove actions. No dragging is required."),
        ("Building and moving", "Choose an area, row and column in Premises. The selected square reports the top object, with underlying items in its details. Floors and furniture can share a square. Fences belong on the edge; gates replace panels. The full-boundary command charges only for missing panels. Close the site before moving or removing equipment."),
        ("Customers and complaints", "Customer trust grows from actual care and communication. Reviews refer to their dog's experience. Inbox filters include complaints and reviews. Open a message to choose a response. Refunds can never exceed the customer's recorded payment."),
        ("Staffing and payroll", "The owner can provide initial care without drawing a salary. Paid staff have contracted hours, wages, employer contributions and pension costs. Hire, review pay, train, promote and arrange the rota through their profile. Leave and sickness reduce available cover. Dismissal settles agreed notice pay."),
        ("Money and reports", "Finance explains every movement in the bank. Borrowing is not income, and equipment investment is separate from operating expenses. Reports contain charts and individual accessible values. Forecasts use confirmed bookings, not guaranteed future demand. Prices are game assumptions inspired by UK businesses, not financial or legal advice."),
        ("Services and expansion", "Day care and half-days form the opening business. Specialist care needs trained staff and a quiet room. Grooming needs its own room, station and groomer; transport needs a vehicle and trained driver. Boarding requires space, training and approval. Planning and construction take game time. Growth still needs safe staffing and a cash reserve."),
        ("Apple Watch and offline actions", "The iPhone holds the authoritative business. Watch actions are saved in a local queue and confirmed by iPhone. A sleeping live connection does not mean background delivery has failed. Refresh Sync retries safely. If the day or business changed before an action arrives, it is rejected with a reason so it cannot affect the wrong care record."),
        ("Saving and reminders", "Meaningful changes save automatically before they appear as successful. A previous local backup is retained. Export saves from Settings on iPhone. The game does not advance while closed. Optional reminders point to unfinished records; they do not mean that real animals are awaiting care. iCloud backup is not enabled in this build."),
        ("Audio and presentation", "All six volume controls start at 50 percent, with the same levels whether VoiceOver is on or off. Zero is silent. Settings, Sound Library has separate previews; music and ambience previews last up to 15 seconds. Office sounds accompany administration, care-room sounds accompany dogs, and garden or rain recordings accompany the outdoor area. Music rotates through complete tracks without immediate repeats. Audio never replaces written or spoken results. Appearance follows the system unless you choose Light or Dark. System Dynamic Type remains supported.")
    ]
    var body: some View {
        List {
            ForEach(topics.filter { search.isEmpty || $0.0.localizedCaseInsensitiveContains(search) || $0.1.localizedCaseInsensitiveContains(search) }, id: \.0) { title, text in
                Section(title) { Text(text).fixedSize(horizontal: false, vertical: true) }
            }
        }.listStyle(.plain).searchable(text: $search, prompt: "Search the guide").navigationTitle("How to Play")
    }
}
struct AboutView: View {
    var body: some View {
        List {
            Image("Brand").resizable().scaledToFit().frame(maxWidth: 160).accessibilityHidden(true)
            Text("PawBoss").font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text("A Dog Day Care Simulation")
            ValueRow(title: "Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
            Text("A personal project by Sidney Tambin.")
            Text("Original game design: PawBoss Design Bible. Native Apple artwork generated for PawBoss. Recorded sound and music used under the licences listed in Audio Credits. System symbols and native controls by Apple.")
            NavigationLink("Audio Credits", destination: AudioCreditsView())
            Text("All people, animals and businesses in the simulation are fictional. Financial, licensing and care systems are gameplay models, not professional advice.")
        }.listStyle(.plain).navigationTitle("About")
    }
}
struct SoundLibraryView: View {
    @EnvironmentObject private var store: BusinessStore
    var body: some View {
        List {
            Button("Stop Preview", systemImage: "stop.circle") { store.feedback.stopPreview() }
                .accessibilityIdentifier("stopAudioPreview")
            ForEach(AudioMix.categories, id: \.self) { category in
                Section(category) {
                    ForEach(store.feedback.library.assets.filter { $0.category == category }) { asset in
                        Button("Preview \(asset.title)", systemImage: "play.circle") { store.feedback.preview(asset.id) }
                            .accessibilityIdentifier("preview-\(asset.id)")
                            .accessibilityHint("Uses the \(category.lowercased()) volume. Stops any previous preview.")
                    }
                }
            }
            NavigationLink("Audio Credits", destination: AudioCreditsView())
        }.listStyle(.plain).navigationTitle("Sound Library").onDisappear { store.feedback.stopPreview() }
    }
}
struct AudioCreditsView: View {
    private let library = AudioLibrary.bundled()
    var body: some View {
        List {
            Text("Recordings converted to AAC, level matched and edge faded. Dog effects are excerpts. CC0 recordings are public-domain dedications; The Office is used under Creative Commons Attribution 3.0.")
            ForEach(library.sources) { source in
                Section(source.title) {
                    Text(source.author)
                    if let page = URL(string: source.page) { Link("Original recording: \(source.title)", destination: page) }
                    if let licence = URL(string: source.licenseURL) { Link(source.license, destination: licence) }
                }
            }
        }.listStyle(.plain).navigationTitle("Audio Credits")
    }
}
