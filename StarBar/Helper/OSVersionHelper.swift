//
//  OSVersionHelper.swift
//  StarBar
//
//  Created by MainasuK Cirno on 2019/7/21.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Foundation

enum OSVersionHelper {

    /// The player this app talks to. It was iTunes before macOS 10.15; the app now needs
    /// macOS 13, so it is always Music. The Scripting Bridge header keeps iTunes's names.
    static let bundleIdentifier = "com.apple.Music"

}
