import XCTest
@testable import PawBossCore

final class AudioPolicyTests: XCTestCase {
    func testAllSixVolumesDefaultToHalf() {
        let prefs = AppPreferences()
        XCTAssertEqual(prefs.volumes.count, 6)
        for category in AudioMix.categories { XCTAssertEqual(AudioMix.gain(category, volumes: prefs.volumes), 0.5) }
    }
    func testGainIsContinuousClampedAndHasNoAccessibilityOverride() {
        for value in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertEqual(AudioMix.gain("Music", volumes: ["Music":value]), value)
        }
        XCTAssertEqual(AudioMix.gain("Music", volumes: ["Music": -.infinity]), 0.5)
        XCTAssertEqual(AudioMix.gain("Music", volumes: ["Music": -1]), 0)
        XCTAssertEqual(AudioMix.gain("Music", volumes: ["Music": 2]), 1)
    }
    func testLegacyDefaultMigrationPreservesDeliberateSettings() throws {
        let data = Data(#"{"appearance":"Dark","reduceMotion":true,"haptics":false,"volumes":{"Music":0.15,"Ambience":0,"Dogs":0.8,"Customers":0.3,"Office":0.25,"Gameplay":0.35}}"#.utf8)
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertEqual(prefs.volumes["Music"], 0.5); XCTAssertEqual(prefs.volumes["Ambience"], 0)
        XCTAssertEqual(prefs.volumes["Dogs"], 0.8); XCTAssertEqual(prefs.volumes["Customers"], 0.5)
        XCTAssertEqual(prefs.appearance, "Dark"); XCTAssertTrue(prefs.reduceMotion); XCTAssertFalse(prefs.haptics)
        var changed = prefs; changed.volumes["Music"] = 0.15
        let saved = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(changed))
        XCTAssertEqual(saved.volumes["Music"], 0.15)
    }
    func testMusicPlaysWholeLibraryBeforeRepeating() {
        var rotation = MusicRotation()
        let tracks = ["a","b","c","d","e","f"]
        var last: String?
        for _ in 0..<30 {
            var round = Set<String>()
            for _ in tracks {
                let next = rotation.next(from: tracks)
                XCTAssertNotEqual(next, last)
                round.insert(next!); last = next
            }
            XCTAssertEqual(round, Set(tracks))
        }
        XCTAssertNil(rotation.next(from: []))
    }
    func testOutdoorSoundFollowsWeather() {
        XCTAssertEqual(Soundscape.outdoors(weather: "Heavy rain"), .rain)
        XCTAssertEqual(Soundscape.outdoors(weather: "Light rain"), .rain)
        XCTAssertEqual(Soundscape.outdoors(weather: "Warm sunshine"), .outdoors)
    }
}

