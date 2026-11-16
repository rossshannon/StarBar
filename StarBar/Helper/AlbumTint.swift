//
//  AlbumTint.swift
//  StarBar
//
//  The colour the strip takes from a song's cover with the album tint on: picked, made
//  legible under white text and faded in OKLab. Pure: see `AlbumTintTests`.
//

import AppKit

/// A colour in OKLab: lightness from 0 (black) to 1 (white), and two axes of colour, green to
/// red (`a`) and blue to yellow (`b`).
///
/// The strip's tint is picked, kept legible and faded in OKLab rather than RGB because the
/// space is built so that equal steps look equal: a lightness limit means the same thing for
/// every hue, and halfway between two colours looks halfway, where a plain RGB mix of a red
/// and a green passes through a muddy brown. The conversions are Björn Ottosson's (2020).
struct OKLab: Equatable {

    var l: Double
    var a: Double
    var b: Double

    static let black = OKLab(l: 0, a: 0, b: 0)

    init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    /// From linear-light sRGB, each 0 to 1
    init(linearRed r: Double, green g: Double, blue b: Double) {
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        self.init(
            l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    /// From sRGB as an image stores it, gamma-encoded, each 0 to 1
    init(red: Double, green: Double, blue: Double) {
        self.init(linearRed: OKLab.linear(red), green: OKLab.linear(green), blue: OKLab.linear(blue))
    }

    /// How colourful: 0 for a grey
    var chroma: Double {
        return hypot(a, b)
    }

    /// The hue angle in radians, from 0 up to 2π
    var hue: Double {
        let angle = atan2(b, a)
        return angle < 0 ? angle + 2 * .pi : angle
    }

    /// Linear-light sRGB, outside 0...1 for a colour sRGB can't show
    var linearRGB: (red: Double, green: Double, blue: Double) {
        let l = pow(self.l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(self.l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(self.l - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    /// Whether sRGB, and so the screen, can show this colour
    var isInSRGB: Bool {
        let rgb = linearRGB
        let tolerance = 1e-4
        return [rgb.red, rgb.green, rgb.blue].allSatisfy { $0 >= -tolerance && $0 <= 1 + tolerance }
    }

    /// Gamma-encoded sRGB, each 0 to 1, clamped to what sRGB can show
    var sRGB: (red: Double, green: Double, blue: Double) {
        let rgb = linearRGB
        return (OKLab.encoded(rgb.red), OKLab.encoded(rgb.green), OKLab.encoded(rgb.blue))
    }

    /// Relative luminance, as WCAG defines it for contrast
    var luminance: Double {
        let rgb = linearRGB
        let clamp = { (value: Double) in min(1, max(0, value)) }
        return 0.2126 * clamp(rgb.red) + 0.7152 * clamp(rgb.green) + 0.0722 * clamp(rgb.blue)
    }

    /// The contrast of white text on this colour drawn opaque, as WCAG measures it: 4.5 is the
    /// least it asks of text this size
    var contrastWithWhite: Double {
        return 1.05 / (luminance + 0.05)
    }

    /// The contrast of white text on this colour drawn at `alpha` over black. The screen mixes
    /// a translucent colour in sRGB's encoded values, not in linear light, so that is how it
    /// is mixed here: half of a colour over black is darker than half its light.
    func contrastWithWhite(atAlpha alpha: Double) -> Double {
        let rgb = sRGB
        let mixed = [rgb.red, rgb.green, rgb.blue].map { OKLab.linear($0 * min(1, max(0, alpha))) }
        let luminance = 0.2126 * mixed[0] + 0.7152 * mixed[1] + 0.0722 * mixed[2]
        return 1.05 / (luminance + 0.05)
    }

    func color(alpha: CGFloat) -> NSColor {
        let rgb = sRGB
        return NSColor(srgbRed: CGFloat(rgb.red), green: CGFloat(rgb.green), blue: CGFloat(rgb.blue), alpha: alpha)
    }

    func cgColor(alpha: CGFloat) -> CGColor {
        let rgb = sRGB
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGColor(colorSpace: space, components: [CGFloat(rgb.red), CGFloat(rgb.green), CGFloat(rgb.blue), alpha])
            ?? CGColor(red: CGFloat(rgb.red), green: CGFloat(rgb.green), blue: CGFloat(rgb.blue), alpha: alpha)
    }

    static func linear(_ encoded: Double) -> Double {
        return encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
    }

    static func encoded(_ linear: Double) -> Double {
        let value = min(1, max(0, linear))
        return value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    /// A short description for the log: lightness, chroma and hue in degrees
    var logDescription: String {
        return String(format: "L %.2f C %.3f h %.0f°", l, chroma, hue * 180 / .pi)
    }

}

/// The colour the announcement strip's background takes from a song's cover, when the album
/// tint is on in Preferences. Ross asked for it on 2026-11-16 and was shown four pickers side
/// by side (average, dominant, the border's dominant and this one).
///
/// This one is "vivid": the cover's most present hue, each pixel counted by how colourful it
/// is. A grey sky or a white border can't outvote the colour of the sleeve, and a small strong
/// accent on a black cover still counts; a cover with hardly any colour in it (black and white,
/// a pale sepia) has no tint at all, and the strip stays as the style draws it. The colour is
/// then made dark enough for the strip's white text (`legible(_:)`).
enum AlbumTint {

    /// The cover is read as this many pixels a side, each the average of a 2 by 2 block of a
    /// copy twice the size, so every pixel of the original counts
    static let side = 32
    /// Slices of the colour wheel the hues are counted in, 15° each
    static let hueBins = 24
    /// Below this chroma a pixel is grey and has no hue worth counting
    static let minimumChroma = 0.04
    /// The least colour a cover must have, as the summed chroma of its colourful pixels over
    /// all its pixels, to tint the strip: 5% of the cover at a chroma of 0.16 is enough
    static let minimumColour = 0.008
    /// The tint's lightness. The top keeps white text at 4.5 : 1 or more even drawn opaque, as
    /// it is under Reduce Transparency (a grey at 0.5 gives about 6); the bottom lifts a dark
    /// colour far enough for its hue to read, so a navy cover gives navy rather than black. A
    /// grey isn't lifted: a black cover's strip stays black.
    static let lightness: ClosedRange<Double> = 0.30...0.50
    /// The most chroma the tint keeps: enough for the colour to be plain, short of neon
    static let maximumChroma = 0.14

    /// The tint for `image`, or nil when it has too little colour to give one
    static func colour(of image: NSImage) -> OKLab? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let samples = samples(of: cgImage) else { return nil }
        return vivid(samples).map(legible)
    }

    /// The cover's pixels, `side` by `side`, in OKLab; mostly transparent ones are left out,
    /// so a cover cut to a shape (the Preview's app icon) is judged by what is drawn
    static func samples(of cgImage: CGImage) -> [OKLab]? {
        let side = AlbumTint.side
        let drawn = side * 2
        var pixels = [UInt8](repeating: 0, count: drawn * drawn * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: drawn, height: drawn,
                                          bitsPerComponent: 8, bytesPerRow: drawn * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: drawn, height: drawn))
            return true
        }
        guard didDraw else { return nil }

        var samples: [OKLab] = []
        samples.reserveCapacity(side * side)
        for row in 0..<side {
            for column in 0..<side {
                var total = [0, 0, 0, 0]
                for y in 0..<2 {
                    for x in 0..<2 {
                        let pixel = ((row * 2 + y) * drawn + column * 2 + x) * 4
                        for channel in 0..<4 {
                            total[channel] += Int(pixels[pixel + channel])
                        }
                    }
                }
                // Mostly see-through: not part of the cover
                guard total[3] >= 2 * 255 else { continue }
                // Premultiplied, so dividing by the alpha undoes it
                let alpha = Double(total[3])
                samples.append(OKLab(red: Double(total[0]) / alpha, green: Double(total[1]) / alpha, blue: Double(total[2]) / alpha))
            }
        }
        return samples
    }

    /// The most present hue among `samples`, as their average colour within a slice of the
    /// wheel either side of it; nil when there is too little colour to count.
    ///
    /// Each colourful pixel counts its chroma towards its hue's slice, less for one near black
    /// or white, whose hue is mostly noise. The slices are smoothed with their neighbours
    /// before the peak is taken, so a colour that straddles two slices isn't split in half.
    static func vivid(_ samples: [OKLab]) -> OKLab? {
        guard !samples.isEmpty else { return nil }
        let bins = hueBins
        var slices = [Double](repeating: 0, count: bins)
        var counted: [(colour: OKLab, weight: Double, slice: Int)] = []
        var total = 0.0
        for colour in samples {
            let chroma = colour.chroma
            guard chroma >= minimumChroma else { continue }
            let weight = chroma * smoothstep(0.12, 0.30, colour.l) * (1 - smoothstep(0.90, 0.98, colour.l))
            guard weight > 0 else { continue }
            let slice = min(bins - 1, Int(colour.hue / (2 * .pi) * Double(bins)))
            slices[slice] += weight
            total += weight
            counted.append((colour, weight, slice))
        }
        guard total / Double(samples.count) >= minimumColour else { return nil }

        var peak = 0
        var peakScore = -1.0
        for slice in 0..<bins {
            let score = slices[(slice + bins - 1) % bins] + 2 * slices[slice] + slices[(slice + 1) % bins]
            if score > peakScore {
                peakScore = score
                peak = slice
            }
        }

        var sum = OKLab.black
        var weights = 0.0
        for sample in counted {
            let apart = abs(sample.slice - peak)
            guard min(apart, bins - apart) <= 1 else { continue }
            sum.l += sample.colour.l * sample.weight
            sum.a += sample.colour.a * sample.weight
            sum.b += sample.colour.b * sample.weight
            weights += sample.weight
        }
        guard weights > 0 else { return nil }
        return OKLab(l: sum.l / weights, a: sum.a / weights, b: sum.b / weights)
    }

    /// `colour` made fit to sit under white text: its lightness held within `lightness` (a
    /// grey only capped), its chroma capped at `maximumChroma` and then cut further until sRGB
    /// can show it at that lightness, keeping its hue throughout
    static func legible(_ colour: OKLab) -> OKLab {
        let floor = colour.chroma < minimumChroma ? 0 : lightness.lowerBound
        let l = min(lightness.upperBound, max(floor, colour.l))
        return shown(lightness: l, chroma: min(colour.chroma, maximumChroma), angle: atan2(colour.b, colour.a))
    }

    /// The glow's light: the tint's hue, made as bright as a light of that colour looks
    /// (`lightLightness`) and a little more colourful than the tint (`lightChromaBoost`, up to
    /// `lightChroma`), cut until sRGB can show it. Bright, because the tint's own lightness,
    /// kept low for the text, glowed like an ember in the mock-up rather than a light.
    static func light(_ tint: OKLab) -> OKLab {
        return shown(lightness: lightLightness, chroma: min(tint.chroma * lightChromaBoost, lightChroma), angle: atan2(tint.b, tint.a))
    }

    static let lightLightness = 0.70
    static let lightChroma = 0.17
    static let lightChromaBoost = 1.25

    /// The colour at `lightness` and `angle`, with `chroma` or as much of it as sRGB can show
    private static func shown(lightness l: Double, chroma: Double, angle: Double) -> OKLab {
        let at = { (chroma: Double) in OKLab(l: l, a: chroma * cos(angle), b: chroma * sin(angle)) }
        guard !at(chroma).isInSRGB else { return at(chroma) }
        var low = 0.0
        var high = chroma
        for _ in 0..<18 {
            let middle = (low + high) / 2
            if at(middle).isInSRGB {
                low = middle
            } else {
                high = middle
            }
        }
        return at(low)
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

}

extension AlbumTint {

    /// The glow from behind the cover, the album tint's second form (Ross, 2026-11-16: "tints
    /// the bar radially from behind the album art so it's like it's a light source"): a light
    /// of the cover's colour (`AlbumTint.light(_:)`) hidden behind the artwork, over the
    /// style's own background. It is full strength out to the artwork's edge and falls away in
    /// two parts, as light round an object does: a tight halo hugging the artwork and a long
    /// soft spill, gone by `reach` from the light's centre. Drawn as one radial gradient.
    ///
    /// Sizes are in points, already scaled with the strip.
    struct Glow: Equatable {

        /// The light's centre: the artwork's centre, in the glow layer's coordinates
        var centre: CGPoint
        /// Half the artwork's side: the light is hidden behind it, so it is full strength
        /// out to here
        var core: CGFloat
        /// How far from the centre the light reaches
        var reach: CGFloat
        /// The halo's size: half strength at this far past the artwork's edge
        var halo: CGFloat

        /// The reach at scale 1, unless `announcementGlowReach` says otherwise: from the
        /// break-out sleeve's centre, half of a 1440 point wide strip. Ross chose it from the
        /// mock-up's 320, 480 and 720 on 2026-11-16.
        static let defaultReach: CGFloat = 720
        static let defaultHalo: CGFloat = 10
        /// How much of the light is the halo; the rest is the spill
        static let haloShare = 0.4
        /// The spill's curve: 1 would fall away in a straight line, 2 sooner
        static let spillExponent = 1.6
        /// The most the light is at the artwork's edge, by the background it is drawn over: all
        /// of it over the classic strip's black (and Reduce Transparency's), a little less over
        /// a blur, and less again over Liquid Glass, whose own material should still show
        static func strongest(for style: TrackAnnouncementStyle, opaque: Bool) -> CGFloat {
            if opaque { return 1 }
            switch style {
            case .classic: return 1
            case .blur: return 0.9
            case .glass: return 0.75
            }
        }

        /// The break-out sleeve's: its centre 56 points in from its edge, and the title
        /// starts 12 points past that edge (the flat artwork's text starts 16 past its 40)
        static func sleeve(reach: CGFloat = defaultReach) -> Glow {
            return Glow(centre: .zero, core: TrackAnnouncementSleeve.size / 2, reach: reach, halo: defaultHalo)
        }
        static let titleGap: CGFloat = 12

        /// How much of the light there is `distance` past the artwork's edge, from 1 there to
        /// 0 at `reach`
        func strength(beyondEdge distance: CGFloat) -> CGFloat {
            guard distance > 0 else { return 1 }
            let span = Double(max(1, reach - core))
            let d = Double(distance)
            guard d < span else { return 0 }
            let halo = 1 / (1 + pow(d / Double(max(self.halo, 0.01)), 2))
            let spill = pow(1 - d / span, Glow.spillExponent)
            return CGFloat(Glow.haloShare * halo + (1 - Glow.haloShare) * spill)
        }

        /// The gradient's stops, from the centre out: where each is, as a share of `reach`, and
        /// how much of the light it has. Close together through the halo, wider through the
        /// spill, and nothing at the end.
        var stops: [(location: CGFloat, strength: CGFloat)] {
            let span = max(1, reach - core)
            let far: [CGFloat] = [0.2, 0.3, 0.42, 0.56, 0.7, 0.85, 1].map { $0 * span }
            let near: [CGFloat] = [0, 0.3, 0.6, 1, 1.5, 2.2, 3.2].map { $0 * halo }.filter { $0 < far[0] }
            var stops: [(location: CGFloat, strength: CGFloat)] = [(location: 0, strength: 1)]
            for distance in near + far {
                stops.append((location: min(1, (core + distance) / max(reach, 1)), strength: strength(beyondEdge: distance)))
            }
            return stops
        }

        /// The most the light may be at the artwork's edge: `most`, unless that would leave
        /// white text where the title starts, `titleGap` past the sleeve, under 4.5 : 1 over
        /// black, the style's background at its darkest. Worked out for the sleeve; the flat
        /// artwork's title starts further out, where there is less light.
        static func peak(for light: OKLab, most: CGFloat, reach: CGFloat = defaultReach) -> CGFloat {
            let atTitle = Double(sleeve(reach: reach).strength(beyondEdge: titleGap))
            let readable = { (peak: Double) in light.contrastWithWhite(atAlpha: peak * atTitle) >= minimumContrast }
            guard !readable(Double(most)) else { return most }
            var low = 0.0
            var high = Double(most)
            for _ in 0..<20 {
                let middle = (low + high) / 2
                if readable(middle) {
                    low = middle
                } else {
                    high = middle
                }
            }
            return CGFloat(low)
        }

        static let minimumContrast = 4.5

    }

}

/// What is laid over the strip's backdrop: a colour, and how much of it. The style's own black
/// wash is one; the cover's tint is another.
struct TrackAnnouncementWash: Equatable {

    var colour: OKLab
    var alpha: CGFloat

    /// `progress` of the way from `from` to `to` (0 to 1), mixed premultiplied, so black at 60%
    /// becomes red at 60% without passing through anything paler, and a colour coming in from
    /// nothing (the glass's untinted state) keeps its own hue while its alpha rises
    static func mix(_ from: TrackAnnouncementWash, _ to: TrackAnnouncementWash, progress: CGFloat) -> TrackAnnouncementWash {
        let t = Double(min(1, max(0, progress)))
        let alpha = Double(from.alpha) + Double(to.alpha - from.alpha) * t
        guard alpha > 1e-6 else { return TrackAnnouncementWash(colour: to.colour, alpha: 0) }
        let fromWeight = Double(from.alpha) * (1 - t)
        let toWeight = Double(to.alpha) * t
        let colour = OKLab(
            l: (from.colour.l * fromWeight + to.colour.l * toWeight) / alpha,
            a: (from.colour.a * fromWeight + to.colour.a * toWeight) / alpha,
            b: (from.colour.b * fromWeight + to.colour.b * toWeight) / alpha
        )
        return TrackAnnouncementWash(colour: colour, alpha: CGFloat(alpha))
    }

}
