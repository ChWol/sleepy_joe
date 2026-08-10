import SwiftUI

/// App entry point for the standalone watchOS app.
/// Branded as "Focus" externally to remain discreet.
@main
struct SleepyJoeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
