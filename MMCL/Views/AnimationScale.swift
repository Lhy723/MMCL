import SwiftUI

extension Animation {
    /// macOS 26 style spring animation, scaled by the user's duration preference.
    static func mmclSpring(response: Double = 0.35, dampingFraction: Double = 0.85, scale: Double = 1.0) -> Animation {
        .spring(response: response * scale, dampingFraction: dampingFraction)
    }
}
