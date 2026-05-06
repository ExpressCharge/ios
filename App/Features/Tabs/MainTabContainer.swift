//
//  MainTabContainer.swift
//  ExpresScan
//
//  Wave 6 / Slice F. Capability-derived shell.
//
//  Replaces the bare `ReadyView()` rendering at the `.ready` route.
//  Decides between a native iOS-26 liquid-glass `TabView` (when both
//  `scanner` AND `user` are present), a lone-capability root view
//  (no tab bar at all — the lone screen is the SwiftUI hierarchy
//  root), or a chrome-stripped `KioskShell` wrapping the lone view.
//
//  Slice G will swap the placeholder capability source for a real
//  `DeviceStateCoordinator` read; until then, scanner-only is the
//  default so the existing scan flow keeps working.
//

import Capabilities
import Models
import SwiftUI

/// Top-level shell for the `.ready` route. Owns the capability-derived
/// VM and renders one of: lone screen, two-tab `TabView`, or kiosk wrap.
public struct MainTabContainer: View {

    @State private var viewModel: MainTabContainerViewModel

    public init(capabilities: Set<DeviceCapability>) {
        _viewModel = State(initialValue: MainTabContainerViewModel(capabilities: capabilities))
    }

    public var body: some View {
        // `.id(...)` so a structural change (capabilities-changed via
        // SSE in slice G) cleanly fades the shell rather than trying to
        // diff a TabView into a lone view.
        Group {
            switch viewModel.shell {
            case .loneScan:
                NavigationStack {
                    ReadyView()
                }
            case .loneChargers:
                NavigationStack {
                    ChargersTabView()
                        .expressScanToolbarMenu()
                }
            case .tabs:
                liquidGlassTabs
            case .kioskScan:
                KioskShell {
                    ReadyView()
                }
            case .kioskChargers:
                KioskShell {
                    ChargersTabView()
                }
            }
        }
        .id(capabilitySetHash)
        .animation(.easeInOut(duration: 0.25), value: capabilitySetHash)
    }

    /// Stable hash of the current capability set so structural changes
    /// trigger an `.id`-driven crossfade in SwiftUI.
    private var capabilitySetHash: Int {
        var hasher = Hasher()
        for cap in viewModel.capabilities.sorted(by: { $0.rawValue < $1.rawValue }) {
            hasher.combine(cap.rawValue)
        }
        return hasher.finalize()
    }

    /// Native iOS-26 liquid-glass two-tab `TabView` using the value-type
    /// `Tab` API. `.tabBarMinimizeBehavior(.onScrollDown)` enables the
    /// shrink-on-scroll polish that's the headline of the new tab bar.
    @ViewBuilder
    private var liquidGlassTabs: some View {
        TabView {
            Tab("Chargers", systemImage: "bolt.fill") {
                NavigationStack {
                    ChargersTabView()
                        .expressScanToolbarMenu()
                }
            }
            Tab("Scan", systemImage: "wave.3.right.circle.fill") {
                NavigationStack {
                    ReadyView()
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

// `ChargersPlaceholderView` was removed in Slice I — `ChargersTabView`
// is now the real implementation.
