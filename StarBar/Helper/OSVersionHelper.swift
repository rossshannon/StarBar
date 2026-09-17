//
//  OSVersionHelper.swift
//  StarBar
//
//  Created by MainasuK Cirno on 2019/7/21.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Foundation

enum OSVersionHelper {
    
    static let bundleIdentifier: String = {
        if #available(macOS 10.15, *) {
            return "com.apple.Music"
        } else {
            return "com.apple.iTunes"
        }
    }()
    
}
