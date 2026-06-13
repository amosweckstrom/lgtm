import SwiftUI

/// Settings / onboarding panel in GitHub Primer style: bold section headers,
/// bordered cards, Primer-styled inputs and buttons.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.primer) private var p
    @Binding var showingSettings: Bool

    @State private var tokenInput = ""
    @State private var newOwner = ""
    @State private var newName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                tokenSection
                reposSection
                optionsSection
            }
            .padding(14)
        }
        .background(p.bg)
    }

    // MARK: Token

    private var tokenSection: some View {
        SettingsSection(title: "GitHub token", icon: "key.fill") {
            if state.hasToken {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(p.success)
                    Text("Connected").font(.system(size: 12, weight: .medium)).foregroundStyle(p.fg)
                    Text("stored in Keychain").font(.system(size: 11)).foregroundStyle(p.muted)
                    Spacer()
                    Button("Remove") { state.clearToken() }
                        .buttonStyle(PrimerButton(role: .danger))
                }
                .padding(11)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Paste a token with read access to the repos you track.")
                        .font(.system(size: 11))
                        .foregroundStyle(p.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        PrimerField { SecureField("ghp_…", text: $tokenInput).onSubmit(saveToken) }
                        Button("Save", action: saveToken)
                            .buttonStyle(PrimerButton(role: .primary))
                            .disabled(tokenIsEmpty)
                    }
                }
                .padding(11)
            }
        }
    }

    private var tokenIsEmpty: Bool { tokenInput.trimmingCharacters(in: .whitespaces).isEmpty }

    private func saveToken() {
        guard !tokenIsEmpty else { return }
        state.setToken(tokenInput)
        tokenInput = ""
    }

    // MARK: Repos

    private var reposSection: some View {
        SettingsSection(title: "Repositories", icon: "shippingbox.fill") {
            VStack(alignment: .leading, spacing: 9) {
                if state.repos.isEmpty {
                    Text("No repos tracked yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(p.muted)
                } else {
                    VStack(spacing: 5) {
                        ForEach(state.repos) { repo in
                            RepoRow(repo: repo) { state.removeRepo(repo) }
                        }
                    }
                }
                HStack(spacing: 6) {
                    PrimerField { TextField("owner", text: $newOwner) }
                    Text("/").foregroundStyle(p.muted)
                    PrimerField { TextField("repo", text: $newName).onSubmit(addRepo) }
                    Button("Add", action: addRepo)
                        .buttonStyle(PrimerButton(role: .primary))
                        .disabled(repoIsEmpty)
                }
            }
            .padding(11)
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

    private var optionsSection: some View {
        SettingsSection(title: "Options", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 11) {
                Toggle(isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                )) {
                    Text("Launch at login").font(.system(size: 12)).foregroundStyle(p.fg)
                }
                .toggleStyle(.switch)
                .tint(p.success)
                .controlSize(.small)

                if let error = state.lastError {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(p.danger)
                            .padding(.top, 1)
                        Text(error)
                            .font(.system(size: 10.5))
                            .foregroundStyle(p.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if state.hasToken {
                    Button("Done") {
                        withAnimation(.easeInOut(duration: 0.18)) { showingSettings = false }
                    }
                    .buttonStyle(PrimerButton(role: .primary))
                }
            }
            .padding(11)
        }
    }
}

// MARK: - Reusable Primer pieces

/// A titled section: bold header above a bordered card.
private struct SettingsSection<Content: View>: View {
    @Environment(\.primer) private var p
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10)).foregroundStyle(p.muted)
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.fg)
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(p.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(p.border, lineWidth: 1)
                )
        }
    }
}

private struct RepoRow: View {
    @Environment(\.primer) private var p
    let repo: TrackedRepo
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "shippingbox").font(.system(size: 10)).foregroundStyle(p.muted)
            Text(repo.slug)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(p.fg)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(hovering ? AnyShapeStyle(p.danger) : AnyShapeStyle(p.muted))
            }
            .buttonStyle(.plain)
            .help("Stop tracking")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(p.bg)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(p.border, lineWidth: 1))
        .onHover { hovering = $0 }
    }
}

/// A Primer-styled text field wrapper: bordered, canvas-default background.
private struct PrimerField<Content: View>: View {
    @Environment(\.primer) private var p
    @ViewBuilder var content: Content
    var body: some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(p.fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(p.bg)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(p.border, lineWidth: 1))
    }
}

/// GitHub Primer button: green primary, red danger, or default bordered.
private struct PrimerButton: ButtonStyle {
    enum Role { case primary, danger, normal }
    @Environment(\.primer) private var p
    @Environment(\.isEnabled) private var isEnabled
    var role: Role = .normal

    func makeBody(configuration: Configuration) -> some View {
        let bg: Color
        let fg: Color
        switch role {
        case .primary: bg = p.success; fg = .white
        case .danger:  bg = p.bg;      fg = p.danger
        case .normal:  bg = p.bg;      fg = p.fg
        }
        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(role == .primary ? .clear : p.border, lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}
