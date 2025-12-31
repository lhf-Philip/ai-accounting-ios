//
//  Item.swift
//  AI 記帳
//
//  Created by Philip Li on 31/12/2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
