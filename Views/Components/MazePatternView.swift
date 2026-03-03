import Inject
import SwiftUI

struct MazePatternView: View {
    @ObserveInjection var inject

    var body: some View {
        Canvas { context, size in
            let tileSize: CGFloat = 60
            let cols = Int(ceil(size.width / tileSize)) + 1
            let rows = Int(ceil(size.height / tileSize)) + 1

            for row in 0..<rows {
                for col in 0..<cols {
                    let origin = CGPoint(x: CGFloat(col) * tileSize, y: CGFloat(row) * tileSize)
                    var path = Path()
                    path.move(to: CGPoint(x: origin.x, y: origin.y + 30))
                    path.addLine(to: CGPoint(x: origin.x + 20, y: origin.y + 30))
                    path.addLine(to: CGPoint(x: origin.x + 20, y: origin.y + 10))
                    path.addLine(to: CGPoint(x: origin.x + 40, y: origin.y + 10))
                    path.addLine(to: CGPoint(x: origin.x + 40, y: origin.y + 50))
                    path.addLine(to: CGPoint(x: origin.x + 30, y: origin.y + 50))
                    path.addLine(to: CGPoint(x: origin.x + 30, y: origin.y + 40))
                    path.addLine(to: CGPoint(x: origin.x + 20, y: origin.y + 40))
                    path.addLine(to: CGPoint(x: origin.x + 20, y: origin.y + 60))
                    path.addLine(to: CGPoint(x: origin.x + 60, y: origin.y + 60))
                    path.addLine(to: CGPoint(x: origin.x + 60, y: origin.y + 20))
                    path.addLine(to: CGPoint(x: origin.x + 40, y: origin.y + 20))
                    path.addLine(to: CGPoint(x: origin.x + 40, y: origin.y + 10))
                    path.addLine(to: CGPoint(x: origin.x + 20, y: origin.y + 10))
                    path.addLine(to: CGPoint(x: origin.x + 20, y: origin.y))
                    path.addLine(to: CGPoint(x: origin.x + 30, y: origin.y))
                    path.addLine(to: CGPoint(x: origin.x + 30, y: origin.y + 10))
                    path.addLine(to: CGPoint(x: origin.x, y: origin.y + 10))
                    context.stroke(
                        path,
                        with: .color(.asterionText.opacity(0.025)),
                        lineWidth: 0.5
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .enableInjection()
    }
}
