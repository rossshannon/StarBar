//
//  StarFlourishTests.swift
//  StarBarTests
//
//  The stars' flourish when a rating is saved, as pure timing and as drawn: which kind a save
//  gets, when the run reaches each star, how each pops and takes its colour, the quiet fold
//  back for a rating lowered, the cross-fade under Reduce Motion, which saves get the
//  five-star finale (`StarFinaleTests` has the finale itself), and that the frames sit exactly
//  over the stars at rest.
//

import XCTest
@testable import StarBar

final class StarFlourishTests: XCTestCase {

    private let starSize = NSSize(width: 16, height: 16)
    private let spacing: CGFloat = 4

    /// A rating saved, with Reduce Motion off unless a test says otherwise. `shown` is what the
    /// stars showed as the gesture ended: the rating before it, unless a drag had moved them.
    private func saved(_ rating: Int, from before: Int, showing shown: Int? = nil,
                       reduceMotion: Bool = false, look: StarFlourish.Look = .afterglow) -> StarFlourish {
        return StarFlourish(saving: rating, from: before, showing: shown ?? before, reduceMotion: reduceMotion, look: look)
    }

    /// Every frame of a flourish at 60 Hz, and one past its end
    private func frames(of flourish: StarFlourish) -> [TimeInterval] {
        return stride(from: 0, through: flourish.duration + 1.0 / 60.0, by: 1.0 / 60.0).map { $0 }
    }

    private func largestScale(of index: Int, in flourish: StarFlourish) -> CGFloat {
        return frames(of: flourish).map { flourish.pose(of: index, at: $0).scale }.max() ?? 0
    }

    // MARK: - Which kind

    func testARatingRaisedOrChosenAgainIsAFlourishAndOneLoweredIsQuiet() {
        XCTAssertEqual(saved(80, from: 40).kind, .raise)
        XCTAssertEqual(saved(60, from: 60).kind, .raise, "a click on the stars a song already has still answers")
        XCTAssertEqual(saved(10, from: 0).kind, .raise, "a half star is a star")
        XCTAssertEqual(saved(40, from: 80).kind, .lower, "never a flourish for stars taken away")
        XCTAssertEqual(saved(0, from: 60).kind, .lower)
        XCTAssertEqual(saved(0, from: 0).kind, .lower, "nothing lit, so nothing to pop")
    }

    func testRaisedOrLoweredIsAgainstTheRatingBeforeTheGestureNotWhatADragShowed() {
        // Two stars; the drag went up to five and was let go on three
        let up = saved(60, from: 40, showing: 100)
        XCTAssertEqual(up.kind, .raise)
        XCTAssertEqual(up.from, Stars.styles(forRating: 100))
        XCTAssertEqual(up.to, Stars.styles(forRating: 60))
        // Four stars; the drag went down to one and was let go on three
        XCTAssertEqual(saved(60, from: 80, showing: 20).kind, .lower)
    }

    func testReduceMotionCrossFadesWhateverWasSaved() {
        XCTAssertEqual(saved(80, from: 40, reduceMotion: true).kind, .fade)
        XCTAssertEqual(saved(20, from: 80, reduceMotion: true).kind, .fade)
    }

    func testNothingToDrawTakesNoTime() {
        XCTAssertEqual(saved(0, from: 0).duration, 0, "no stars chosen for a song that had none")
        XCTAssertEqual(saved(60, from: 60, reduceMotion: true).duration, 0, "the same stars, and nothing may move")
        XCTAssertGreaterThan(saved(60, from: 60).duration, 0, "the same stars still pop")
    }

    func testTheLookComesFromTheHiddenDefault() throws {
        let suite = "StarFlourishTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(StarFlourish.Look.current(defaults), .run, "the one-colour run, unless it says otherwise")
        for look in StarFlourish.Look.allCases {
            defaults.set(look.rawValue, forKey: "starFlourish")
            XCTAssertEqual(StarFlourish.Look.current(defaults), look)
        }
        defaults.set("fireworks", forKey: "starFlourish")
        XCTAssertEqual(StarFlourish.Look.current(defaults), .run, "a name it doesn't know changes nothing")
    }

