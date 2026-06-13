import SwiftUI
import AppKit

/// The dropdown content rendered by MenuBarExtra (.window style), styled after
/// GitHub's Primer design language: flat bordered list-groups, Primer palette,
/// state dots and label pills. Adapts to light/dark via the resolved palette.
struct MenuView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var showingSettings = false

    private var p: PrimerPalette { PrimerPalette.resolve(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(showingSettings: $showingSettings)
            Divider().overlay(p.border)

            if showingSettings || !state.hasToken {
                SettingsView(showingSettings: $showingSettings)
                    .frame(maxHeight: 470)
            } else {
                content
            }

            Divider().overlay(p.border)
            FooterBar()
        }
        .frame(width: Theme.width)
        .background(p.bg)
        .environment(\.primer, p)
    }

    @ViewBuilder
    private var content: some View {
        if state.repos.isEmpty {
            EmptyState(
                icon: "folder.badge.plus",
                title: "No repositories yet",
                subtitle: "Open settings to add a repo to track."
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !state.respondedPRs.isEmpty {
                        YourPRsGroup(items: state.respondedPRs)
                    }
                    ForEach(state.results) { repoResult in
                        RepoGroup(repoResult: repoResult)
                    }
                }
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 480)
        }
    }
}

// MARK: - Header

private struct HeaderBar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.primer) private var p
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(spacing: 8) {
            LogoMark()
            Text("PR Bar")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(p.fg)

            if state.reviewRequestedTotal > 0 {
                CounterPill(count: state.reviewRequestedTotal, text: "to review", tint: p.accent)
            }
            if !state.respondedPRs.isEmpty {
                CounterPill(count: state.respondedPRs.count, text: "responded", tint: p.success)
            }

            Spacer(minLength: 4)

            if state.isRefreshing {
                ProgressView().controlSize(.small).frame(width: 28, height: 28)
            } else {
                PrimerIconButton(symbol: "arrow.clockwise", help: "Refresh now") {
                    Task { await state.refresh() }
                }
            }
            PrimerIconButton(
                symbol: showingSettings ? "chevron.backward" : "gearshape",
                help: showingSettings ? "Back" : "Settings"
            ) {
                withAnimation(.easeInOut(duration: 0.18)) { showingSettings.toggle() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(p.canvas)
    }
}

private struct LogoMark: View {
    @Environment(\.primer) private var p
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(p.fg)
            .frame(width: 20, height: 20)
            .overlay(
                Image(systemName: "checklist")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(p.bg)
            )
    }
}

/// A Primer "Counter"-style bordered pill.
private struct CounterPill: View {
    @Environment(\.primer) private var p
    let count: Int
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(p.muted)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(p.bg, in: Capsule())
        .overlay(Capsule().strokeBorder(p.border, lineWidth: 1))
    }
}

// MARK: - Groups

private struct RepoGroup: View {
    @EnvironmentObject var state: AppState
    @Environment(\.primer) private var p
    let repoResult: RepoPRs

