//
//  CopyableValueRow.swift
//  ExpresScan
//
//  Wave 6 / Slice F. `LabeledContent`-style row whose trailing value
//  is monospaced + truncated, plus a copy button. Generalises the
//  hand-rolled device-ID copy pattern previously inlined in
//  `DiagnosticsSheet`.
//
//  Caller owns toast presentation by passing a `onCopy` closure —
//  keeps this component free of presentation state.
//

import SwiftUI
import UIKit

/// `LabeledContent` + monospaced value + `doc.on.doc` copy button.
public struct CopyableValueRow: View {

    private let label: String
    private let value: String?
    private let valueMaxWidth: CGFloat?
    private let onCopy: (String) -> Void

    public init(
        _ label: String,
        value: String?,
        valueMaxWidth: CGFloat? = nil,
        onCopy: @escaping (String) -> Void
    ) {
        self.label = label
        self.value = value
        self.valueMaxWidth = valueMaxWidth
        self.onCopy = onCopy
    }

    public var body: some View {
        HStack {
            Text(label)
            Spacer()
            if let value, !value.isEmpty {
                Text(value)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: valueMaxWidth, alignment: .trailing)
                Button {
                    UIPasteboard.general.string = value
                    onCopy(value)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .accessibilityLabel("Copy \(label)")
                }
                .buttonStyle(.borderless)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }
}
