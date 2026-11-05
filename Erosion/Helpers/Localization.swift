//
//  Localization.swift
//  Erosion
//
//  Runtime-string localization helpers.
//
//  SwiftUI's `Text("literal")`, `Label(...)`, `.navigationTitle(...)` and friends
//  already treat their argument as a `LocalizedStringKey`, so those pick up
//  `zh-Hans.lproj/Localizable.strings` automatically. The problem is the large
//  number of strings that reach the UI as a plain `String`: shared components
//  (`HeaderLabel`, `PlainToggle`, `CompactAlert`, …), enum display names, and
//  alert titles handed to `Alertinator` (UIKit, not SwiftUI).
//
//  `Text(someString)` resolves to the verbatim initializer and never consults the
//  strings table, so those call sites have to look the key up explicitly. That is
//  what the helpers below are for. Unknown keys fall back to the original string,
//  which keeps behaviour identical when no translation is installed.
//

import Foundation
import SwiftUI

/// Looks `key` up in the main bundle's `Localizable.strings`, returning the key
/// itself when no translation exists.
@inline(__always)
func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

extension Text {
    /// Renders a runtime `String` through the strings table.
    /// Use this instead of `Text(_:)` for values that are already `String`.
    init(localized key: String) {
        self.init(NSLocalizedString(key, comment: ""))
    }
}