    // MARK: - The run

    func testTheRunReachesTheLitStarsFromTheLeftOneAfterAnother() {
        for look in [StarFlourish.Look.afterglow, .run] {
            let flourish = saved(100, from: 0, look: look)
            let delays = (0..<5).map { flourish.delay(of: $0) }
            XCTAssertEqual(delays[0], 0, "\(look)")
            for (earlier, later) in zip(delays, delays.dropFirst()) {
                XCTAssertEqual(later - earlier, 0.05, accuracy: 0.0001, "\(look)")
            }
        }
    }

    func testEveryLitStarPopsPastItsSizeAndTheLastOneHardest() {
        for look in [StarFlourish.Look.afterglow, .run] {
            let flourish = saved(80, from: 20, look: look)
            let peaks = (0..<4).map { largestScale(of: $0, in: flourish) }
            for peak in peaks {
                XCTAssertGreaterThan(peak, 1.12, "\(look): a pop, not a nudge")
                XCTAssertLessThanOrEqual(peak, StarFlourish.largestScale, "\(look)")
            }
            XCTAssertGreaterThan(peaks[3], peaks[2] + 0.05, "\(look): the star that makes the rating lands hardest")
            XCTAssertEqual(peaks[0], peaks[2], accuracy: 0.02, "\(look): the others alike")
            XCTAssertEqual(largestScale(of: 4, in: flourish), 1, "\(look): the dot never moves")
        }
    }

    /// A star dips a little under its size after the overshoot, which is what makes it a pop
    func testAStarSettlesFromJustUnderItsSize() {
        let flourish = saved(60, from: 60)
        let scales = frames(of: flourish).map { flourish.pose(of: 0, at: $0).scale }
        XCTAssertLessThan(scales.min() ?? 1, 0.99)
        XCTAssertGreaterThan(scales.min() ?? 0, 0.9, "but never visibly small")
    }

    func testThePlainPopGrowsEveryLitStarTogetherToOneTenthOver() {
        let flourish = saved(80, from: 20, look: .pop)
        XCTAssertEqual((0..<5).map { flourish.delay(of: $0) }, [0, 0, 0, 0, 0])
        for index in 0..<4 {
            XCTAssertEqual(largestScale(of: index, in: flourish), 1.1, accuracy: 0.005)
        }
        XCTAssertLessThan(flourish.duration, 0.3, "briefly")
    }

    func testAStarTheRunLightsGrowsOutOfItsDotAsTheRunReachesIt() {
        let flourish = saved(60, from: 0)
        let slot = StarFlourish.slot(2, starSize: starSize, spacing: spacing)
        let dot = StarFlourish.Glyph(style: .dot, frame: slot, opacity: 1)

        XCTAssertEqual(flourish.glyphs(of: 2, at: 0, in: slot), [dot], "still a dot on the first frame")
        XCTAssertEqual(flourish.glyphs(of: 2, at: flourish.delay(of: 2) - 0.001, in: slot), [dot], "and until the run reaches it")

        let arriving = flourish.pose(of: 2, at: flourish.delay(of: 2))
        XCTAssertEqual(arriving.morph, 0)
        XCTAssertLessThan(arriving.scale, 0.5, "it starts small")

        let lit = flourish.delay(of: 2) + StarFlourish.bloomFadeDuration + 0.001
        XCTAssertEqual(flourish.pose(of: 2, at: lit).morph, 1, accuracy: 0.0001)
        let glyphs = flourish.glyphs(of: 2, at: lit, in: slot)
        XCTAssertEqual(glyphs.map { $0.style }, [.full], "all star, a few frames on")
        XCTAssertGreaterThan(glyphs[0].frame.width, starSize.width, "and already past its size")
    }

