//
//  AppKitCompat.swift
//  macai
//
//  Lightweight AppKit type shims for iOS builds.
//

#if os(iOS)
import UIKit

typealias NSColor = UIColor
typealias NSImage = UIImage
typealias NSFont = UIFont
typealias NSSize = CGSize

extension UIColor {
    static var labelColor: UIColor { .label }
    static var secondaryLabelColor: UIColor { .secondaryLabel }
    static var tertiaryLabelColor: UIColor { .tertiaryLabel }
    static var textColor: UIColor { .label }
    static var controlBackgroundColor: UIColor { .secondarySystemBackground }
    static var windowBackgroundColor: UIColor { .systemBackground }
}
#endif
