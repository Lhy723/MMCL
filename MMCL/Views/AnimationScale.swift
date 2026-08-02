import SwiftUI

extension Animation {
    /// A shared spring used by MMCL's state-driven transitions.
    ///
    /// A scale of zero is an explicit request to disable animation rather than
    /// creating a zero-duration spring, which can still produce an unnecessary
    /// transaction and an abrupt visual update.
    static func mmclSpring(response: Double = 0.35, dampingFraction: Double = 0.85, scale: Double = 1.0) -> Animation? {
        guard scale > 0 else { return nil }
        return .spring(response: response * scale, dampingFraction: dampingFraction)
    }
}
