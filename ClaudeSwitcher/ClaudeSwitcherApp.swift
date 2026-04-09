import SwiftUI

@main
struct ClaudeSwitcherApp: App {
    @StateObject private var manager = ClaudeSwapManager()

    var body: some Scene {
        MenuBarExtra {
            AccountListView(manager: manager)
                .frame(width: 320)
        } label: {
            let email = manager.activeAccount?.email ?? ""
            let short = email.contains("@") ? String(email.prefix(while: { $0 != "@" })) : "Claude"
            Label(short, systemImage: "person.2.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
