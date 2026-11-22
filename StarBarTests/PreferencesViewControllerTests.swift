//
//  PreferencesViewControllerTests.swift
//  StarBarTests
//
//  The Preferences window: its panes, which one it opens on, how the window fits each
//  pane, and the star labels for the rating shortcuts. Needs no Music app.
//

import XCTest
import MASShortcut
@testable import StarBar

final class PreferencesViewControllerTests: XCTestCase {

    private let suiteName = "PreferencesViewControllerTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func loadedController() -> PreferencesViewController {
        let controller = PreferencesViewController(defaults: defaults)
        _ = controller.view
        return controller
    }

    /// Every view under `view` of type `T`, however deep
    private func descendants<T: NSView>(of view: NSView, _ type: T.Type) -> [T] {
        return view.subviews.flatMap { subview -> [T] in
            ((subview as? T).map { [$0] } ?? []) + descendants(of: subview, type)
        }
    }

    // MARK: - Panes

    /// A toolbar of three panes, each with a label and an icon
    func testThePanesAreGeneralAccountsAndShortcuts() {
        let controller = loadedController()

        XCTAssertEqual(controller.tabStyle, .toolbar)
        XCTAssertEqual(controller.tabViewItems.map(\.label), ["General", "Accounts", "Shortcuts"])
        for item in controller.tabViewItems {
            XCTAssertNotNil(item.image, item.label)
        }
        XCTAssertEqual(controller.selectedPane, .general)
    }

    /// The shortcuts have a pane of their own, and the other panes have none of them
    func testTheShortcutRecordersAreOnlyOnTheShortcutsPane() throws {
        let controller = loadedController()

        var recorders: [PreferencesViewController.Pane: Int] = [:]
        for item in controller.tabViewItems {
            let pane = try XCTUnwrap(PreferencesViewController.pane(of: item))
            let view = try XCTUnwrap(item.viewController?.view)
            recorders[pane] = descendants(of: view, MASShortcutView.self).count
        }
        XCTAssertEqual(recorders, [.general: 0, .accounts: 0, .shortcuts: 10])
    }

    /// The services StarBar signs in to share the Accounts pane, Spotify first
    func testTheAccountsPaneHasSpotifyAndLastfm() throws {
        let controller = loadedController()
        let accounts = try XCTUnwrap(controller.tabViewItems.first { PreferencesViewController.pane(of: $0) == .accounts }?.viewController as? AccountsPreferencesViewController)
        let grid = accounts.gridView

        let spotifyRow = try XCTUnwrap(grid.cell(for: accounts.spotifyTextField)?.row)
        let lastfmRow = try XCTUnwrap(grid.cell(for: accounts.lastfmTextField)?.row)
        XCTAssertLessThan(grid.index(of: spotifyRow), grid.index(of: lastfmRow))
        for view in [accounts.lastfmConnectButton, accounts.lastfmStatusTextField, accounts.lastfmSpotifyCheckboxButton, accounts.lastfmLoveCheckboxButton] {
            XCTAssertNotNil(grid.cell(for: view), "every Last.fm control is in the Accounts grid")
        }
        XCTAssertEqual(lastfmRow.rowAlignment, .firstBaseline, "the label sits on the Connect button's text")
    }

    /// Spotify on other devices is a Spotify setting, so it sits in Spotify's block in
    /// Accounts, above the line before Last.fm (Ross, 2026-11-22), and in no other pane
    func testSpotifyOnOtherDevicesIsUnderSpotify() throws {
        let controller = loadedController()
        let accounts = try XCTUnwrap(controller.tabViewItems.first { PreferencesViewController.pane(of: $0) == .accounts }?.viewController as? AccountsPreferencesViewController)
        let grid = accounts.gridView
        func rowIndex(of view: NSView) throws -> Int {
            return grid.index(of: try XCTUnwrap(grid.cell(for: view)?.row, "\(view) is in the Accounts grid"))
        }
        let line = try rowIndex(of: try XCTUnwrap(descendants(of: grid, NSBox.self).first { $0.boxType == .separator }))

        let checkbox = try rowIndex(of: accounts.spotifyOtherDevicesCheckboxButton)

        XCTAssertGreaterThan(checkbox, try rowIndex(of: accounts.spotifyStatusTextField), "under the sign-in's status")
        XCTAssertLessThan(checkbox, line, "above the line before Last.fm")
        let titles = controller.tabViewItems.compactMap { $0.viewController?.view }.flatMap { descendants(of: $0, NSButton.self) }.map(\.title)
        XCTAssertEqual(titles.filter { $0 == "Show Spotify songs playing on other devices" }.count, 1, "in one pane only")
    }

    /// The Music Video strip's three settings are a block of their own in General, under a line
    func testTheStripSettingsAreABlockOfTheirOwn() throws {
        let controller = loadedController()
        let general = try XCTUnwrap(controller.tabViewItems.first { PreferencesViewController.pane(of: $0) == .general }?.viewController as? GeneralPreferencesViewController)
        let grid = general.gridView
        func rowIndex(of view: NSView) throws -> Int {
            return grid.index(of: try XCTUnwrap(grid.cell(for: view)?.row, "\(view) is in the General grid"))
        }

        let lines = descendants(of: grid, NSBox.self).filter { $0.boxType == .separator }
        XCTAssertEqual(lines.count, 1)
        let line = try rowIndex(of: try XCTUnwrap(lines.first))
        for view in [general.launchAtLoginCheckboxButton, general.halfStarCheckboxButton, general.reminderCheckboxButton] {
            XCTAssertLessThan(try rowIndex(of: view), line, "\(view) is above the line")
        }
        for view in [general.announceRowView, general.announcementStylePopUpButton, general.albumTintPopUpButton] {
            XCTAssertGreaterThan(try rowIndex(of: view), line, "\(view) is below the line")
        }
    }

    /// The window's title is the pane's, as in macOS's own Settings windows
    func testTheTitleFollowsThePane() {
        let controller = loadedController()

        controller.selectedTabViewItemIndex = 2

        XCTAssertEqual(controller.title, "Shortcuts")
    }

    // MARK: - The pane it opens on

    func testItOpensOnThePaneChosenLast() {
        let first = loadedController()
        first.selectedTabViewItemIndex = 2
        XCTAssertEqual(defaults.string(forKey: ApplicationKey.preferencesPane.rawValue), "shortcuts")

        let second = loadedController()

        XCTAssertEqual(second.selectedPane, .shortcuts)
    }

    func testAPaneItDoesNotKnowOpensGeneral() {
        defaults.set("advanced", forKey: ApplicationKey.preferencesPane.rawValue)

        XCTAssertEqual(loadedController().selectedPane, .general)
    }

    // MARK: - Fitting the window

    /// Each pane gets its own height and the widest pane's width, so only the height changes
    /// from one pane to the next
    func testTheWindowFitsEachPane() throws {
        let controller = PreferencesViewController(defaults: defaults)
        let window = NSWindow(contentViewController: controller)
        let contentView = try XCTUnwrap(window.contentView)
        let panes = controller.tabViewItems.compactMap { $0.viewController?.view }
        let widest = try XCTUnwrap(panes.map(\.fittingSize.width).max())

        var heights: [CGFloat] = []
        for index in controller.tabViewItems.indices {
            controller.selectedTabViewItemIndex = index
            controller.fitWindowToSelectedPane(animated: false)

            XCTAssertEqual(contentView.frame.width, widest, accuracy: 0.5, controller.tabViewItems[index].label)
            XCTAssertEqual(contentView.frame.height, panes[index].fittingSize.height, accuracy: 0.5, controller.tabViewItems[index].label)
            heights.append(contentView.frame.height)
        }
        // Ten recorders make the tallest pane
        XCTAssertEqual(heights.max(), heights[2])
        XCTAssertLessThan(heights[1], heights[2])
    }

    /// Each pane's grid sits inside the pane with its margins
    func testEachPaneFitsItsGridAndMargins() throws {
        let controller = loadedController()
        let margin = PreferencesViewController.paneMargin

        for item in controller.tabViewItems {
            let view = try XCTUnwrap(item.viewController?.view)
            let grid = try XCTUnwrap(descendants(of: view, NSGridView.self).first)
            XCTAssertEqual(view.fittingSize.height, grid.fittingSize.height + 2 * margin, accuracy: 0.5, item.label)
            XCTAssertEqual(view.fittingSize.width, grid.fittingSize.width + 2 * margin, accuracy: 0.5, item.label)
        }
    }

    /// The window keeps its title bar and toolbar and its top edge; only the content changes
    func testAFittedWindowKeepsItsTopEdge() {
        let frame = NSRect(x: 100, y: 300, width: 500, height: 400)
        let screen = NSRect(x: 0, y: 25, width: 1440, height: 850)

        let shorter = PreferencesViewController.windowFrame(frame, contentSize: NSSize(width: 500, height: 320), fitting: NSSize(width: 500, height: 200), within: screen)
        XCTAssertEqual(shorter, NSRect(x: 100, y: 420, width: 500, height: 280))

        let taller = PreferencesViewController.windowFrame(frame, contentSize: NSSize(width: 500, height: 320), fitting: NSSize(width: 520, height: 420), within: screen)
        XCTAssertEqual(taller, NSRect(x: 100, y: 200, width: 520, height: 500))
        XCTAssertEqual(taller.maxY, frame.maxY)
    }

    /// A window that would grow past the bottom of the screen moves up to stay on it
    func testAFittedWindowStaysAboveTheBottomOfTheScreen() {
        let frame = NSRect(x: 100, y: 50, width: 500, height: 300)
        let screen = NSRect(x: 0, y: 25, width: 1440, height: 850)

        let fitted = PreferencesViewController.windowFrame(frame, contentSize: NSSize(width: 500, height: 220), fitting: NSSize(width: 500, height: 500), within: screen)

        XCTAssertEqual(fitted, NSRect(x: 100, y: 25, width: 500, height: 580))
    }

    /// One taller than the screen keeps its title bar on it
    func testAFittedWindowTallerThanTheScreenKeepsItsTopOnIt() {
        let frame = NSRect(x: 100, y: 300, width: 500, height: 300)
        let screen = NSRect(x: 0, y: 25, width: 1440, height: 500)

        let fitted = PreferencesViewController.windowFrame(frame, contentSize: NSSize(width: 500, height: 220), fitting: NSSize(width: 500, height: 700), within: screen)

        XCTAssertEqual(fitted.height, 780)
        XCTAssertEqual(fitted.maxY, screen.maxY)
    }

    // MARK: - Star labels

    /// The stars are a template image tinted with the label colour, so AppKit recolours
    /// them for light and dark mode. An image baked with a fixed colour would not follow.
    func testStarsLabelFollowsTheLabelColour() throws {
        let stack = ShortcutsPreferencesViewController.starsLabel(count: 3, fontSize: 13)
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
            let stack = ShortcutsPreferencesViewController.starsLabel(count: count, fontSize: 13)
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
        return AccountsPreferencesViewController.lastfmStatus(state: state, username: username, canConnect: canConnect, problem: problem, isPaused: isPaused, waiting: waiting, isDryRun: isDryRun)
    }

    private let revokeText = " To remove StarBar’s access, go to Applications in your Last.fm settings."

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
                       "This copy of StarBar was built without a Last.fm key, so it can’t connect.",
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
