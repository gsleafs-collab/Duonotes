import SwiftUI

/// The classic marbled composition book cover with a white title label.
struct CompositionCover: View {
    /// Shape of the small covers on the bookshelf.
    static let aspectRatio: CGFloat = 0.72

    let title: String
    let ink: Color
    /// Gives each notebook its own marble pattern that never changes.
    let seed: UUID
    /// Fills the screen edge to edge with no rounded corners or shadow.
    var fullBleed = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let spine = min(size.width * 0.11, 64)
            let labelWidth = min((size.width - spine) * 0.74, size.height * 0.5)
            ZStack(alignment: .topLeading) {
                MarbleView(ink: ink, seed: seed)

                // Cloth tape over the spine.
                Rectangle()
                    .fill(ink)
                    .frame(width: spine, height: size.height)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(.white.opacity(0.18)).frame(width: 1)
                    }

                label(width: labelWidth)
                    .position(x: spine + (size.width - spine) / 2, y: size.height * 0.28)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: fullBleed ? 0 : 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(fullBleed ? 0 : 0.35), lineWidth: 1))
        .shadow(color: .black.opacity(fullBleed ? 0 : 0.35), radius: 4, x: 2, y: 3)
        .environment(\.colorScheme, .light)
    }

    private func label(width: CGFloat) -> some View {
        VStack(spacing: width * 0.04) {
            Text("COMPOSITION BOOK")
                .font(.system(size: width * 0.075, weight: .heavy, design: .serif))
                .tracking(width * 0.006)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            VStack(spacing: width * 0.02) {
                Text(title.isEmpty ? " " : title)
                    .font(.custom("Noteworthy-Bold", size: width * 0.11))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                Rectangle().frame(height: max(0.75, width * 0.004))
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, width * 0.07)
        .padding(.vertical, width * 0.06)
        .frame(width: width)
        .background(.white, in: RoundedRectangle(cornerRadius: width * 0.05))
        .overlay(RoundedRectangle(cornerRadius: width * 0.05).strokeBorder(.black, lineWidth: max(1.5, width * 0.008)))
        .shadow(color: .black.opacity(0.3), radius: width * 0.02, y: width * 0.015)
    }
}

/// Black and white marbling built from many overlapping random blobs.
struct MarbleView: View {
    let ink: Color
    let seed: UUID

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var rng = SeededGenerator(seed: seed)
            let unit = max(min(size.width, size.height) / 150, 0.4)
            let count = min(Int(size.width * size.height / (unit * unit * 9)), 12_000)

            for index in 0..<count {
                let center = CGPoint(x: CGFloat.random(in: 0...size.width, using: &rng),
                                     y: CGFloat.random(in: 0...size.height, using: &rng))
                let width = CGFloat.random(in: 2...11, using: &rng) * unit
                let height = CGFloat.random(in: 1...5, using: &rng) * unit
                let angle = CGFloat.random(in: 0...CGFloat.pi, using: &rng)
                let blob = Path(ellipseIn: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
                    .applying(CGAffineTransform(rotationAngle: angle))
                    .applying(CGAffineTransform(translationX: center.x, y: center.y))
                // Two dark blobs for every white one gives the classic marbled look.
                let color: Color = index % 3 == 2 ? .white : ink
                context.fill(blob, with: .color(color))
            }
        }
        .drawingGroup()
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
