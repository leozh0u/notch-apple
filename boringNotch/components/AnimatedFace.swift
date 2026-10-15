// Created by Harsh Vardhan Goswami on 04/08/24.
// Modified for Notch Apple, 15 October 2026. GPL-3.0.
import Defaults
import SwiftUI

struct MinimalFaceFeatures: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Default(.gentleMotion) private var gentleMotion
    @State private var isBlinking = false
    var height: CGFloat = 20
    var width: CGFloat = 30

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<2) { _ in
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: 4, height: isBlinking ? 1.5 : 6)
                    .frame(height: 8)
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
        .task(id: reduceMotion || !gentleMotion) {
            isBlinking = false
            guard !reduceMotion, gentleMotion else { return }
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(4))
                    withAnimation(.easeInOut(duration: 0.1)) { isBlinking = true }
                    try await Task.sleep(for: .milliseconds(160))
                    withAnimation(.easeInOut(duration: 0.1)) { isBlinking = false }
                }
            } catch { isBlinking = false }
        }
    }
}
