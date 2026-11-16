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

}
