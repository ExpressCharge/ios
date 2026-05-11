//
//  CapabilitiesTests.swift
//  CapabilitiesTests
//

import Foundation
import Testing

@testable import Capabilities
@testable import Models

@Suite("Capabilities — derivation + legality")
struct CapabilitiesTests {

    // MARK: - isLegalSet — exhaustive over the 16 subsets

    @Test func isLegalSetExhaustive() {
        // Build every subset of `DeviceCapability.allCases` bitwise
        // and check legality matches the spec:
        //   illegal iff `kiosk ∈ caps` AND |caps ∩ {scanner, user}| ≠ 1.
        // `.managed` is intentionally orthogonal to the kiosk rule —
        // its presence neither helps nor hurts legality.
        let all = DeviceCapability.allCases
        for mask in 0..<(1 << all.count) {
            var caps: Set<DeviceCapability> = []
            for (i, c) in all.enumerated() where (mask >> i) & 1 == 1 {
                caps.insert(c)
            }
            let kiosk = caps.contains(.kiosk)
            let exclusivePairCount = caps.intersection([.scanner, .user]).count
            let expected = kiosk ? (exclusivePairCount == 1) : true
            #expect(
                DeviceCapability.isLegalSet(caps) == expected,
                "set \(caps) → expected \(expected)"
            )
        }
    }

    // Spot-check the named cases for clarity even though the exhaustive
    // test above subsumes them.

    @Test func isLegalSet_namedCases() {
        #expect(DeviceCapability.isLegalSet([]))
        #expect(DeviceCapability.isLegalSet([.scanner]))
        #expect(DeviceCapability.isLegalSet([.user]))
        #expect(DeviceCapability.isLegalSet([.charger]))
        #expect(DeviceCapability.isLegalSet([.scanner, .user]))
        #expect(DeviceCapability.isLegalSet([.scanner, .kiosk]))
        #expect(DeviceCapability.isLegalSet([.user, .kiosk]))
        // Illegal: kiosk + both scanner+user, kiosk alone, kiosk + neither.
        #expect(!DeviceCapability.isLegalSet([.kiosk]))
        #expect(!DeviceCapability.isLegalSet([.scanner, .user, .kiosk]))
        #expect(!DeviceCapability.isLegalSet([.charger, .kiosk]))
    }

    // MARK: - Derivation helpers

    @Test func canSeeChargersTab() {
        #expect(!DeviceCapability.canSeeChargersTab([]))
        #expect(!DeviceCapability.canSeeChargersTab([.scanner]))
        #expect(DeviceCapability.canSeeChargersTab([.user]))
        #expect(DeviceCapability.canSeeChargersTab([.user, .scanner]))
        #expect(DeviceCapability.canSeeChargersTab([.user, .kiosk]))
    }

    @Test func canScan() {
        #expect(!DeviceCapability.canScan([]))
        #expect(DeviceCapability.canScan([.scanner]))
        #expect(!DeviceCapability.canScan([.user]))
        #expect(DeviceCapability.canScan([.scanner, .user]))
    }

    @Test func isKiosk() {
        #expect(!DeviceCapability.isKiosk([]))
        #expect(!DeviceCapability.isKiosk([.user]))
        #expect(DeviceCapability.isKiosk([.scanner, .kiosk]))
    }

    @Test func tabBarVisible() {
        // Visible iff BOTH scanner AND user.
        #expect(!DeviceCapability.tabBarVisible([]))
        #expect(!DeviceCapability.tabBarVisible([.scanner]))
        #expect(!DeviceCapability.tabBarVisible([.user]))
        #expect(DeviceCapability.tabBarVisible([.scanner, .user]))
        #expect(DeviceCapability.tabBarVisible([.scanner, .user, .kiosk]))
    }

    @Test func isAppCanonicalCapability() {
        #expect(DeviceCapability.scanner.isAppCanonicalCapability)
        #expect(DeviceCapability.user.isAppCanonicalCapability)
        #expect(DeviceCapability.kiosk.isAppCanonicalCapability)
        #expect(!DeviceCapability.charger.isAppCanonicalCapability)
    }

    // MARK: - CapabilityMetadata

    @Test func metadataAllCoversEveryCapability() {
        let keys = Set(CapabilityMetadata.all.map(\.key))
        #expect(keys == Set(DeviceCapability.allCases))
    }

    @Test func metadataLookupRoundTrip() {
        for c in DeviceCapability.allCases {
            let m = CapabilityMetadata.metadata(for: c)
            #expect(m.key == c)
            #expect(!m.displayName.isEmpty)
            #expect(!m.description.isEmpty)
            #expect(!m.sfSymbol.isEmpty)
        }
    }

    @Test func metadataCopyMatchesSpec() {
        let scanner = CapabilityMetadata.metadata(for: .scanner)
        #expect(scanner.displayName == "NFC scanner")
        #expect(scanner.description == "Use this device to read NFC chargecards")
        #expect(scanner.sfSymbol == "wave.3.right.circle.fill")

        let charger = CapabilityMetadata.metadata(for: .charger)
        #expect(charger.displayName == "EV charger")
        #expect(charger.description == "This device is a charging station")
        #expect(charger.sfSymbol == "bolt.car.fill")

        let user = CapabilityMetadata.metadata(for: .user)
        #expect(user.displayName == "Use chargers")
        #expect(user.description == "List chargers, start/stop, see sessions, cancel reservations")
        #expect(user.sfSymbol == "bolt.fill")

        let kiosk = CapabilityMetadata.metadata(for: .kiosk)
        #expect(kiosk.displayName == "Kiosk mode")
        #expect(kiosk.description == "Single-purpose appliance, no chrome / no settings")
        #expect(kiosk.sfSymbol == "lock.display")
    }

    @Test func registrationOptionsExcludesCharger() {
        let keys = Set(CapabilityMetadata.registrationOptions.map(\.key))
        #expect(keys == [.scanner, .user, .kiosk, .managed])
        #expect(!keys.contains(.charger))
    }

    // MARK: - .managed (Phase 2 / Bundle 2a)

    @Test func managedCopyMatchesSpec() {
        let m = CapabilityMetadata.metadata(for: .managed)
        #expect(m.displayName == "Managed")
        #expect(
            m.description
                == "Admin-fleet posture; allows admins to read this device's location"
        )
        #expect(!m.sfSymbol.isEmpty)
    }

    @Test func managedIsOrthogonalToKioskExclusivity() {
        // Adding `.managed` to a legal set keeps it legal.
        #expect(DeviceCapability.isLegalSet([.scanner, .managed]))
        #expect(DeviceCapability.isLegalSet([.user, .managed]))
        #expect(DeviceCapability.isLegalSet([.scanner, .kiosk, .managed]))
        #expect(DeviceCapability.isLegalSet([.user, .kiosk, .managed]))
        // Adding `.managed` to an illegal kiosk set keeps it illegal.
        #expect(!DeviceCapability.isLegalSet([.kiosk, .managed]))
        #expect(!DeviceCapability.isLegalSet([.scanner, .user, .kiosk, .managed]))
    }

    @Test func managedIsNotAppCanonical() {
        // The "main screen" gates are scanner/user/kiosk — not managed.
        #expect(!DeviceCapability.managed.isAppCanonicalCapability)
    }

    @Test func managedDoesNotAffectDerivedHelpers() {
        #expect(!DeviceCapability.canSeeChargersTab([.managed]))
        #expect(!DeviceCapability.canScan([.managed]))
        #expect(!DeviceCapability.isKiosk([.managed]))
        #expect(!DeviceCapability.tabBarVisible([.managed]))
    }

    @Test func appRegistrationOptionsIncludesManaged() {
        #expect(DeviceCapability.appRegistrationOptions.contains(.managed))
        #expect(!DeviceCapability.appRegistrationOptions.contains(.charger))
    }
}
