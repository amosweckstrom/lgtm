import XCTest
@testable import LGTM

/// Pins the pure GitHub GraphQL → `[PullRequest]` decode/derivation/sort, with no
/// network. Guards the check-rollup mapping, the ghost/avatar fallbacks, the
/// case-insensitive viewer matching for review-requested-from-me and
/// authored-by-me, the pending-review-request flag, the most-recent
/// review-requested timestamp, the pin-on-top stable sort, and the two decode
/// failure paths.
final class GitHubDecodeTests: XCTestCase {

    // MARK: - Fixture builders

    /// Build a single PR node dictionary shaped like GitHub's GraphQL response.
    private func node(
        id: String = "PR_1",
        number: Int = 1,
        title: String = "Title",
        url: String = "https://example.com/pr/1",
        author: [String: Any]? = ["login": "octocat", "avatarUrl": "https://avatars/octocat"],
        reviewDecision: String? = nil,
        rollupState: String? = nil,
        includeRollup: Bool = true,
        requestedLogins: [String] = [],
        timeline: [(login: String, createdAt: String)] = []
    ) -> [String: Any] {
        var n: [String: Any] = [
            "id": id,
            "number": number,
            "title": title,
            "url": url
        ]
        if let author { n["author"] = author }
        if let reviewDecision { n["reviewDecision"] = reviewDecision }

        // commits.last.commit.statusCheckRollup.state
        var rollup: [String: Any]? = nil
        if includeRollup {
            if let rollupState {
                rollup = ["state": rollupState]
            } else {
                rollup = nil
            }
        }
        let commitNode: [String: Any] = ["commit": ["statusCheckRollup": rollup as Any]]
        n["commits"] = ["nodes": [commitNode]]

        // reviewRequests.nodes[].requestedReviewer.login
        let requestNodes: [[String: Any]] = requestedLogins.map {
            ["requestedReviewer": ["__typename": "User", "login": $0]]
        }
        n["reviewRequests"] = ["nodes": requestNodes]

        // timelineItems.nodes[] (REVIEW_REQUESTED_EVENT)
        let timelineNodes: [[String: Any]] = timeline.map {
            [
                "__typename": "ReviewRequestedEvent",
                "createdAt": $0.createdAt,
                "requestedReviewer": ["__typename": "User", "login": $0.login]
            ]
        }
        n["timelineItems"] = ["nodes": timelineNodes]

        return n
    }

    /// Wrap PR nodes in the top-level GraphQL envelope.
    private func envelope(_ nodes: [[String: Any]]) -> [String: Any] {
        ["data": ["repository": ["pullRequests": ["nodes": nodes]]]]
    }

    // MARK: - statusCheckRollup mapping

    func testRollupMapping() throws {
        let cases: [(String?, CheckStatus)] = [
            ("SUCCESS", .success),
            ("FAILURE", .failure),
            ("ERROR", .failure),
            ("PENDING", .pending),
            ("EXPECTED", .pending),
            ("WHATEVER", .none)
        ]
        for (state, expected) in cases {
            let json = envelope([node(rollupState: state)])
            let prs = try GitHubClient.decodePullRequests(from: json, viewerLogin: "me")
            XCTAssertEqual(prs.first?.checkStatus, expected, "rollup \(state ?? "nil")")
        }
    }

    func testMissingRollupMapsToNone() throws {
        // No statusCheckRollup object at all.
        let json = envelope([node(includeRollup: false)])
        let prs = try GitHubClient.decodePullRequests(from: json, viewerLogin: "me")
        XCTAssertEqual(prs.first?.checkStatus, CheckStatus.none)
    }

    // MARK: - author / avatar fallbacks

    func testMissingAuthorBecomesGhost() throws {
        let json = envelope([node(author: nil)])
        let prs = try GitHubClient.decodePullRequests(from: json, viewerLogin: "me")
        XCTAssertEqual(prs.first?.author, "ghost")
        XCTAssertNil(prs.first?.authorAvatarURL)
    }

    func testMissingAvatarURLIsNil() throws {
        let json = envelope([node(author: ["login": "octocat"])])
        let prs = try GitHubClient.decodePullRequests(from: json, viewerLogin: "me")
        XCTAssertEqual(prs.first?.author, "octocat")
        XCTAssertNil(prs.first?.authorAvatarURL)
    }

    // MARK: - reviewRequestedFromMe (case-insensitive)

    func testReviewRequestedFromMeIsCaseInsensitive() throws {
        let json = envelope([node(requestedLogins: ["ME"])])
        let prs = try GitHubClient.decodePullRequests(from: json, viewerLogin: "me")
        XCTAssertTrue(prs.first?.reviewRequestedFromMe ?? false)
    }

    func testReviewRequestedFromMeFalseWhenOnlyOthers() throws {
        let json = envelope([node(requestedLogins: ["someone", "another"])])
        let prs = try GitHubClient.decodePullRequests(from: json, viewerLogin: "me")
        XCTAssertFalse(prs.first?.reviewRequestedFromMe ?? true)
    }

