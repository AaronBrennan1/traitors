import SwiftUI

/// The card that comes down when you walk somewhere new: where you are, and when.
struct PhaseCurtain: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Palette.gold.opacity(0.10), .clear], center: .center, startRadius: 0, endRadius: 320)
            VStack(spacing: 10) {
                Rectangle().fill(Palette.gold.opacity(0.6)).frame(width: 44, height: 1)
                Text(title.uppercased())
                    .font(.serif(.title, weight: .heavy))
                    .tracking(5)
                    .foregroundStyle(Palette.parchment)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.serif(.headline).italic())
                    .foregroundStyle(Palette.gold)
                Rectangle().fill(Palette.gold.opacity(0.6)).frame(width: 44, height: 1)
            }
            .padding(.horizontal, 24)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
