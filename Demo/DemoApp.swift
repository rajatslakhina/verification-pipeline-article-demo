import SwiftUI
import ReviewGateKit

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ReviewGateDemoView()
            }
        }
    }
}
