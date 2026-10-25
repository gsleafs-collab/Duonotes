import SwiftUI

/// The classic marbled composition book cover with a white title label.
struct CompositionCover: View {
    static let aspectRatio: CGFloat = PaperMetrics.size.width / PaperMetrics.size.height

    let title: String
    let style: CoverStyle
    /// Gives each notebook its own marble pattern that never changes.
    let seed: UUID

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .leading) {
                MarbleView(ink: style.ink, seed: seed)

                // Cloth tape over the spine.
                Rectangle()
                    .fill(style.ink)
                    .frame(width: size.width * 0.11)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(.white.opacity(0.18)).frame(width: 1)
                    }

                label(width: size.width * 0.66)
                    .position(x: size.width * 0.555, y: size.height * 0.27)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 4, x: 2, y: 3)
    }

    private func label(width: CGFloat) -> some View {
        VStack(spacing: width * 0.04) {
            Text("COMPOSITION BOOK")
                .font(.system(size: width * 0.075, weight: .heavy, design: .serif))
                .tracking(width * 0.006)
            VStack(spacing: width * 0.02) {
                Text(title.isEmpty ? " " : title)
                    .font(.custom("Noteworthy-Bold", size: width * 0.11))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                Rectangle().frame(height: 0.75)
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, width * 0.07)
        .padding(.vertical, width * 0.06)
        .frame(width: width)
        .background(.white, in: RoundedRectangle(cornerRadius: width * 0.05))
        .overlay(RoundedRectangle(cornerRadius: width * 0.05).strokeBorder(.black, lineWidth: 1.5))
    }
}

/// Black and white marbling built from many random blobs.
struct MarbleView: View {
    let ink: Color
    let seed: UUID

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var rng = SeededGenerator(seed: seed)
            let unit = max(size.width / 160, 0.5)
            let count = Int(size.width * size.height / (unit * unit * 55))

            for index in 0..<count {
                let center = CGPoint(x: .random(in: 0...size.width, using: &rng),
                                     y: .random(in: 0...size.height, using: &rng))
                let width = CGFloat.random(in: 2...9, using: &rng) * unit
                let height = CGFloat.random(in: 1...4, using: &rng) * unit
                let angle = CGFloat.random(in: 0...CGFloat.pi, using: &rng)
                let blob = Path(ellipseIn: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
                    .applying(CGAffineTransform(rotationAngle: angle))
                    .applying(CGAffineTransform(translationX: center.x, y: center.y))
                // Mostly dark ink with a few white flecks on top.
                let color: Color = index % 7 == 6 ? .white : ink
                context.fill(blob, with: .color(color))
            }
        }
    }
}

/// A small repeatable random generator (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UUID) {
        // FNV-1a hash of the UUID string, stable across launches.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.uuidString.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        state = hash
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}
