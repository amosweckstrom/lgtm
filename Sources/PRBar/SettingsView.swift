import SwiftUI

/// Settings / onboarding panel: token entry, repo management, login toggle.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Binding var showingSettings: Bool

    @State private var tokenInput = ""
    @State private var newOwner = ""
    @State private var newName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                tokenCard
                reposCard
                optionsCard
            }
            .padding(13)
        }
    }

    // MARK: Token

    private var tokenCard: some View {
        SettingsCard(title: "GitHub Token", symbol: "key.fill") {
            if state.hasToken {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                    Text("Connected")
                        .font(.system(size: 12, weight: .medium))
                    Text("stored in Keychain")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove", role: .destructive) { state.clearToken() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.failure)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste a token with read access to the repos you track.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        SecureField("ghp_…", text: $tokenInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .onSubmit(saveToken)
                        Button("Save", action: saveToken)
                            .buttonStyle(BrandButton())
                            .disabled(tokenIsEmpty)
                    }
                }
            }
        }
    }

    private var tokenIsEmpty: Bool {
        tokenInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func saveToken() {
        guard !tokenIsEmpty else { return }
        state.setToken(tokenInput)
        tokenInput = ""
    }

    // MARK: Repos

    private var reposCard: some View {
        SettingsCard(title: "Repositories", symbol: "shippingbox.fill") {
            VStack(alignment: .leading, spacing: 8) {
                if state.repos.isEmpty {
                    Text("No repos tracked yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 5) {
                        ForEach(state.repos) { repo in
                            RepoChip(repo: repo) { state.removeRepo(repo) }
                        }
                    }
                }

                HStack(spacing: 6) {
                    TextField("owner", text: $newOwner)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    Text("/").foregroundStyle(.secondary)
                    TextField("repo", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit(addRepo)
                    Button("Add", action: addRepo)
                        .buttonStyle(BrandButton())
                        .disabled(repoIsEmpty)
                }
            }
        }
    }

    private var repoIsEmpty: Bool {
        newOwner.trimmingCharacters(in: .whitespaces).isEmpty
            || newName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func addRepo() {
        guard !repoIsEmpty else { return }
        state.addRepo(owner: newOwner, name: newName)
        newOwner = ""
        newName = ""
    }

    // MARK: Options

    private var optionsCard: some View {
        SettingsCard(title: "Options", symbol: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                )) {
                    Text("Launch at login")
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .tint(Theme.brand)
                .controlSize(.small)

                if let error = state.lastError {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.failure)
                            .padding(.top, 1)
                        Text(error)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.failure)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if state.hasToken {
                    Button("Done") {
                        withAnimation(.easeInOut(duration: 0.18)) { showingSettings = false }
                    }
                    .buttonStyle(BrandButton())
                }
            }
        }
    }
}

// MARK: - Reusable pieces

/// A titled container that groups related settings with a faint card surface.
private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                    .textCase(.uppercase)
            } icon: {
                Image(systemName: symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.brand)
            }
            .foregroundStyle(.secondary)

            content
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct RepoChip: View {
    let repo: TrackedRepo
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "shippingbox")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(repo.slug)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(hovering ? AnyShapeStyle(Theme.failure) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .help("Stop tracking")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Brand-colored filled button used for primary actions.
private struct BrandButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.brandGradient)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
