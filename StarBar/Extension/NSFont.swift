//
//  NSFont.swift
//  StarBar
//

import Cocoa

extension NSFont {

    /// The italic face of this font, or the font itself when there isn't one.
    ///
    /// The system font does have one (`.SFNS-RegularItalic`), so the album line really slants
    /// rather than quietly staying upright.
    var italic: NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }

}
