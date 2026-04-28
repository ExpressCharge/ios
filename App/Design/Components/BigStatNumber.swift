//
//  BigStatNumber.swift
//  ExpresScan
//
//  Wave 6 / Slice J — display-large numeric readout used by the live
//  telemetry row on `ChargerDetailView` (and earmarked for the future
//  customer dashboard). Big rounded font, animated transitions between
//  consecutive values, with AX5-safe scaling so the column survives a
//  user dialing Dynamic Type all the way up.
//

import SwiftUI

public struct BigStatNumber: View {

    public let value: String
    public let label: String

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }

    public var body: some View {
        VStack(alignment: .center, spacing: Spacing.xs) {
            Text(value)
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

#if DEBUG
#Preview {
    HStack {
        BigStatNumber(value: "8.2", label: "kWh")
        BigStatNumber(value: "11.0", label: "kW")
        BigStatNumber(value: "00:24", label: "elapsed")
    }
    .padding()
}
#endif
