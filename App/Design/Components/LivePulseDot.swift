//
//  LivePulseDot.swift
//  ExpresScan
//
//  Small steady dot with an outward "ping" ring, used to signal live
//  data flow next to live telemetry numbers. Mirrors the web's
//  `bg-emerald-500` + `animate-ping` pattern from `ConnectorCard.tsx`.
//

import SwiftUI

struct LivePulseDot: View {

    let color: Color
    let size: CGFloat

    @State private var animate: Bool = false

    init(color: Color = ColorPalette.voltGreen, size: CGFloat = 8) {
        self.color = color
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.45))
                .frame(width: size, height: size)
                .scaleEffect(animate ? 2.2 : 1.0)
                .opacity(animate ? 0.0 : 0.7)
                .animation(
                    .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                    value: animate
                )
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 2.4, height: size * 2.4)
        .accessibilityHidden(true)
        .onAppear { animate = true }
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 24) {
        LivePulseDot()
        LivePulseDot(color: .blue, size: 10)
    }
    .padding()
}
#endif
