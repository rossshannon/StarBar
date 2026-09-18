//
//  SVGPathTests.swift
//  StarBarTests
//
//  Reading SVG path data. No Music app needed.
//

import XCTest
@testable import StarBar

final class SVGPathTests: XCTestCase {

    private func bounds(_ data: String) -> NSRect {
        return SVGPath.path(fromPathData: data).bounds
    }

    // MARK: - The commands the artwork uses

    func testAbsoluteMoveAndLine() {
        XCTAssertEqual(bounds("M10,10 L30,50"), NSRect(x: 10, y: 10, width: 20, height: 40))
    }

    func testRelativeLine() {
        XCTAssertEqual(bounds("M10,10 l20,40"), NSRect(x: 10, y: 10, width: 20, height: 40))
    }

    func testVerticalAndHorizontalShorthands() {
        // The note's data leans on `v` in particular
        XCTAssertEqual(bounds("M0,0 v100 h50"), NSRect(x: 0, y: 0, width: 50, height: 100))
        XCTAssertEqual(bounds("M0,0 V100 H50"), NSRect(x: 0, y: 0, width: 50, height: 100))
    }

    func testCloseReturnsToTheStartOfTheSubpath() {
        // After z, a relative move continues from the subpath start, not from the last point
        let path = SVGPath.path(fromPathData: "M10,10 L50,10 z l0,20")

        XCTAssertEqual(path.bounds, NSRect(x: 10, y: 10, width: 40, height: 20))
    }

    func testCubicCurvePassesThroughItsEndPoint() {
        let path = SVGPath.path(fromPathData: "M0,0 C0,50 100,50 100,0")

        XCTAssertEqual(path.bounds.minX, 0, accuracy: 0.001)
        XCTAssertEqual(path.bounds.maxX, 100, accuracy: 0.001)
    }

    func testRepeatedCoordinatesReuseTheLastCommand() {
        // SVG lets one command letter be followed by several sets of numbers
        XCTAssertEqual(bounds("M0,0 L10,0 20,0 30,0"), NSRect(x: 0, y: 0, width: 30, height: 0))
    }

    func testASecondPairAfterAMoveIsALine() {
        XCTAssertEqual(bounds("M0,0 10,10"), NSRect(x: 0, y: 0, width: 10, height: 10))
    }

    // MARK: - Number scanning

    func testNumbersRunTogetherBySign() {
        // "10-20" is two numbers, not one
        XCTAssertEqual(bounds("M0,0 L10-20"), NSRect(x: 0, y: -20, width: 10, height: 20))
    }

    func testDecimalsRunTogetherByPoint() {
        // "1.5.5" is 1.5 then 0.5
        let path = SVGPath.path(fromPathData: "M0,0 L1.5.5")

        XCTAssertEqual(path.bounds.maxX, 1.5, accuracy: 0.001)
        XCTAssertEqual(path.bounds.maxY, 0.5, accuracy: 0.001)
    }

    func testEmptyDataGivesAnEmptyPath() {
        XCTAssertEqual(SVGPath.path(fromPathData: "").elementCount, 0)
    }

