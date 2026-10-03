//
//  WatchHaptics.swift
//  sansan Watch App
//

import WatchKit

enum WatchHaptics {
    static func click() {
        WKInterfaceDevice.current().play(.click)
    }

    /// `.click`보다 확실히 체감되는 버튼 탭 피드백.
    static func tap() {
        WKInterfaceDevice.current().play(.directionUp)
    }

    static func success() {
        WKInterfaceDevice.current().play(.success)
    }

    static func start() {
        WKInterfaceDevice.current().play(.start)
    }

    static func notification() {
        WKInterfaceDevice.current().play(.notification)
    }
}
