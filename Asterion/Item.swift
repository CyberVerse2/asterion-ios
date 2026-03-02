//
//  Item.swift
//  Asterion
//
//  Created by Celestine Ejiofor on 02/03/2026.
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
