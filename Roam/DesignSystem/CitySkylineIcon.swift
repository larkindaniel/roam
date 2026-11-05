import SwiftUI

/// A city in a list: a row of buildings of different heights, white in a grey circle, as Apple Maps marks cities.
struct CitySkylineIcon: View {
    var size: CGFloat = 28
    var tint: Color = Color(red: 0.45, green: 0.48, blue: 0.53)

    var body: some View {
        Circle()
            .fill(tint)
            .overlay(Skyline().fill(.white).padding(size * 0.22).offset(y: size * 0.04))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Seven buildings standing on one line, the tallest in the middle with a spire.
private struct Skyline: Shape {
    func path(in rect: CGRect) -> Path {
        // (left edge, width, height) as fractions of the box.
        let buildings: [(CGFloat, CGFloat, CGFloat)] = [
            (0.00, 0.14, 0.42), (0.13, 0.15, 0.62), (0.27, 0.14, 0.48), (0.40, 0.18, 0.86),
            (0.57, 0.14, 0.56), (0.70, 0.16, 0.70), (0.85, 0.15, 0.38),
        ]
        var path = Path()
        for (x, w, h) in buildings {
            path.addRect(CGRect(x: rect.minX + x * rect.width, y: rect.maxY - h * rect.height,
                                width: w * rect.width, height: h * rect.height))
        }
        let spireX = rect.minX + 0.49 * rect.width
        path.addRect(CGRect(x: spireX - rect.width * 0.015, y: rect.minY, width: rect.width * 0.03, height: rect.height * 0.16))
        return path
    }
}
