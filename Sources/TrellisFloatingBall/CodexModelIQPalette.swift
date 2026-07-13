import AppKit

enum CodexModelIQPalette {
    struct Style {
        let tint: NSColor
        let labelBackground: NSColor
    }

    static let defaultHex = 0x64748B

    private static let fallbackColors: [String: Int] = [
        "gpt_56_sol_max": 0xFACC15,
        "gpt_56_sol_ultra": 0x16A34A,
        "gpt_56_sol_xhigh": 0xEAB308,
        "gpt_56_sol_high": 0xD97706,
        "gpt_56_sol_medium": 0xB45309,
        "gpt_56_sol_low": 0x92400E,
        "gpt_56_terra_max": 0x60A5FA,
        "gpt_56_terra_xhigh": 0x60A5FA,
        "gpt_56_terra_medium": 0x2563EB,
        "gpt_56_luna_max": 0xFB7185,
        "gpt_56_luna_medium": 0xD61F45,
        "gpt_55_xhigh": 0x16A34A,
        "gpt_55_high": 0x2563EB,
        "gpt_55_medium": 0xD97706,
        "gpt_55_low": 0x0891B2,
        "gpt_54_xhigh": 0x7C3AED,
        "gpt_54_high": 0xDC2626
    ]

    static func style(colorHex: Int) -> Style {
        let tint = NSColor(hex: colorHex)
        return Style(
            tint: tint,
            labelBackground: tint.blended(withFraction: 0.88, of: .white) ?? .white
        )
    }

    static func fallbackHex(modelKey: String?, name: String) -> Int {
        if let modelKey,
           let color = fallbackColors[normalizedKey(modelKey)]
        {
            return color
        }
        return fallbackColors[normalizedKey(name)] ?? defaultHex
    }

    static func normalizedKey(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "gpt-", with: "gpt_")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
