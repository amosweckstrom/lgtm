import Foundation

/// Housekeeping for the PR worktrees LGTM creates under `~/.lgtm/worktrees`.
enum Worktrees {
    // MARK: - Path convention (single source of truth)
    //
    // The convention `~/.lgtm/worktrees/<owner>-<name>-pr-<number>` lives ONLY
    // here. Both `AIReview` (Swift URL + the worktree-creating bash) and the
    // `cleanupClosed` script below derive their paths from these members, so the
    // Swift fast-path and the shell that actually creates the directory can't
    // drift apart.

    /// Shell form of the worktrees root (`$HOME/.lgtm/worktrees`).
    static let rootShell = "$HOME/.lgtm/worktrees"

    /// Swift form of the worktrees root (`~/.lgtm/worktrees`).
    static let root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".lgtm/worktrees")

    /// Per-repo slug (`<owner>-<name>`). Doubles as the per-repo hook filename.
    static func slug(for repo: TrackedRepo) -> String {
        "\(repo.owner)-\(repo.name)"
    }

    /// Directory leaf for a PR's worktree: `<owner>-<name>-pr-<number>`.
    static func dirName(for pr: PullRequest, in repo: TrackedRepo) -> String {
        "\(slug(for: repo))-pr-\(pr.number)"
    }

    /// Swift URL of a PR's conventional worktree directory.
    static func path(for pr: PullRequest, in repo: TrackedRepo) -> URL {
        root.appendingPathComponent(dirName(for: pr, in: repo))
    }

    /// Shell form of a PR's conventional worktree directory.
    static func shellPath(for pr: PullRequest, in repo: TrackedRepo) -> String {
        "\(rootShell)/\(dirName(for: pr, in: repo))"
    }

    // MARK: - Cleanup

    /// Remove worktrees whose PR is merged or closed. Runs in the background.
    ///
    /// Safe by design:
    ///  - only ever touches directories under `~/.lgtm/worktrees` — the main
    ///    clone (derived from each worktree's common git dir) is never removed;
    ///  - confirms each PR is actually MERGED/CLOSED via `gh` before removing, so
    ///    a failed or partial refresh can't trigger deletion;
    ///  - uses plain `git worktree remove` (no `--force`): a worktree with
    ///    uncommitted changes is kept, not destroyed. Committed work survives on
    ///    its branch regardless — `git worktree remove` leaves the branch ref.
    static func cleanupClosed() {
        DispatchQueue.global(qos: .utility).async {
            let proc = Process()
            // Login shell so the user's PATH (git, gh — often in Homebrew) resolves
            // even though the app is launched by the GUI with a minimal environment.
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-lc", script]
            do {
                try proc.run()
            } catch {
                NSLog("lgtm: worktree cleanup failed to launch: \(error.localizedDescription)")
            }
        }
    }

    private static let script = #"""
    set -u
    ROOT="\#(rootShell)"
    [ -d "$ROOT" ] || exit 0
    # Glob + parse match `dirName`'s "<owner>-<name>-pr-<number>" leaf: the
    # "*-pr-*" glob finds worktree dirs and "${D##*-pr-}" extracts the number.
    for D in "$ROOT"/*-pr-*; do
      [ -d "$D" ] || continue
      N="${D##*-pr-}"
      case "$N" in (*[!0-9]*) continue ;; esac          # trailing token not a PR number
      git -C "$D" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
      STATE="$(cd "$D" && gh pr view "$N" --json state -q .state 2>/dev/null)"
      [ -n "$STATE" ] || continue                        # state unknown (offline?) — leave it
      case "$STATE" in
        MERGED|CLOSED)
          COMMON="$(git -C "$D" rev-parse --git-common-dir 2>/dev/null)" || continue
          case "$COMMON" in /*) ;; *) COMMON="$D/$COMMON" ;; esac
          MAIN="$(cd "$(dirname "$COMMON")" && pwd)" || continue
          if git -C "$MAIN" worktree remove "$D" 2>/dev/null; then
            echo "[lgtm] removed worktree for $STATE PR #$N: $D"
          else
            echo "[lgtm] kept worktree for PR #$N (uncommitted changes) — remove manually: $D"
          fi
          ;;
      esac
    done
    """#
}