    /// On macOS 27 a press lights the stars before the release saves them, so the flourish
    /// plays over stars that are already there
    func testStarsAlreadyLitPopWhereTheyAreWithoutShrinkingFirst() {
        let flourish = saved(60, from: 20, showing: 60)
        for index in 0..<3 {
            let first = flourish.pose(of: index, at: 0)
            XCTAssertEqual(first.scale, 1, "star \(index) is whole and its own size on the first frame")
            XCTAssertEqual(first.morph, 1)
            XCTAssertEqual(first.tint, 0)
            for elapsed in frames(of: flourish) {
                let pose = flourish.pose(of: index, at: elapsed)
                XCTAssertEqual(pose.morph, 1)
                XCTAssertGreaterThan(pose.scale, 0.9)
            }
        }
    }

    func testAHalfStarFillingOutIsAlreadyItsSize() {
        let flourish = saved(60, from: 50)
        XCTAssertEqual(flourish.from[2], .half)
        XCTAssertEqual(flourish.to[2], .full)
        let arriving = flourish.pose(of: 2, at: flourish.delay(of: 2))
        XCTAssertEqual(arriving.scale, 1, "only a dot has to grow")
        XCTAssertEqual(arriving.morph, 0)
        let slot = StarFlourish.slot(2, starSize: starSize, spacing: spacing)
        let midway = flourish.glyphs(of: 2, at: flourish.delay(of: 2) + StarFlourish.bloomFadeDuration / 2, in: slot)
        XCTAssertEqual(midway.map { $0.style }, [.half, .full])
        XCTAssertEqual(midway.map { $0.opacity }.reduce(0, +), 1, accuracy: 0.0001, "the half they share stays solid")
    }

    func testADragLetGoBelowWhereItWentPopsWhatIsLeftAndDropsTheRestQuietly() {
        let flourish = saved(60, from: 20, showing: 100)
        XCTAssertEqual(flourish.lit, 3)
        for index in 3..<5 {
            XCTAssertEqual(flourish.delay(of: index), 0, "they go at once")
            XCTAssertEqual(largestScale(of: index, in: flourish), 1, "and nothing of them pops")
            XCTAssertEqual(flourish.pose(of: index, at: StarFlourish.lowerDuration).morph, 1, accuracy: 0.0001)
        }
        XCTAssertGreaterThan(largestScale(of: 2, in: flourish), 1.2)
    }

    // MARK: - The colour

