import AppKit
import XCTest
@testable import TrellisFloatingBall

final class CodexModelIQPaletteTests: XCTestCase {
    func testCurrentModelFallbackColorsMatchSourceWebsite() {
        let expected: [String: Int] = [
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

        for (modelKey, colorHex) in expected {
            XCTAssertEqual(
                CodexModelIQPalette.fallbackHex(modelKey: modelKey, name: ""),
                colorHex,
                modelKey
            )
        }
    }

    func testFallbackCanDeriveModelKeyFromDisplayName() {
        XCTAssertEqual(
            CodexModelIQPalette.fallbackHex(modelKey: nil, name: "GPT-5.5-high"),
            0x22C55E
        )
        XCTAssertEqual(
            CodexModelIQPalette.fallbackHex(modelKey: nil, name: "GPT-5.6-Luna-max"),
            0xFB7185
        )
    }

    func testUnknownModelUsesNeutralFallback() {
        XCTAssertEqual(
            CodexModelIQPalette.fallbackHex(modelKey: "future_model", name: "Future model"),
            CodexModelIQPalette.defaultHex
        )
    }

    func testCardStyleUsesExactSourceColor() {
        let style = CodexModelIQPalette.style(colorHex: 0xFB7185)
        assertColor(style.tint, hex: 0xFB7185)
    }

    private func assertColor(
        _ color: NSColor,
        hex: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let components = color.usingColorSpace(.sRGB) else {
            XCTFail("颜色无法转换为 sRGB", file: file, line: line)
            return
        }
        XCTAssertEqual(components.redComponent, CGFloat((hex >> 16) & 0xFF) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components.greenComponent, CGFloat((hex >> 8) & 0xFF) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components.blueComponent, CGFloat(hex & 0xFF) / 255, accuracy: 0.001, file: file, line: line)
    }
}
