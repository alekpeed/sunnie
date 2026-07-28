import Foundation
import Testing
@testable import SunnieShared

@Suite("Deterministic action keys")
struct ActionKeyFactoryTests {

    @Test("The same action produces the same key every time")
    func keyIsStable() {
        let performedAt = TestFixtures.date(2026, 7, 15, 9, 30)

        let first = ActionKeyFactory.plantCare(
            plantID: TestFixtures.plantID, careType: .water, performedAt: performedAt
        )
        let second = ActionKeyFactory.plantCare(
            plantID: TestFixtures.plantID, careType: .water, performedAt: performedAt
        )

        #expect(first == second)
    }

    @Test("Two devices logging the same watering within a minute collapse to one key")
    func watchAndPhoneCollapseWithinGranularity() {
        // This is the case FIRST_VERTICAL_SLICE.md calls out: the user taps Water
        // on the Watch, the phone applies it, and the queued transfer arrives
        // again seconds later. Neither the device nor the exact second is part of
        // the key, so both resolve to one care event.
        let watchTap = TestFixtures.date(2026, 7, 15, 9, 30)
        let phoneReplay = watchTap.addingTimeInterval(37)

        let watchKey = ActionKeyFactory.plantCare(
            plantID: TestFixtures.plantID, careType: .water, performedAt: watchTap
        )
        let phoneKey = ActionKeyFactory.plantCare(
            plantID: TestFixtures.plantID, careType: .water, performedAt: phoneReplay
        )

        #expect(watchKey == phoneKey)
    }

    @Test("A genuine second watering days later gets its own key")
    func laterCareIsDistinct() {
        let first = ActionKeyFactory.plantCare(
            plantID: TestFixtures.plantID,
            careType: .water,
            performedAt: TestFixtures.date(2026, 7, 15, 9)
        )
        let later = ActionKeyFactory.plantCare(
            plantID: TestFixtures.plantID,
            careType: .water,
            performedAt: TestFixtures.date(2026, 7, 22, 9)
        )

        #expect(first != later)
    }

    @Test("Different plants and different care types never share a key")
    func distinctSubjectsProduceDistinctKeys() {
        let performedAt = TestFixtures.date(2026, 7, 15, 9, 30)
        let otherPlant = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

        let water = ActionKeyFactory.plantCare(
            plantID: TestFixtures.plantID, careType: .water, performedAt: performedAt
        )
        let mist = ActionKeyFactory.plantCare(
            plantID: TestFixtures.plantID, careType: .mist, performedAt: performedAt
        )
        let otherPlantWater = ActionKeyFactory.plantCare(
            plantID: otherPlant, careType: .water, performedAt: performedAt
        )

        #expect(water != mist)
        #expect(water != otherPlantWater)
        #expect(mist != otherPlantWater)
    }

    @Test("Custom care types keep their content identity in the key")
    func customCareTypeIsIdentified() {
        let performedAt = TestFixtures.date(2026, 7, 15, 9, 30)
        let a = ActionKeyFactory.plantCare(
            plantID: TestFixtures.plantID,
            careType: .custom("sunnie.care.dust"),
            performedAt: performedAt
        )
        let b = ActionKeyFactory.plantCare(
            plantID: TestFixtures.plantID,
            careType: .custom("sunnie.care.trim"),
            performedAt: performedAt
        )

        #expect(a != b)
        #expect(a.rawValue.contains("sunnie.care.dust"))
    }

    @Test("Bucketing floors consistently on both sides of the epoch")
    func bucketingFloors() {
        let justBefore = Date(timeIntervalSince1970: -1)
        let justAfter = Date(timeIntervalSince1970: 1)

        #expect(ActionKeyFactory.bucketedEpoch(justBefore) == -1)
        #expect(ActionKeyFactory.bucketedEpoch(justAfter) == 0)
    }

    @Test("Progression keys derive from the care key, so replays cannot double-award")
    func progressionKeyDerivesFromAction() {
        let actionKey = ActionKeyFactory.plantCare(
            plantID: TestFixtures.plantID,
            careType: .water,
            performedAt: TestFixtures.date(2026, 7, 15, 9, 30)
        )

        let first = ActionKeyFactory.progression(
            type: .plantCareCompleted, sourceActionKey: actionKey
        )
        let second = ActionKeyFactory.progression(
            type: .plantCareCompleted, sourceActionKey: actionKey
        )

        #expect(first == second)
        #expect(first.contains(actionKey.rawValue))
    }

    @Test("Care type storage keys survive a round trip")
    func careTypeStorageKeyRoundTrips() throws {
        for careType in CareType.builtIn {
            let restored = try #require(CareType(storageKey: careType.storageKey))
            #expect(restored == careType)
        }

        let custom = CareType.custom("sunnie.care.dust")
        #expect(CareType(storageKey: custom.storageKey) == custom)
        #expect(CareType(storageKey: "notARealCareType") == nil)
        #expect(CareType(storageKey: "custom:") == nil)
    }
}