    // MARK: - hasPendingReviewRequest

    func testHasPendingReviewRequestTracksRequestNodes() throws {
        let withRequests = try GitHubClient.decodePullRequests(
            from: envelope([node(requestedLogins: ["whoever"])]), viewerLogin: "me")
        XCTAssertTrue(withRequests.first?.hasPendingReviewRequest ?? false)

        let withoutRequests = try GitHubClient.decodePullRequests(
            from: envelope([node(requestedLogins: [])]), viewerLogin: "me")
        XCTAssertFalse(withoutRequests.first?.hasPendingReviewRequest ?? true)
    }

    // MARK: - authoredByMe (case-insensitive)

    func testAuthoredByMeIsCaseInsensitive() throws {
        let mine = try GitHubClient.decodePullRequests(
            from: envelope([node(author: ["login": "ME"])]), viewerLogin: "me")
        XCTAssertTrue(mine.first?.authoredByMe ?? false)

        let theirs = try GitHubClient.decodePullRequests(
            from: envelope([node(author: ["login": "someone"])]), viewerLogin: "me")
        XCTAssertFalse(theirs.first?.authoredByMe ?? true)
    }

    // MARK: - reviewRequestedAt (most recent matching event)

    func testReviewRequestedAtPicksMostRecentMatchingEvent() throws {
        let json = envelope([node(timeline: [
            (login: "me", createdAt: "2026-01-01T00:00:00Z"),
            (login: "other", createdAt: "2026-06-01T00:00:00Z"),   // newer but not me — ignored
            (login: "ME", createdAt: "2026-03-01T00:00:00Z")        // most recent matching
        ])])
        let prs = try GitHubClient.decodePullRequests(from: json, viewerLogin: "me")
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(prs.first?.reviewRequestedAt, iso.date(from: "2026-03-01T00:00:00Z"))
    }

    func testReviewRequestedAtNilWhenNoMatchingEvent() throws {
        let json = envelope([node(timeline: [
            (login: "other", createdAt: "2026-06-01T00:00:00Z")
        ])])
        let prs = try GitHubClient.decodePullRequests(from: json, viewerLogin: "me")
        XCTAssertNil(prs.first?.reviewRequestedAt)
    }

    // MARK: - sort: requested-from-me pinned, stable otherwise

    func testRequestedFromMePinnedAboveStablePreservingOrder() throws {
        // API order: A(other) B(me) C(other) D(me) E(other) F(me).
        // Expected: the requested-from-me group (B,D,F) pinned first IN ORIGINAL
        // order, then the rest (A,C,E) in original order. Interleaved with two
        // elements per group on each side of a flip, so a reversed-direction or
        // dropped offset tie-break visibly scrambles within-group order and fails.
        let json = envelope([
            node(id: "A", requestedLogins: ["other"]),
            node(id: "B", requestedLogins: ["me"]),
            node(id: "C", requestedLogins: ["other"]),
            node(id: "D", requestedLogins: ["me"]),
            node(id: "E", requestedLogins: ["other"]),
            node(id: "F", requestedLogins: ["me"])
        ])
        let prs = try GitHubClient.decodePullRequests(from: json, viewerLogin: "me")
        XCTAssertEqual(prs.map(\.id), ["B", "D", "F", "A", "C", "E"])
    }

    func testStableOrderAmongTiedFlags() throws {
        // None are requested-from-me — the offset tie-break must preserve original
        // API order. A reversed tie-break would yield Z,Y,X,W; an unordered
        // collection (e.g. a Set/Dictionary regression) would scramble it.
        let json = envelope([
            node(id: "W", requestedLogins: []),
            node(id: "X", requestedLogins: ["other"]),
            node(id: "Y", requestedLogins: []),
            node(id: "Z", requestedLogins: ["other"])
        ])
        let prs = try GitHubClient.decodePullRequests(from: json, viewerLogin: "me")
        XCTAssertEqual(prs.map(\.id), ["W", "X", "Y", "Z"])
    }

    // MARK: - decode failures

    func testMissingDataThrowsDecoding() {
        XCTAssertThrowsError(
            try GitHubClient.decodePullRequests(from: [:], viewerLogin: "me")
        ) { error in
            guard case GitHubError.decoding(let message) = error else {
                return XCTFail("expected GitHubError.decoding, got \(error)")
            }
            XCTAssertEqual(message, "missing data")
        }
    }

    func testMissingRepositoryPullRequestsThrowsDecoding() {
        // data present, but no repository.pullRequests.nodes.
        let json: [String: Any] = ["data": ["repository": [:]]]
        XCTAssertThrowsError(
            try GitHubClient.decodePullRequests(from: json, viewerLogin: "me")
        ) { error in
            guard case GitHubError.decoding(let message) = error else {
                return XCTFail("expected GitHubError.decoding, got \(error)")
            }
            XCTAssertEqual(message, "missing repository.pullRequests")
        }
    }
}
