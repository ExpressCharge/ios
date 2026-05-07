//
//  PublicIdView.swift
//  ExpresScan
//
//  Renders an 8-char public ID as two stacked rows of 4 monospaced
//  characters, with letters in green and digits in blue. Mirrors the
//  web `PublicIdDisplay` so the same code reads identically on the
//  printed sticker, the iOS hero, and the admin web watermark.
//
//  Display-only — no tap target. The popover-style QR affordance is
//  admin-only (web). On iOS the public ID is a passive identity
//  watermark on charger cards and the user's own profile screen.
//

import SwiftUI

public struct PublicIdView: View {

    public enum Size {
        case small
        case regular
        case large

        fileprivate var fontSize: CGFloat {
            switch self {
            case .small: return 11
            case .regular: return 14
            case .large: return 22
            }
        }

        fileprivate var rowSpacing: CGFloat {
            switch self {
            case .small: return 1
            case .regular: return 2
            case .large: return 4
            }
        }

        fileprivate var charSpacing: CGFloat {
            switch self {
            case .small: return 1.5
            case .regular: return 2.5
            case .large: return 4
            }
        }
    }

    let publicId: String
    let size: Size

    public init(publicId: String, size: Size = .regular) {
        self.publicId = publicId
        self.size = size
    }

    public var body: some View {
        let chars = Array(publicId)
        let mid = min(chars.count / 2, 4)
        let top = Array(chars.prefix(mid))
        let bot = Array(chars.dropFirst(mid).prefix(4))

        VStack(alignment: .center, spacing: size.rowSpacing) {
            row(top)
            row(bot)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Public ID \(publicId.prefix(4))-\(publicId.suffix(4))")
    }

    @ViewBuilder
    private func row(_ chars: [Character]) -> some View {
        HStack(spacing: size.charSpacing) {
            ForEach(0..<chars.count, id: \.self) { i in
                Text(String(chars[i]))
                    .font(.system(size: size.fontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color(for: chars[i]))
                    .tracking(2)
            }
        }
    }

    private func color(for ch: Character) -> Color {
        // Digits 2-9 (the alphabet excludes 0/1) → blue.
        // Letters → green.
        ch.isNumber ? Color.blue : Color.green
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        PublicIdView(publicId: "ABCD2345", size: .small)
        PublicIdView(publicId: "ABCD2345", size: .regular)
        PublicIdView(publicId: "ABCD2345", size: .large)
    }
    .padding()
    .background(Color.black)
}
#endif
