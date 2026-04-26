# Frontend Implementation Plan (`expresscharge`)

All work is in `/Users/scruffy/Documents/Repos/expresscharge`. Tech: Fresh +
Preact + islands + shadcn/ui + Tailwind + lucide-preact.

## Phase split

The work is split across three phases for ordering, NOT for gating — the
system is not live yet, so all phases ship as breaking renames. Phase 1 is the
shared infrastructure (icon resolver, capability pill, design tokens). Phase 2
adds the new admin Devices surface. Phase 3 swaps the scan modal's picker.

---

## Phase 1: Refactors (unblocks both teams; ship anytime)

These changes have zero behavior impact. They unblock the iOS team (design
tokens) and the Phase 2/3 work (icon resolver, capability pill).

### Files to create

```
src/lib/utils/device-icons.ts                 # getDeviceIcon(kind, formFactor?)
components/devices/CapabilityPill.tsx         # small badge for "tap" / "ev"
components/brand/devices/IPhoneIcon.tsx       # SVG icon w/ halo
components/brand/devices/LaptopIcon.tsx       # SVG icon w/ halo
docs/design-tokens.json                       # exported tokens for iOS
```

### Files to modify

```
islands/shared/charger-visuals.ts → device-visuals.ts
   add: normalizeDeviceStatus(), DEVICE_STATUS_HALO
   keep: existing normalizeStatus(), STATUS_HALO (charger-specific, unchanged)
islands/ChargerCard.tsx
   replace direct chargerFormFactorIcons import → getDeviceIcon("charger", formFactor)
components/scan/ScanPanel.tsx
   change copy "Connecting to charger log stream…" → "Connecting…"
```

### `getDeviceIcon` resolver

```ts
import type { ComponentType } from "preact";
import { chargerFormFactorIcons, GenericChargerIcon }
  from "../../components/brand/chargers/index.ts";
import { IPhoneIcon } from "../../components/brand/devices/IPhoneIcon.tsx";
import { LaptopIcon } from "../../components/brand/devices/LaptopIcon.tsx";

export interface DeviceIconProps {
  size?: "sm" | "md" | "lg";
  haloColor?: string;
  className?: string;
}

export function getDeviceIcon(
  kind: "charger" | "phone_nfc" | "laptop_nfc",
  formFactor?: string,
): ComponentType<DeviceIconProps> {
  if (kind === "charger") {
    return chargerFormFactorIcons[formFactor ?? "generic"] ?? GenericChargerIcon;
  }
  if (kind === "phone_nfc") return IPhoneIcon;
  if (kind === "laptop_nfc") return LaptopIcon;
  return GenericChargerIcon;
}
```

---

## Phase 2: New Devices admin surface (unflagged; deploy after Phase 1)

A new admin page at `/admin/devices` listing all registered devices (chargers
shown via the `tappable_devices` view OR omitted — see decision below).

### Decision: **Devices page shows phones only** for v1

The view unions chargers + phones, but the `/admin/devices` page filters to
`kind != 'charger'` to avoid duplicating chargers in two places (they already
have their own page). The picker (Phase 3) does union them.

### Files to create

```
routes/admin/devices/index.tsx               # listing
routes/admin/devices/[deviceId].tsx          # detail (with charger redirect)

islands/DeviceCard.tsx                        # mirror of ChargerCard for phones
components/devices/DevicesStatStrip.tsx       # 5-cell stat strip (teal accent)
components/devices/DeviceIdentityCard.tsx     # detail-page identity SectionCard
components/devices/DeviceFiltersBar.tsx       # type/online/owner filters
islands/devices/DeviceActionsMenu.tsx         # rename / deregister row actions
```

### Files to modify

```
src/lib/admin-navigation.ts                   # add "Devices" entry under Operations
```

### Page structure (matches CLAUDE.md primitives)

```
SidebarLayout accentColor="teal"
  PageCard title="Devices" colorScheme="teal"
    DevicesStatStrip (total / online / offline / phones / chargers)
    DeviceFiltersBar (type | online | owner search)
    Table (id | label | model | owner | last seen | actions)
    Pagination
```

Detail page `/admin/devices/[deviceId]`:

```
SidebarLayout accentColor="teal"
  PageCard title={device.label} colorScheme="teal"
    DeviceIdentityCard (model, OS, app version, owner, last seen, push token presence)
    SectionCard "Capabilities" (CapabilityPill row)
    SectionCard "Recent scans" (last 50, table)
    SectionCard "Heartbeat" (placeholder for now)
    [headerActions] Trigger scan, Force deregister
```

If the resolved row has `kind === 'charger'`, server-side redirect to
`/admin/chargers/{chargeBoxId}` (no shared detail UI — keep the two flavors
separate).

### Sidebar nav addition

In `src/lib/admin-navigation.ts`:

