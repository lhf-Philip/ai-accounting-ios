import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String? {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else { return nil }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)
        if components.count >= 4 { a = Float(components[3]) }
        
        if a != Float(1.0) {
            return String(format: "%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }

    func toRGBHex() -> String? {
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(
            format: "%02X%02X%02X",
            Int(round(r * 255)),
            Int(round(g * 255)),
            Int(round(b * 255))
        )
    }

    static func normalizedRGBHex(_ rawHex: String) -> String {
        let cleaned = rawHex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .uppercased()

        if cleaned.count == 3 {
            return cleaned.reduce(into: "") { result, char in
                result.append(char)
                result.append(char)
            }
        }

        if cleaned.count >= 6 {
            return String(cleaned.prefix(6))
        }

        return "007AFF"
    }

    static func uniqueSystemColorHex(
        from color: Color,
        avoiding manualPalette: Set<String>
    ) -> String? {
        let normalizedPalette = Set(manualPalette.map { normalizedRGBHex($0) })
        guard let baseHex = color.toRGBHex() else { return nil }
        if !normalizedPalette.contains(baseHex) {
            return baseHex
        }

        let baseUIColor = UIColor(color)
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard baseUIColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
            return baseHex
        }

        for step in 1...24 {
            let hueShift = CGFloat(step) * 0.035
            let shifted = UIColor(
                hue: (h + hueShift).truncatingRemainder(dividingBy: 1),
                saturation: max(s, 0.45),
                brightness: max(b, 0.45),
                alpha: 1
            )
            let candidate = Color(uiColor: shifted).toRGBHex() ?? baseHex
            if !normalizedPalette.contains(candidate) {
                return candidate
            }
        }

        return baseHex
    }
}
