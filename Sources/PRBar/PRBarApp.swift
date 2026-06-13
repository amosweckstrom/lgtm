import SwiftUI

@main
struct PRBarApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(state)
                .onAppear { state.start() }
        } label: {
            // Icon + review-request count badge. Filled glyph when reviews wait.
            let count = state.reviewRequestedTotal
            if count > 0 {
                Label("\(count)", systemImage: "checklist.checked")
            } else {
                Image(systemName: "checklist")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
