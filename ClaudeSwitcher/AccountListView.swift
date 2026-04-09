import SwiftUI
import Sparkle

struct AccountListView: View {
    @ObservedObject var manager: ClaudeSwapManager
    let updater: SPUUpdater
    @State private var confirmingRemove: SwapAccount?
    @State private var showInfo = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Claude Accounts")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Button {
                    withAnimation { showInfo.toggle() }
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(showInfo ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Info panel
            if showInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How to add accounts:")
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                    Text("""
                    1. Log in to Claude Code
                    2. Click "+ Add Current Account"
                    3. Run /logout in terminal
                    4. Log in with another account
                    5. Click "+ Add Current Account" again

                    Switch between accounts with a single click.
                    """)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08))
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // Account list
            if manager.accounts.isEmpty {
                Text("No accounts saved yet.\nAdd your current account first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 16)
            } else {
                ForEach(manager.accounts) { account in
                    let isActive = account.number == manager.activeAccount?.number
                    AccountRow(
                        account: account,
                        isActive: isActive,
                        onSwitch: {
                            if !isActive { manager.switchToAccount(account.number) }
                        },
                        onRemove: { confirmingRemove = account }
                    )
                }
            }

            // Confirm remove
            if let removing = confirmingRemove {
                HStack {
                    Text("Remove \(removing.shortEmail)?")
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Button("Yes") {
                        manager.removeAccount(removing.number)
                        confirmingRemove = nil
                    }
                    .foregroundColor(.red)
                    .font(.caption.bold())
                    Button("No") { confirmingRemove = nil }
                        .font(.caption.bold())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
            }

            // Error
            if let error = manager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

            // Loading
            if manager.isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Working...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            // Add account button
            Button {
                manager.addCurrentAccount()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                    Text("Add Current Account")
                        .foregroundColor(.green)
                        .font(.callout.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(manager.isLoading)

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            // Check for Updates button (Sparkle)
            CheckForUpdatesButton(updater: updater)

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            // Quit button
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .foregroundColor(.secondary)
                    Text("Quit Claude Switcher")
                        .foregroundColor(.secondary)
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer().frame(height: 8)
        }
    }
}

struct AccountRow: View {
    let account: SwapAccount
    let isActive: Bool
    let onSwitch: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isActive ? .accentColor : .secondary.opacity(0.4))
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 1) {
                Text(account.email)
                    .font(.callout)
                    .foregroundColor(isActive ? .accentColor : .primary)
                    .lineLimit(1)

                if !account.organizationName.isEmpty {
                    Text(account.organizationName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundColor(.secondary.opacity(0.5))
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.1) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
                .padding(.horizontal, 8)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSwitch() }
        .onHover { isHovered = $0 }
    }
}
