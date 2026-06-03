//
//  Item.swift
//  sansan
//
//  Created by Park Jeongwook on 6/3/26.
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
