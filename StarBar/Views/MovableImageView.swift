//
//  MovableImageView.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-8-18.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Cocoa

final class MovableImageView: NSImageView {
    
    override var mouseDownCanMoveWindow: Bool {
        return true
    }
    
}

