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

}