extension SimulationTests {
    func testExpandedCatalogIsDistinctAndKeepsOriginalIDs() throws {
        let catalog = try Catalog.bundled()
        XCTAssertGreaterThanOrEqual(catalog.dogs.count, 36)
        XCTAssertGreaterThanOrEqual(Set(catalog.dogs.map(\.breed)).count, 30)
        XCTAssertGreaterThanOrEqual(catalog.items.count, 48)
        XCTAssertEqual(Set(catalog.items.map(\.id)).count, catalog.items.count)
        XCTAssertGreaterThanOrEqual(catalog.events.count, 14)
        for id in ["fence","gate","floor","bed","water","toys","cleaning","firstaid","desk","shade","agility","path","garden","grooming","vehicle","extension","staffbench"] {
            XCTAssertEqual(try catalog.item(id).id, id)
        }
    }
    func testEquipmentBenefitsNeedCarePlanAndUsablePlacement() throws {
        var engine = try customerGame()
        let id = engine.state.dogs[0].id
        engine.state.dogs[0].favouriteActivity = "Scent trails"
        engine.state.dogs[0].confidence = 80; engine.state.dogs[0].ageMonths = 36
        engine.state.weather = "Mild"
        engine.state.areas[2].items.append(PlacedItem(definitionID: "snuffle", row: 1, column: 1, installedDay: 0, readyDay: 0))
        XCTAssertEqual(engine.state.equipmentSupport(for: engine.state.dogs[0]).welfare, 1)
        engine.state.areas[2].items[engine.state.areas[2].items.count-1].condition = 44
        XCTAssertEqual(engine.state.equipmentSupport(for: engine.state.dogs[0]).welfare, 0)
        engine.state.areas[2].items[engine.state.areas[2].items.count-1].condition = 100
        engine.state.priorities = ["rest","cleaning"]
        XCTAssertEqual(engine.state.equipmentSupport(for: engine.state.dogs[0]).welfare, 0)
        XCTAssertEqual(engine.state.dogs[0].id, id)
    }
    func testEquipmentCannotReplaceEssentialCare() throws {
        var engine = try customerGame()
        engine.state.dogs[0].favouriteActivity = "Scent trails"
        engine.state.areas[2].items.append(PlacedItem(definitionID: "snuffle", row: 1, column: 1, installedDay: 0, readyDay: 0))
        for a in engine.state.areas.indices { engine.state.areas[a].items.removeAll { $0.definitionID == "water" } }
        XCTAssertEqual(engine.state.equipmentSupport(for: engine.state.dogs[0]).welfare, 0)
    }
    func testEquipmentCannotStackUnlimitedBenefits() throws {
        var engine = try customerGame()
        engine.state.dogs[0].favouriteActivity = "Scent trails"; engine.state.dogs[0].ageMonths = 120
        engine.state.weather = "Warm sunshine"
        for id in ["snuffle","snuffle","garden","orthobed","coolmat","fan"] {
            engine.state.areas[2].items.append(PlacedItem(definitionID: id, row: 1, column: 1, installedDay: 0, readyDay: 0))
        }
        let support = engine.state.equipmentSupport(for: engine.state.dogs[0])
        XCTAssertEqual(support.welfare, 3); XCTAssertEqual(support.stressRelief, 2)
    }
    func testNewEquipmentAndExistingRecordsSurvivePersistence() throws {
        var engine = try customerGame()
        engine.state.areas[2].items.append(PlacedItem(definitionID: "puzzle", row: 1, column: 1, installedDay: 0, readyDay: 0))
        let restored = try JSONDecoder().decode(BusinessState.self, from: JSONEncoder().encode(engine.state))
        _ = try GameEngine(state: restored, catalog: engine.catalog)
        XCTAssertEqual(restored.dogs.map(\.id), engine.state.dogs.map(\.id))
        XCTAssertEqual(restored.customers.map(\.id), engine.state.customers.map(\.id))
        XCTAssertEqual(restored.bookings.map(\.id), engine.state.bookings.map(\.id))
        XCTAssertEqual(restored.areas[2].items.last?.definitionID, "puzzle")
    }
    func testCustomerVarietyAndSchedulesHaveGameplayMeaning() throws {
        var engine = try ready()
        for _ in 0..<60 { engine.generateEnquiry(source: "Local introductions") }
        XCTAssertEqual(Set(engine.state.enquiries.map { $0.customer.communication }).count, 6)
        XCTAssertEqual(Set(engine.state.enquiries.map { $0.customer.bookingHabit }).count, 6)
        XCTAssertEqual(Set(engine.state.enquiries.map { $0.dog.id }).count, 60)
        XCTAssertEqual(CustomerSchedule.offsets(for: "Three weekdays each week"), [0,1,2])
        XCTAssertEqual(CustomerSchedule.offsets(for: "Three alternate weekdays"), [0,2,4])
        XCTAssertEqual(CustomerSchedule.service(for: "Two morning half-days"), .halfDay)
        XCTAssertTrue(engine.state.enquiries.contains { $0.dog.ageMonths < 12 })
    }
    func testCareEquipmentIsRecordedAndStillOnlyAppliedOnce() throws {
        var engine = try customerGame()
        let id = engine.state.dogs[0].id
        engine.state.dogs[0].favouriteActivity = "Scent trails"
        engine.state.areas[2].items.append(PlacedItem(definitionID: "snuffle", row: 1, column: 1, installedDay: 0, readyDay: 0))
        apply(.checkIn(id), to: &engine); apply(.care(id), to: &engine)
        XCTAssertTrue(engine.state.dogs[0].observations.last!.text.contains("Scent equipment"))
        let welfare = engine.state.dogs[0].welfare
        XCTAssertFalse(engine.perform(.care(id)).applied)
        XCTAssertEqual(engine.state.dogs[0].welfare, welfare)
    }
}
