//
//  AdminErrorDetail.swift
//  ExpresScan
//
//  Phase 1 admin observability — surfaces the raw `APIError`
//  diagnostic beneath the customer-friendly message in error states.
//
//  Customer accounts never see this view (it collapses to `EmptyView`).
//  Admin accounts see a compact monospaced block with the
//  `diagnosticDescription` and a Copy-to-clipboard button — enough to
//  classify a failure (decode vs 5xx vs unmapped) without shipping a
//  debug build.
//
//  DEBUG builds also render it regardless of account, so in-house
//  development against a fresh sim with no signed-in account still
//  surfaces the detail.
//

import Networking
import SwiftUI
import UIKit

/// Compact admin-only block that shows `error.diagnosticDescription`
/// in monospaced caption, with a Copy button. Renders nothing for
/// customer accounts (release builds) — wrap the call site in any
/// SwiftUI hierarchy and trust this view to make the right call.
public struct AdminErrorDetail: View {

    private let error: APIError?
    @Environment(\.isCustomerAccount) private var isCustomerAccount

    public init(error: APIError?) {
        self.error = error
    }

    public var body: some View {
        if let error, shouldRender {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .imageScale(.small)
                    Text("Diagnostic (admin)")
                        .font(.caption2.weight(.semibold))
                    Spacer(minLength: 0)
                    Button {
                        UIPasteboard.general.string = error.diagnosticDescription
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy diagnostic")
                }
                .foregroundStyle(ColorPalette.mutedForeground)

                Text(error.diagnosticDescription)
                    .font(.caption2.monospaced())
                    .foregroundStyle(ColorPalette.foreground)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(ColorPalette.muted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(ColorPalette.borderSubtle, lineWidth: 1)
            )
        }
    }

    /// Show in DEBUG builds always (in-house dev), and in release builds
    /// only when the account is not a customer (admin or no-account-yet).
    private var shouldRender: Bool {
        #if DEBUG
        return true
        #else
        return !isCustomerAccount
        #endif
    }
}
