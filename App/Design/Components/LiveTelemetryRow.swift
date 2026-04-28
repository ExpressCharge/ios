//
//  LiveTelemetryRow.swift
//  ExpresScan
//
//  Wave 6 / Slice J — three-column telemetry row used by the charging
//  hero. Hairline `Divider`s between columns; SwiftUI's `HStack` lays
//  the three columns out at equal width because each `BigStatNumber`
//  applies `.frame(maxWidth: .infinity)`.
//

import SwiftUI

public struct LiveTelemetryRow: View {

    public let kwh: String
    public let kw: String
    public let elapsed: String

    public init(kwh: String, kw: String, elapsed: String) {
        self.kwh = kwh
        self.kw = kw
        self.elapsed = elapsed
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 0) {
            BigStatNumber(value: kwh, label: "kWh")
            Divider().frame(width: 1, height: 48)
            BigStatNumber(value: kw, label: "kW")
            Divider().frame(width: 1, height: 48)
            BigStatNumber(value: elapsed, label: "elapsed")
        }
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.base)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(ColorPalette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(ColorPalette.borderSubtle)
                )
        )
    }
}

#if DEBUG
#Preview {
    LiveTelemetryRow(kwh: "8.2", kw: "11.0", elapsed: "00:24")
        .padding()
}
#endif
