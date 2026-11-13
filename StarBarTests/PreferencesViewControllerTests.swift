//
//  PreferencesViewControllerTests.swift
//  StarBarTests
//
//  The star labels for the rating shortcuts in Preferences. Needs no Music app.
//

import XCTest
@testable import StarBar

final class PreferencesViewControllerTests: XCTestCase {

    /// The stars are a template image tinted with the label colour, so AppKit recolours
    /// them for light and dark mode. An image baked with a fixed colour would not follow.
    func testStarsLabelFollowsTheLabelColour() throws {
        let stack = PreferencesViewController.starsLabel(count: 3, fontSize: 13)
        let imageView = try XCTUnwrap(stack.arrangedSubviews.first as? NSImageView)

        XCTAssertEqual(try XCTUnwrap(imageView.image).isTemplate, true)
        XCTAssertEqual(imageView.contentTintColor, .labelColor)
        XCTAssertEqual(imageView.accessibilityLabel(), "3 stars")
        XCTAssertEqual((stack.arrangedSubviews.last as? NSTextField)?.stringValue, ": ")
    }

    /// Each label draws as many stars as its shortcut sets, at the label's font size
    func testStarsLabelWidthGrowsWithTheCount() throws {
        var previousWidth: CGFloat = 0
        for count in 1...5 {
            let stack = PreferencesViewController.starsLabel(count: count, fontSize: 13)
            let image = try XCTUnwrap((stack.arrangedSubviews.first as? NSImageView)?.image)
            XCTAssertEqual(image.size.height, 13)
            XCTAssertGreaterThan(image.size.width, previousWidth, "count \(count)")
            previousWidth = image.size.width
        }
    }

    // MARK: - Last.fm status

    private func lastfmStatus(state: LastfmAccount.State = .connected,
                              username: String? = "listener",
                              canConnect: Bool = true,
                              problem: String? = nil,
                              isPaused: Bool = false,
                              waiting: Int = 0,
                              isDryRun: Bool = false) -> String {
        return PreferencesViewController.lastfmStatus(state: state, username: username, canConnect: canConnect, problem: problem, isPaused: isPaused, waiting: waiting, isDryRun: isDryRun)
    }

    private let revokeText = " To remove StarBar's access, go to Applications in your Last.fm settings."

    /// Catches a connected status that forgets who is scrobbling or how to revoke access
    func testLastfmConnectedNamesTheUser() {
        XCTAssertEqual(lastfmStatus(), "Scrobbling as listener." + revokeText, "connected should name the user and say how to revoke")
    }

    func testLastfmDisconnectedOffersToScrobble() {
        XCTAssertEqual(lastfmStatus(state: .disconnected, username: nil),
                       "Scrobble what you play in Music to your Last.fm profile.",
                       "disconnected should say what connecting does")
    }

    /// A build with no key must not invite the user to press a button that can't work
    func testLastfmWithoutAKeySaysItCantConnect() {
        XCTAssertEqual(lastfmStatus(state: .disconnected, username: nil, canConnect: false),
                       "This copy of StarBar was built without a Last.fm key, so it can't connect.",
                       "a build without a key should say it can't connect")
    }

    func testLastfmConnectingWaitsForTheUser() {
        XCTAssertEqual(lastfmStatus(state: .connecting, username: nil),
                       "Waiting for you to allow access on last.fm…",
                       "connecting should say it waits for the user")
    }

    /// The problem left from an earlier attempt belongs to that attempt, not the one under way
    func testLastfmConnectingIgnoresAnOldProblem() {
        XCTAssertEqual(lastfmStatus(state: .connecting, username: nil, problem: "Last.fm couldn't be reached."),
                       "Waiting for you to allow access on last.fm…",
                       "an old problem should not be shown while connecting")
    }

    func testLastfmPausedSaysSo() {
        XCTAssertEqual(lastfmStatus(isPaused: true), "Connected as listener. Scrobbling is paused." + revokeText,
                       "paused should say scrobbling is paused")
    }

    /// Catches "1 plays"
    func testLastfmOnePlayWaitingIsSingular() {
        XCTAssertEqual(lastfmStatus(waiting: 1), "Scrobbling as listener. 1 play waiting to be sent." + revokeText,
                       "one waiting play should be singular")
    }

    func testLastfmSeveralPlaysWaitingArePlural() {
        XCTAssertEqual(lastfmStatus(waiting: 7), "Scrobbling as listener. 7 plays waiting to be sent." + revokeText,
                       "several waiting plays should be plural with the count")
    }

    func testLastfmPausedWithPlaysWaitingSaysBoth() {
        XCTAssertEqual(lastfmStatus(isPaused: true, waiting: 2),
                       "Connected as listener. Scrobbling is paused. 2 plays waiting to be sent." + revokeText,
                       "paused with plays waiting should say both")
    }

    /// A problem is shown first, as Spotify's is, and the sign-in still stands after it
    func testLastfmProblemWhileConnectedComesFirst() {
        XCTAssertEqual(lastfmStatus(problem: "Last.fm couldn't be reached."),
                       "Last.fm couldn't be reached. Scrobbling as listener." + revokeText,
                       "a problem while connected should be shown before the status")
    }

    func testLastfmProblemWhileDisconnectedComesFirst() {
        XCTAssertEqual(lastfmStatus(state: .disconnected, username: nil, problem: "Last.fm said the sign-in is no longer valid."),
                       "Last.fm said the sign-in is no longer valid. Scrobble what you play in Music to your Last.fm profile.",
                       "a problem while disconnected should be shown before the status")
    }

    /// A dry run sends nothing whatever the sign-in says, so it must say so above all else
    func testLastfmDryRunTakesPrecedence() {
        let expected = "Dry run: StarBar logs what it would send to Last.fm and sends nothing."
        XCTAssertEqual(lastfmStatus(isDryRun: true), expected, "dry run while connected")
        XCTAssertEqual(lastfmStatus(state: .disconnected, username: nil, canConnect: false, problem: "Oops.", isPaused: true, waiting: 3, isDryRun: true),
                       expected, "dry run should win over everything else")
        XCTAssertEqual(lastfmStatus(state: .connecting, isDryRun: true), expected, "dry run while connecting")
    }

}