    private var collapsed: Bool { state.isCollapsed(repoResult.repo) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupHeader(
                icon: "shippingbox.fill",
                title: repoResult.repo.slug,
                reviewCount: repoResult.reviewRequestedCount,
                trailingText: collapsed && repoResult.error == nil ? "\(repoResult.pullRequests.count) open" : nil,
                collapsed: collapsed
            ) {
                withAnimation(.easeInOut(duration: 0.18)) { state.toggleCollapsed(repoResult.repo) }
            }

            if !collapsed {
                if let error = repoResult.error {
                    InlineNote(text: error, symbol: "exclamationmark.triangle.fill", tint: p.danger)
                } else if repoResult.pullRequests.isEmpty {
                    InlineNote(text: "No open pull requests", symbol: "checkmark.circle", tint: p.muted)
                } else {
                    ListGroup {
                        ForEach(Array(repoResult.pullRequests.enumerated()), id: \.element.id) { i, pr in
                            if i > 0 { RowDivider() }
                            PRRowButton(url: pr.url) { RepoPRRow(pr: pr) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }
}

private struct YourPRsGroup: View {
    @EnvironmentObject var state: AppState
    @Environment(\.primer) private var p
    let items: [AttentionPR]

    private let sectionID = "__your_prs__"
    private var collapsed: Bool { state.isCollapsed(id: sectionID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupHeader(
                icon: "person.crop.circle",
                title: "Your pull requests",
                reviewCount: 0,
                trailingText: "\(items.count)",
                collapsed: collapsed
            ) {
                withAnimation(.easeInOut(duration: 0.18)) { state.toggleCollapsed(id: sectionID) }
            }

            if !collapsed {
                ListGroup {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { RowDivider() }
                        PRRowButton(url: item.pr.url) { MyPRRow(item: item) }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }
}

/// A collapsible section header in Primer's bold/muted style.
private struct GroupHeader: View {
    @Environment(\.primer) private var p
    let icon: String
    let title: String
    var reviewCount: Int = 0
    var trailingText: String? = nil
    let collapsed: Bool
    let toggle: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(p.muted)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(p.muted)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(hovering ? p.accent : p.fg)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if reviewCount > 0 {
                    LabelPill(text: "\(reviewCount) for you", color: p.accent)
                }
                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: 11))
                        .foregroundStyle(p.muted)
                        .monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A bordered, rounded Primer list-group container.
private struct ListGroup<Content: View>: View {
    @Environment(\.primer) private var p
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(p.bg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(p.border, lineWidth: 1)
            )
    }
}

private struct RowDivider: View {
    @Environment(\.primer) private var p
    var body: some View { Rectangle().fill(p.border).frame(height: 1) }
}

/// One list-group row, tappable, with a Primer hover fill.
private struct PRRowButton<Content: View>: View {
    @Environment(\.primer) private var p
    let url: String
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        Button { open(url) } label: {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hovering ? p.canvas : p.bg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Rows

private struct RepoPRRow: View {
    @Environment(\.primer) private var p
    let pr: PullRequest

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            StateIcon(status: pr.checkStatus).padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(pr.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(p.fg)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("#\(pr.number)")
                        .font(.system(size: 12))
                        .foregroundStyle(p.muted)
                        .monospacedDigit()
                    Text("@\(pr.author)")
                        .font(.system(size: 12))
                        .foregroundStyle(p.muted)
                    if pr.reviewRequestedFromMe {
                        LabelPill(text: "review requested", color: p.accent)
                    } else if let label = pr.reviewState.label {
                        LabelPill(text: label, color: pr.reviewState.color(p),
                                  leadingSymbol: pr.reviewState == .approved ? "checkmark" : nil)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct MyPRRow: View {
    @Environment(\.primer) private var p
    let item: AttentionPR
    private var pr: PullRequest { item.pr }
    private var approved: Bool { pr.reviewState == .approved }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: approved ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                .font(.system(size: 12))
                .foregroundStyle(approved ? p.success : p.danger)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(pr.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(p.fg)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("#\(pr.number)")
                        .font(.system(size: 12))
                        .foregroundStyle(p.muted)
                        .monospacedDigit()
                    Text(item.repo.slug)
                        .font(.system(size: 12))
                        .foregroundStyle(p.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    LabelPill(text: approved ? "approved" : "changes requested",
                              color: approved ? p.success : p.danger,
                              leadingSymbol: approved ? "checkmark" : nil)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// CI status dot, GitHub-style filled circle; pulses while running.
private struct StateIcon: View {
    @Environment(\.primer) private var p
    let status: CheckStatus
    var body: some View {
        Image(systemName: status == .none ? "circle" : "circle.fill")
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(status.color(p))
            .symbolEffect(.pulse, options: .repeating, isActive: status == .pending)
            .help(status.help)
            .frame(width: 14, alignment: .center)
    }
}

/// A GitHub Label: colored text in a translucent rounded pill with a thin border.
private struct LabelPill: View {
    let text: String
    let color: Color
    var leadingSymbol: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let leadingSymbol {
                Image(systemName: leadingSymbol).font(.system(size: 8, weight: .bold))
            }
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(color.opacity(0.13), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Chrome

/// A Primer "IconButton" — bordered square with subtle hover.
private struct PrimerIconButton: View {
    @Environment(\.primer) private var p
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(p.muted)
                .frame(width: 28, height: 28)
                .background(hovering ? p.canvas : p.bg)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(p.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct EmptyState: View {
    @Environment(\.primer) private var p
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(p.muted)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.fg)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(p.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .padding(.horizontal, 20)
    }
}

private struct InlineNote: View {
    @Environment(\.primer) private var p
    let text: String
    let symbol: String
    let tint: Color
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11))
            Text(text).font(.system(size: 12)).lineLimit(2)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.bg)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(p.border, lineWidth: 1))
    }
}

private struct FooterBar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.primer) private var p
    @State private var hovering = false

    var body: some View {
        HStack {
            if let updated = state.lastUpdated {
                Label(updated.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    .labelStyle(CompactLabel())
                    .font(.system(size: 11))
                    .foregroundStyle(p.muted)
            } else {
                Text("Not yet refreshed").font(.system(size: 11)).foregroundStyle(p.muted)
            }
            Spacer()
            Button { NSApplication.shared.terminate(nil) } label: {
                Text("Quit")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hovering ? p.accent : p.muted)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Quit PR Bar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(p.canvas)
    }
}

private struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}

private func open(_ url: String) {
    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
}