```ts
{
  id: "nav:/admin/devices",
  label: "Devices",
  href: "/admin/devices",
  icon: "Smartphone",  // lucide
  accent: "teal",
  section: "Operations",
  // Position: after Chargers, before Reservations
}
```

---

## Phase 3: Scan modal picker migration

Behavior change. No feature flag — `/api/auth/scan-charger-list` is renamed
outright to `/api/auth/scan-tap-targets` (backend) with the union response
shape, and the picker is replaced everywhere.

### Files to create

```
components/scan/DevicePickerInline.tsx        # replaces ChargerPickerInline
```

### Files to modify

```
islands/shared/use-scan-tag.ts
   resolveChargeBoxId → resolveTapTargetDeviceId
   /api/auth/scan-charger-list → /api/auth/scan-tap-targets
   ChargerListEntry → TapTargetEntry
   chargeBoxId → deviceId (in opts and internal state)
islands/TapToAddModal.tsx
   ChargerPickerInline → DevicePickerInline
   pass tapTarget shape down to ScanPanel
components/scan/ScanPanel.tsx
   pass through new readerName variants by kind
   no copy hardcoding — copy comes from the caller
src/lib/command-palette/commands.ts
   The "Scan EV Card" action (commit 99c287a) dispatches
   `cmdk:scan-picker:open`. Whatever component listens (the
   `ScanTagPaletteHost` referenced in commands.ts comments) needs the same
   chargeBoxId → deviceId rename + DevicePickerInline swap.
```

### Picker behavior

- Auto-pick when exactly one online tap-capable target is **owned by the
  current user** (their own phone). Otherwise show the picker.
- Group sections in the picker:
  - "Chargers" — `BatteryCharging` icon, orange accent
  - "Your phone" — `Smartphone` icon, "(this device)" suffix
  - "Other devices" — `Smartphone` icon
- Sort within groups: online first, then by `last_seen_at` desc.
- Show offline targets grayed-out with last-seen subtitle ("Offline — last seen 2h ago"), disabled click.

---

## Design tokens for iOS team (`docs/design-tokens.json`)

JSON file the iOS engineer can drop into Xcode or use as a reference for
asset-catalog Color Sets:

```json
{
  "colors": {
    "primaryCyan":     { "light": "oklch(0.55 0.20 220)", "dark": "oklch(0.75 0.15 200)" },
    "voltGreen":       { "light": "oklch(0.60 0.22 145)", "dark": "oklch(0.75 0.22 145)" },
    "warningAmber":    { "light": "oklch(0.75 0.18 85)",  "dark": "oklch(0.85 0.18 85)" },
    "destructiveRose": { "light": "oklch(0.50 0.24 25)",  "dark": "oklch(0.55 0.20 25)" },
    "accentTeal":      { "light": "oklch(0.60 0.13 196)", "dark": "oklch(0.72 0.14 196)" },
    "background":      { "light": "oklch(0.98 0.005 220)","dark": "oklch(0.12 0.02 240)" },
    "card":            { "light": "oklch(1.00 0.000 0)",  "dark": "oklch(0.15 0.02 240)" },
    "borderSubtle":    { "light": "oklch(0.88 0.025 220)","dark": "oklch(0.28 0.03 240)" }
  },
  "typography": {
    "stack": "system",
    "monoStack": "ui-monospace, SFMono-Regular, Menlo, Monaco"
  },
  "spacing": { "xs": 4, "sm": 8, "md": 12, "base": 16, "lg": 24, "xl": 32 },
  "radius": { "sm": 6, "md": 8, "lg": 10, "xl": 14, "pill": 999 }
}
```

OKLCH triplets convert to sRGB hex via the standard perceptual-to-sRGB path.
Suggested asset-catalog values (approximations):

| Token | Light hex | Dark hex |
|---|---|---|
| primaryCyan | `#1A8FA8` | `#5DC4D9` |
| voltGreen   | `#3A9A52` | `#6ACA7A` |
| warningAmber| `#D9A35F` | `#E8B96B` |
| destructiveRose | `#B83838` | `#C75252` |
| accentTeal  | `#2A9588` | `#3CB1A2` |
| background  | `#F5FAFB` | `#181C26` |
| card        | `#FFFFFF` | `#22262E` |
| borderSubtle| `#D8E0E5` | `#3A4250` |

## Acceptance criteria

Phase 1: zero visual regressions in existing chargers page; unit test
`getDeviceIcon` returns correct component for each kind.

Phase 2: `/admin/devices` listing renders, filters work, detail page renders
identity card with all fields, force-deregister button works (admin path only,
confirmation modal, audit row created on submit).

Phase 3: with flag ON, scan modal auto-picks own-phone correctly, picker groups
work, scan-arm dispatches to the correct backend endpoint based on selected
target type.
