import SwiftUI

/// Alias for SwiftUI's `@State` property wrapper.
/// Recent SDKs also declare `@State` as a macro whose plugin only ships with full Xcode,
/// so building with the Command Line Tools alone fails. The alias bypasses the macro.
typealias ViewState = SwiftUI.State
