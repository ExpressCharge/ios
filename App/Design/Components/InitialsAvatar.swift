//
//  InitialsAvatar.swift
//  ExpresScan
//
//  Circular avatar that derives 1–2 capital letters from a display
//  name. Used by `ActiveSessionCard` to show who is charging.
//

import SwiftUI

struct InitialsAvatar: View {

    let name: String?
    let size: CGFloat
    let tint: Color

    init(
        name: String?,
        size: CGFloat = 40,
        tint: Color = ColorPalette.primaryCyan
    ) {
        self.name = name
        self.size = size
        self.tint = tint
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
            Circle()
                .strokeBorder(tint.opacity(0.55), lineWidth: 1)
            Text(initials)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var initials: String {
        guard let raw = name?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return "?" }
        let parts = raw.split(whereSeparator: { $0.isWhitespace })
        if parts.count == 1 {
            return String(parts[0].prefix(1)).uppercased()
        }
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.last?.prefix(1) ?? ""
        return (first + last).uppercased()
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 16) {
        InitialsAvatar(name: "Vlad Zaharia")
        InitialsAvatar(name: "Alice")
        InitialsAvatar(name: nil)
        InitialsAvatar(name: "x@y.com", size: 56, tint: ColorPalette.voltGreen)
    }
    .padding()
}
#endif