    func testTheColourComesUpFastHoldsThroughThePopAndCoolsAway() {
        let flourish = saved(20, from: 0)
        func tint(_ elapsed: TimeInterval) -> CGFloat { return flourish.pose(of: 0, at: elapsed).tint }
        XCTAssertEqual(tint(0), 0)
        XCTAssertEqual(tint(StarFlourish.tintRiseDuration), 1, accuracy: 0.0001)
        XCTAssertEqual(tint(StarFlourish.tintCoolStart), 1, accuracy: 0.0001, "full while the star overshoots")
        let cooling = stride(from: StarFlourish.tintCoolStart, through: flourish.duration, by: 1.0 / 60.0).map { tint($0) }
        for (earlier, later) in zip(cooling, cooling.dropFirst()) {
            XCTAssertLessThanOrEqual(later, earlier + 0.0001, "it only cools")
        }
        XCTAssertEqual(tint(flourish.duration), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(flourish.duration, 0.6, "long enough to see the colour go")
    }

    func testOnlyTheAfterglowHasColour() {
        for look in [StarFlourish.Look.run, .pop] {
            let flourish = saved(100, from: 0, look: look)
            XCTAssertFalse(look.tints)
            for elapsed in frames(of: flourish) {
                XCTAssertEqual((0..<5).map { flourish.pose(of: $0, at: elapsed).tint }, [0, 0, 0, 0, 0], "\(look)")
                XCTAssertNil(flourish.tintImage(at: elapsed, starSize: starSize, spacing: spacing), "\(look)")
            }
        }
        XCTAssertTrue(StarFlourish.Look.afterglow.tints)
    }

    // MARK: - Lowered, Reduce Motion, and while the button is held

    func testALoweredRatingFoldsBackFromTheRightAndNothingPops() {
        let flourish = saved(20, from: 80)
        XCTAssertEqual((1..<4).map { flourish.delay(of: $0) }, [0.06, 0.03, 0], "the fourth star goes first")
        XCTAssertEqual(flourish.duration, 0.06 + StarFlourish.lowerDuration, accuracy: 0.0001)
        XCTAssertLessThan(flourish.duration, 0.25, "a quiet change")
        for elapsed in frames(of: flourish) {
            for index in 0..<5 {
                let pose = flourish.pose(of: index, at: elapsed)
                XCTAssertEqual(pose.scale, 1)
                XCTAssertEqual(pose.tint, 0)
                XCTAssertFalse(pose.crossFades, "the star shrinks into its dot")
            }
            XCTAssertEqual(flourish.pose(of: 0, at: elapsed), .rest, "the star that stays doesn't stir")
            XCTAssertNil(flourish.tintImage(at: elapsed, starSize: starSize, spacing: spacing))
        }
        // Shrinking, not just fading: part way through, the star is smaller than its slot
        let slot = StarFlourish.slot(3, starSize: starSize, spacing: spacing)
        let folding = flourish.glyphs(of: 3, at: StarFlourish.lowerDuration / 2, in: slot)
        XCTAssertEqual(folding.first?.style, .full)
        XCTAssertLessThan(folding.first?.frame.width ?? 99, starSize.width)
    }

    func testReduceMotionCrossFadesTheGlyphsThatChangeAndMovesNothing() {
        let flourish = saved(80, from: 40, reduceMotion: true)
        XCTAssertEqual(flourish.duration, StarFlourish.fadeDuration)
        XCTAssertLessThan(flourish.duration, 0.2)
        for elapsed in frames(of: flourish) {
            for index in 0..<5 {
                let pose = flourish.pose(of: index, at: elapsed)
                XCTAssertEqual(pose.scale, 1, "nothing changes size")
                XCTAssertEqual(pose.tint, 0)
                XCTAssertEqual(flourish.delay(of: index), 0, "and nothing takes turns")
            }
        }
        XCTAssertEqual(flourish.pose(of: 2, at: StarFlourish.fadeDuration / 2).morph, 0.5, accuracy: 0.0001)
        XCTAssertTrue(flourish.pose(of: 2, at: 0).crossFades)
        XCTAssertEqual(flourish.pose(of: 0, at: 0), .rest, "a star that doesn't change isn't touched")
        // Where they are: both glyphs fill the slot they share, at their own size
        let slot = StarFlourish.slot(2, starSize: starSize, spacing: spacing)
        let midway = flourish.glyphs(of: 2, at: StarFlourish.fadeDuration / 2, in: slot)
        XCTAssertEqual(midway.map { $0.style }, [.full, .dot])
        XCTAssertEqual(midway.map { $0.frame }, [slot, slot])
    }

    func testAHeldPressChangesTheGlyphsQuicklyAndPopsNothing() throws {
        let flourish = try XCTUnwrap(StarFlourish.preview(from: 40, to: 80, reduceMotion: false))
        XCTAssertEqual(flourish.kind, .preview)
        XCTAssertEqual(flourish.duration, StarFlourish.previewDuration)
        for elapsed in frames(of: flourish) {
            for index in 0..<5 {
                XCTAssertLessThanOrEqual(flourish.pose(of: index, at: elapsed).scale, 1)
                XCTAssertEqual(flourish.pose(of: index, at: elapsed).tint, 0)
            }
        }
        XCTAssertNil(StarFlourish.preview(from: 40, to: 40, reduceMotion: false), "nothing changes")
        XCTAssertNil(StarFlourish.preview(from: 40, to: 80, reduceMotion: true), "they switch as they always did")
    }

    // MARK: - The five-star finale

    func testOnlyASongThatBecomesFiveStarsHasTheFinale() throws {
        XCTAssertTrue(saved(100, from: 60).hasFinale)
        XCTAssertTrue(saved(100, from: 0).hasFinale)
        XCTAssertTrue(saved(100, from: 90).hasFinale, "four and a half, filled out")
        XCTAssertTrue(saved(100, from: 60, showing: 100).hasFinale, "the press had lit all five before the release saved them")
        XCTAssertFalse(saved(100, from: 100).hasFinale, "five stars chosen again only pop")
        XCTAssertFalse(saved(90, from: 60).hasFinale, "four and a half isn't five")
        XCTAssertFalse(saved(80, from: 60).hasFinale)
        XCTAssertFalse(saved(80, from: 100).hasFinale, "never for stars taken away")
        XCTAssertFalse(saved(100, from: 60, reduceMotion: true).hasFinale, "nothing may move")
        let held = try XCTUnwrap(StarFlourish.preview(from: 60, to: 100, reduceMotion: false))
        XCTAssertFalse(held.hasFinale, "nothing is saved while the button is held")
        for look in StarFlourish.Look.allCases {
            XCTAssertTrue(saved(100, from: 60, look: look).hasFinale, "\(look)")
        }
    }

    func testAFlourishLastsAsLongAsItsFinale() {
        let run = saved(100, from: 60, look: .run)
        XCTAssertEqual(run.starsDuration, 0.5, accuracy: 0.0001, "the run itself")
        XCTAssertEqual(run.duration, StarFinale.duration(stagger: 0.05), accuracy: 0.0001, "and the small stars still in the air")
        XCTAssertEqual(run.duration, 0.88, accuracy: 0.0001)

        let pop = saved(100, from: 60, look: .pop)
        XCTAssertEqual(pop.starsDuration, 0.25, accuracy: 0.0001)
        XCTAssertEqual(pop.duration, 0.68, accuracy: 0.0001, "all five leave together")

        let afterglow = saved(100, from: 60, look: .afterglow)
        XCTAssertGreaterThanOrEqual(afterglow.duration, afterglow.starsDuration, "never cut short of the colour cooling")
        XCTAssertGreaterThanOrEqual(afterglow.duration, StarFinale.duration(stagger: 0.05))

        // With no finale, a flourish takes the stars' own time and no more
        let four = saved(80, from: 60, look: .run)
        XCTAssertEqual(four.duration, four.starsDuration)
        XCTAssertEqual(saved(100, from: 100, look: .run).duration, 0.5, accuracy: 0.0001, "five stars chosen again")
    }

    /// While the small stars finish their flight, the stars themselves are drawn at rest
    func testTheStarsAreAtRestWhileTheFinaleFinishes() {
        let flourish = saved(100, from: 60, look: .run)
        XCTAssertLessThan(flourish.starsDuration, flourish.duration)
        for elapsed in stride(from: flourish.starsDuration, through: flourish.duration, by: 1.0 / 60.0) {
            for index in 0..<5 {
                let pose = flourish.pose(of: index, at: elapsed)
                XCTAssertEqual(pose.scale, 1, accuracy: 0.0001, "star \(index) at \(elapsed)")
                XCTAssertEqual(pose.morph, 1, accuracy: 0.0001, "star \(index) at \(elapsed)")
                XCTAssertEqual(pose.tint, 0, accuracy: 0.0001, "star \(index) at \(elapsed)")
            }
        }
    }

    // MARK: - The end

    func testEveryFlourishEndsWithTheSavedStarsAtRest() {
        let ratings = stride(from: 0, through: 100, by: 10).map { $0 }
        for look in StarFlourish.Look.allCases {
            for reduceMotion in [false, true] {
                for before in ratings {
                    for rating in ratings {
                        let flourish = saved(rating, from: before, reduceMotion: reduceMotion, look: look)
                        for index in 0..<5 {
                            let pose = flourish.pose(of: index, at: flourish.duration)
                            let what = "\(look), reduce motion \(reduceMotion), \(before) to \(rating), star \(index)"
                            XCTAssertEqual(pose.scale, 1, accuracy: 0.0001, what)
                            XCTAssertEqual(pose.tint, 0, accuracy: 0.0001, what)
                            XCTAssertEqual(pose.morph, 1, accuracy: 0.0001, what)
                        }
                    }
                }
            }
        }
    }

    // MARK: - As drawn

    func testTheImagesAreTheStripsWidthWithRoomForAPop() {
        let size = StarFlourish.imageSize(starSize: starSize, spacing: spacing)
        XCTAssertEqual(size.width, RatingControl.imageWidth(mode: .rating, starSize: starSize, spacing: spacing), "heart slot and all")
        XCTAssertEqual(StarFlourish.headroom(starSize: starSize), 3)
        XCTAssertEqual(size.height, 22, "the same room above and below, so the stars stay where they are")
        XCTAssertEqual(StarFlourish.slot(0, starSize: starSize, spacing: spacing), NSRect(x: 4, y: 3, width: 16, height: 16))
        XCTAssertEqual(StarFlourish.slot(4, starSize: starSize, spacing: spacing), NSRect(x: 84, y: 3, width: 16, height: 16))

        let flourish = saved(100, from: 0)
        let image = flourish.image(at: 0.1, starSize: starSize, spacing: spacing)
        XCTAssertEqual(image.size, size)
        XCTAssertTrue(image.isTemplate, "the menu bar colours it as it does the stars at rest")
        let tint = flourish.tintImage(at: 0.1, starSize: starSize, spacing: spacing)
        XCTAssertEqual(tint?.size, size, "so it sits exactly over the stars")
        XCTAssertEqual(tint?.isTemplate, false, "its colours are its own")
    }

    /// In the menu bar and at each size the strip draws its stars
    func testAStarAtItsBiggestStaysInsideTheImageAndOffTheHeart() {
        var layouts: [(NSSize, CGFloat)] = [(starSize, spacing)]
        let stripScales: [CGFloat] = [1, 1.44, 2]
        for scale in stripScales {
            layouts.append((NSSize(width: 12 * scale, height: 12 * scale), 3 * scale))
        }
        for (starSize, spacing) in layouts {
            let bounds = NSRect(origin: .zero, size: StarFlourish.imageSize(starSize: starSize, spacing: spacing))
            let heartMinX = RatingControl.favoriteMinX(mode: .rating, starSize: starSize, spacing: spacing)
            for index in 0..<5 {
                let slot = StarFlourish.slot(index, starSize: starSize, spacing: spacing)
                let frame = StarFlourish.frame(ofStarIn: slot, scale: StarFlourish.largestScale)
                XCTAssertTrue(bounds.contains(frame), "\(starSize.width) pt star \(index): \(frame) in \(bounds)")
                XCTAssertLessThanOrEqual(frame.maxX, heartMinX, "\(starSize.width) pt star \(index)")
            }
        }
    }

    func testAStarGrowsAboutItsOwnCentreWhichIsBelowItsSlots() {
        let slot = StarFlourish.slot(1, starSize: starSize, spacing: spacing)
        XCTAssertEqual(StarFlourish.frame(ofStarIn: slot, scale: 1), slot)
        let grown = StarFlourish.frame(ofStarIn: slot, scale: 1.2)
        XCTAssertEqual(grown.midX, slot.midX, accuracy: 0.0001)
        XCTAssertEqual(grown.width, 19.2, accuracy: 0.0001)
        // The star's centre, 0.764 pt under the slot's for a 16 pt star, is the point that stays
        let centreY = slot.midY - 0.764
        XCTAssertEqual(StarFlourish.centre(ofStarIn: slot).x, slot.midX, accuracy: 0.0001)
        XCTAssertEqual(StarFlourish.centre(ofStarIn: slot).y, centreY, accuracy: 0.0001, "where the finale's small stars leave from")
        XCTAssertEqual(grown.minY + (centreY - slot.minY) * 1.2, centreY, accuracy: 0.0001)
    }

    /// The first and last frames are the stars exactly as they are at rest, in the same place
    /// once the image is centred where they were: any difference would show as a jump
    func testAFlourishStartsAndEndsOnTheStarsAtRestPixelForPixel() throws {
        let flourish = saved(70, from: 30, showing: 70)
        let rest = Stars(stars: Stars.styles(forRating: 70).map { Star(size: starSize, style: $0) }, spacing: spacing,
                         showsFavorite: true, isFavorited: false, drawsFavorite: false).image
        let expected = try bitmap(of: rest, at: NSPoint(x: 0, y: StarFlourish.headroom(starSize: starSize)))
        for elapsed in [0, flourish.duration] {
            let drawn = try bitmap(of: flourish.image(at: elapsed, starSize: starSize, spacing: spacing))
            var worst = 0.0
            for y in 0..<drawn.pixelsHigh {
                for x in 0..<drawn.pixelsWide {
                    worst = max(worst, abs(alpha(in: drawn, x: x, y: y) - alpha(in: expected, x: x, y: y)))
                }
            }
            XCTAssertLessThan(worst, 0.02, "at \(elapsed) s")
        }
        XCTAssertGreaterThan(alpha(in: expected, x: 11, y: 10), 0.9, "and there are stars to compare")
    }

    /// The colour is painted only where a star the flash has reached is: the icon's bands down
    /// that star, pink at its top point and green at its feet, and nothing anywhere else
    func testTheFlashPaintsTheIconsBandsOnTheStarsItHasReachedAndNowhereElse() throws {
        let flourish = saved(100, from: 0)
        XCTAssertNil(flourish.tintImage(at: 0, starSize: starSize, spacing: spacing), "nothing is coloured on the first frame")
        XCTAssertNil(flourish.tintImage(at: flourish.duration, starSize: starSize, spacing: spacing), "nor once it has cooled")

        // 0.3 s in, the first star has settled at its own size and is still nine tenths
        // coloured; the run has reached every star but only just lit the last
        let elapsed = 0.3
        XCTAssertEqual(flourish.pose(of: 0, at: elapsed).scale, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(flourish.pose(of: 0, at: elapsed).tint, 0.85)
        let tint = try bitmap(of: XCTUnwrap(flourish.tintImage(at: elapsed, starSize: starSize, spacing: spacing)))

        // The first star's slot is x 4 to 20, y 3 to 19, with y up from the image's bottom
        let top = try colour(in: tint, x: 12, y: 15)
        XCTAssertGreaterThan(top.alphaComponent, 0.6)
        XCTAssertGreaterThan(top.redComponent, top.greenComponent + 0.3, "pink at the top point")
        let middle = try colour(in: tint, x: 11, y: 10)
        XCTAssertGreaterThan(middle.redComponent, 0.7, "lemon across the middle")
        XCTAssertGreaterThan(middle.greenComponent, 0.7)
        XCTAssertLessThan(middle.blueComponent, 0.5)
        let foot = try colour(in: tint, x: 9, y: 6)
        XCTAssertGreaterThan(foot.alphaComponent, 0.6)
        XCTAssertGreaterThan(foot.greenComponent, foot.redComponent + 0.3, "green at its feet")

        XCTAssertEqual(alpha(in: tint, x: 1, y: 11), 0, "nothing left of the first star")
        XCTAssertEqual(alpha(in: tint, x: 116, y: 11), 0, "nothing in the heart's slot")
        XCTAssertEqual(alpha(in: tint, x: 12, y: 0), 0, "nothing under the stars")

        // Earlier, the run hasn't reached the last star, which is still an uncoloured dot
        let early = try bitmap(of: XCTUnwrap(flourish.tintImage(at: 0.1, starSize: starSize, spacing: spacing)))
        XCTAssertGreaterThan(alpha(in: early, x: 11, y: 10), 0.9, "the first star is in full colour")
        XCTAssertEqual(alpha(in: early, x: 91, y: 10), 0, "the fifth has no colour yet")
    }

    // MARK: - Reading what was drawn

    /// `image` drawn at `origin` in a bitmap the size of a flourish's images, one pixel a point
    private func bitmap(of image: NSImage, at origin: NSPoint = .zero) throws -> NSBitmapImageRep {
        let size = StarFlourish.imageSize(starSize: starSize, spacing: spacing)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: origin, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    /// The pixel `x` points from the left and `y` points up from the bottom, as AppKit draws
    private func colour(in bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
        return try XCTUnwrap(bitmap.colorAt(x: x, y: bitmap.pixelsHigh - 1 - y))
    }

    private func alpha(in bitmap: NSBitmapImageRep, x: Int, y: Int) -> Double {
        return Double(bitmap.colorAt(x: x, y: bitmap.pixelsHigh - 1 - y)?.alphaComponent ?? 0)
    }

}