    func testACloseFollowedByLooseNumbersTerminates() {
        // `z` consumes nothing, so an implicit repeat of it used to spin forever, appending a
        // close element each time. If this regresses the test hangs rather than failing.
        let expectation = XCTestExpectation(description: "the parse finished")
        DispatchQueue.global().async {
            _ = SVGPath.path(fromPathData: "M0,0 L10,10 z 5")
            _ = SVGPath.path(fromPathData: "M0,0 z z z")
            _ = SVGPath.path(fromPathData: "z 1 2 3")
            expectation.fulfill()
        }

        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
                       "the parser did not terminate")
    }

    func testAnExplicitCloseStillWorks() {
        // The termination guard must not break the ordinary case
        let path = SVGPath.path(fromPathData: "M10,10 L50,10 L50,50 z")

        XCTAssertEqual(path.bounds, NSRect(x: 10, y: 10, width: 40, height: 40))
    }

    // MARK: - Exponent notation, which SVG exporters emit

    func testAnExponentIsReadAsOneNumber() {
        // "1e2" is 100, not 1 followed by an unknown command that ends the parse
        XCTAssertEqual(bounds("M0,0 L1e2,0"), NSRect(x: 0, y: 0, width: 100, height: 0))
    }

    func testANegativeExponentIsReadAsOneNumber() {
        let path = SVGPath.path(fromPathData: "M0,0 L1e-2,0")

        XCTAssertEqual(path.bounds.maxX, 0.01, accuracy: 0.0001)
    }

    func testALetterThatIsNotAnExponentIsStillACommand() {
        // "10 h5" must not swallow the h as an exponent
        XCTAssertEqual(bounds("M0,0 V10 h5"), NSRect(x: 0, y: 0, width: 5, height: 10))
    }

    func testAnUnsupportedCommandStopsRatherThanGuessing() {
        // Arcs aren't handled; better to stop than to draw the wrong shape
        let path = SVGPath.path(fromPathData: "M0,0 L10,10 A5,5 0 0 1 20,20")

        XCTAssertEqual(path.bounds, NSRect(x: 0, y: 0, width: 10, height: 10))
    }

    // MARK: - The Apple Music icon

    func testTheAppleMusicIconParses() {
        let outline = AppleMusicGlyph.outline

        XCTAssertGreaterThan(outline.elementCount, 40, "the rounded square and the note inside it")
        XCTAssertFalse(outline.isEmpty)
    }

    func testTheIconIsSquare() {
        // The icon is the rounded square, not the note on its own, so it should be square.
        // Catches a parse that silently dropped one of the two subpaths.
        let bounds = AppleMusicGlyph.outline.bounds

        XCTAssertEqual(bounds.width, bounds.height, accuracy: 1.0)
        XCTAssertGreaterThan(bounds.width, 0)
    }

    func testTheNoteIsKnockedOutOfTheSquare() {
        // Even-odd is what cuts the note out. Without it the button is a solid block, which
        // is a quiet failure: it still draws, it just says nothing.
        let size: CGFloat = 64
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.black.setFill()
        AppleMusicGlyph().draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        image.unlockFocus()

        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else {
            return XCTFail("could not read the drawn icon")
        }

        var opaque = 0
        var total = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                total += 1
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { opaque += 1 }
            }
        }

        // A solid rounded square covers about 95% of its box; the note takes a good bite out
        // of that.Measure the fraction rather than one pixel, which depends on where the stems fall.
        let covered = Double(opaque) / Double(total)
        XCTAssertGreaterThan(covered, 0.3, "the square itself should be drawn")
        XCTAssertLessThan(covered, 0.8, "the note should be knocked out of it")
    }

    func testTheIconStaysInsideItsBox() {
        // Measured on the geometry, not on a drawn image: an image clips whatever overflows,
        // so counting its pixels would pass for an icon that spilled over the plus beside it.
        let box = NSRect(x: 7, y: 3, width: 16, height: 16)
        let bounds = AppleMusicGlyph.outline.bounds
        let inset = box.insetBy(dx: box.width * AppleMusicGlyph.inset, dy: box.height * AppleMusicGlyph.inset)
        let scale = min(inset.width / bounds.width, inset.height / bounds.height)

        let drawnSize = NSSize(width: bounds.width * scale, height: bounds.height * scale)
        let drawn = NSRect(x: inset.midX - drawnSize.width / 2, y: inset.midY - drawnSize.height / 2,
                           width: drawnSize.width, height: drawnSize.height)

        XCTAssertTrue(box.contains(drawn), "\(drawn) is not inside \(box)")
    }

    func testTheIconIsActuallyDrawn() {
        // The companion to the above: inside the box, but not empty
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.black.setFill()
        AppleMusicGlyph().draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
        image.unlockFocus()

        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else {
            return XCTFail("could not read the drawn icon")
        }
        var drawn = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                drawn += 1
            }
        }
        XCTAssertGreaterThan(drawn, 0)
    }

}
