# ExpresScan color tokens

The iOS color palette is converted from the canonical ExpresSync OKLch tokens
defined in [`expressync/assets/styles.css`](../expressync/assets/styles.css)
(`:root` and `.dark` blocks). Each token ships as a Display P3 colorset under
`App/Resources/Assets.xcassets/<Token>.colorset/Contents.json`.

This document is the source of truth for that mapping. When the web tokens
move, regenerate the colorsets via `/tmp/oklch-convert/convert.mjs` (the
throwaway script kept the conversion deterministic) and refresh this table.

## Token table

| Token             | Light OKLch              | Light P3 hex | Dark OKLch              | Dark P3 hex |
|-------------------|--------------------------|--------------|-------------------------|-------------|
| `PrimaryCyan`     | `oklch(0.55 0.20 220)`   | `#0082bb`    | `oklch(0.75 0.15 200)`  | `#3ec6d1`   |
| `VoltGreen`       | `oklch(0.60 0.22 145)`   | `#349c29`    | `oklch(0.75 0.22 145)`  | `#66cd5b`   |
| `WarningAmber`    | `oklch(0.75 0.18 85)`    | `#d8a400`    | `oklch(0.85 0.18 85)`   | `#f9c53b`   |
| `DestructiveRose` | `oklch(0.50 0.24 25)`    | `#b70013`    | `oklch(0.65 0.24 25)`   | `#ec4644`   |
| `Background`      | `oklch(0.98 0.005 220)`  | `#f6f9fb`    | `oklch(0.12 0.02 240)`  | `#02060c`   |
| `Card`            | `oklch(1 0 0)`           | `#ffffff`    | `oklch(0.15 0.025 240)` | `#040c14`   |
| `Foreground`      | `oklch(0.18 0.03 240)`   | `#08131d`    | `oklch(0.95 0.01 220)`  | `#e9f0f3`   |
| `Muted`           | `oklch(0.95 0.015 220)`  | `#e6f1f5`    | `oklch(0.20 0.025 240)` | `#0e171f`   |
| `MutedForeground` | `oklch(0.45 0.03 240)`   | `#4a5763`    | `oklch(0.65 0.025 220)` | `#839299`   |
| `BorderSubtle`    | `oklch(0.88 0.025 220)`  | `#cadbe2`    | `oklch(0.25 0.03 240)`  | `#17232e`   |
| `Success`         | `oklch(0.60 0.22 145)`   | `#349c29`    | `oklch(0.75 0.22 145)`  | `#66cd5b`   |
| `Info`            | `oklch(0.55 0.20 220)`   | `#0082bb`    | `oklch(0.75 0.15 200)`  | `#3ec6d1`   |
| `GlowCyan`        | `oklch(0.65 0.20 220)`   | `#00a2dc`    | `oklch(0.75 0.15 200)`  | `#3ec6d1`   |
| `GlowGreen`       | `oklch(0.70 0.22 145)`   | `#56bc4b`    | `oklch(0.75 0.22 145)`  | `#66cd5b`   |
| `GlowViolet`      | `oklch(0.60 0.24 280)`   | `#6b60ff`    | `oklch(0.65 0.24 280)`  | `#7971ff`   |

## Notes

- The hex values in the table are approximations for human eyes; the
  authoritative values land in each colorset's `Contents.json` as Display P3
  components (red/green/blue floats in `[0, 1]`).
- `Success` and `Info` are deliberate semantic aliases of `VoltGreen` and
  `PrimaryCyan`. They exist as separate colorsets so view code can read
  intent (`.token(.success)` for status pills) without coupling to the brand
  hue.
- `Glow*` tokens are decorative — drawn through `.shadow()` or as halo fills
  behind brand surfaces (`BrandLogo`, glass-tinted CTAs). They never appear
  as foreground text.
- Display P3 was chosen over sRGB because the ExpresSync palette pushes into
  the cyan corner of the gamut where P3 has measurable headroom on iPhone 12+
  hardware; rendering them in sRGB visibly desaturates the brand on those
  panels.
