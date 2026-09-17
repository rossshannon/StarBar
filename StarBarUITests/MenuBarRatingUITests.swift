//
//  MenuBarRatingUITests.swift
//  StarBarUITests
//
//  Clicks and drags the real menu bar stars. The app runs with -UITesting YES, so it shows
//  the stars as if a song is playing and never talks to Music. Results are read from the
//  status item's accessibility value, such as "3½ stars".
//
//  The test runner needs permission to control the Mac (Privacy & Security > Accessibility),
//  and it moves the real mouse.
//

import XCTest

final class MenuBarRatingUITests: XCTestCase {

    private var app: XCUIApplication!
    private var statusItem: XCUIElement!

    /// Width of the stars image: five 16pt stars, the heart and seven 4pt gaps
    private let imageWidth: CGFloat = 124

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "YES", "-allowHalfStar", "YES", "-isFirstLaunch", "NO"]
        app.launch()

        statusItem = app.statusItems["Music Rating"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "No status item. App hierarchy:\n\(app.debugDescription)")
        waitForValue("No rating")
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Clicks

    func testClickEachStar() throws {
        for (index, expected) in ["1 star", "2 stars", "3 stars", "4 stars", "5 stars"].enumerated() {
            click(atImageX: CGFloat(16 + 20 * index))
            waitForValue(expected)
        }
    }

    func testClickLeftHalfOfStarGivesHalfStar() throws {
        click(atImageX: 47)
        waitForValue("2½ stars")
    }

    func testClickGapBetweenStars() throws {
        // The gap between stars 3 and 4 spans x = 60 ... 64 and is split at 62
        click(atImageX: 61)
        waitForValue("3 stars")
        click(atImageX: 63)
        waitForValue("3½ stars")
    }

    func testClickLeftOfStarsClearsRating() throws {
        click(atImageX: 56)
        waitForValue("3 stars")
        click(atImageX: 1)
        waitForValue("No rating")
    }

    func testClickHeartTogglesFavourite() throws {
        click(atImageX: 97)
        waitForValue("5 stars")
        click(atImageX: 116)
        waitForValue("5 stars, favourite")
        click(atImageX: 116)
        waitForValue("5 stars")
    }

    // MARK: - Drags

    /// On macOS 27 the app gets one click when the mouse goes down; the rating must come
    /// from where the mouse is released.
    func testDragRightSavesRatingAtRelease() throws {
        drag(fromImageX: 12, toImageX: 97)
        waitForValue("5 stars")
    }

    func testDragLeftToHalfStar() throws {
        drag(fromImageX: 97, toImageX: 43)
        waitForValue("2½ stars")
    }

    // MARK: - Helpers

    /// Screen coordinate at `x` inside the stars image, which the button centres.
    private func coordinate(atImageX x: CGFloat) -> XCUICoordinate {
        let frame = statusItem.frame
        let leftMargin = (frame.width - imageWidth) / 2
        return statusItem
            .coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: leftMargin + x, dy: frame.height / 2))
    }

    private func click(atImageX x: CGFloat) {
        coordinate(atImageX: x).click()
    }

    private func drag(fromImageX startX: CGFloat, toImageX endX: CGFloat) {
        coordinate(atImageX: startX).click(forDuration: 0.3, thenDragTo: coordinate(atImageX: endX))
    }

    private func waitForValue(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: statusItem)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "Expected \"\(expected)\", found \"\(statusItem.value as? String ?? "nil")\"", file: file, line: line)
    }

}
