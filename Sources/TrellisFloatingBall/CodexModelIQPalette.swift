import AppKit

enum CodexModelIQPalette {
    struct Style {
        let tint: NSColor
    }

    static let defaultHex = 0x64748B

    private static let fallbackColors: [String: Int] = [
        "gpt_56_sol_low": 0x92400E,
        "gpt_56_sol_medium": 0xB45309,
        "gpt_56_sol_high": 0xD97706,
        "gpt_56_sol_xhigh": 0xEAB308,
        "gpt_56_sol_max": 0xFACC15,
        "gpt_56_sol_ultra": 0xFDE047,
        "gpt_56_terra_low": 0x1E3A8A,
        "gpt_56_terra_medium": 0x1D4ED8,
        "gpt_56_terra_high": 0x2563EB,
        "gpt_56_terra_xhigh": 0x3B82F6,
        "gpt_56_terra_max": 0x60A5FA,
        "gpt_56_terra_ultra": 0x93C5FD,
        "gpt_56_luna_low": 0x9F1239,
        "gpt_56_luna_medium": 0xBE123C,
        "gpt_56_luna_high": 0xE11D48,
        "gpt_56_luna_xhigh": 0xF43F5E,
        "gpt_56_luna_max": 0xFB7185,
        "gpt_55_high": 0x22C55E,
        "gpt_55_xhigh": 0x4ADE80
    ]

    static func style(colorHex: Int) -> Style {
        Style(tint: NSColor(hex: colorHex))
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
