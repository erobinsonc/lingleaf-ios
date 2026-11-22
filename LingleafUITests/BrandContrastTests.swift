import XCTest

/// The contrast of `Brand.secondaryText` (footers, captions) on the Form backgrounds, light and dark, without
/// a screenshot. The UI test bundle cannot import the app, so the two grey values are read from the source line that
/// defines them (`Lingleaf/Views/Components.swift`); if that line changes shape, the test fails and must be updated.
final class BrandContrastTests: XCTestCase {
    private func channel(_ value: Double) -> Double {
        value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private func luminance(_ red: Double, _ green: Double, _ blue: Double) -> Double {
        0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    private func ratio(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    func testSecondaryTextReachesAAOnTheFormBackgrounds() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Lingleaf/Views/Components.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let pattern = #"secondaryUIColor = dynamicUIColor\(light: UIColor\(white: ([0-9.]+), alpha: 1\), dark: UIColor\(white: ([0-9.]+), alpha: 1\)\)"#
        let match = try XCTUnwrap(text.range(of: pattern, options: .regularExpression), "Brand.secondaryUIColor changed shape")
        let numbers = text[match].components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .compactMap { Double($0) }.filter { $0 != 1 }
        XCTAssertEqual(numbers.count, 2, "expected the light and the dark grey in \(text[match])")
        let light = luminance(numbers[0], numbers[0], numbers[0]), dark = luminance(numbers[1], numbers[1], numbers[1])
        let byte = { (value: Double) in value / 255 }
        let backgrounds: [(String, Double, Double)] = [
            ("light card white", light, luminance(1, 1, 1)),
            ("light grouped #F2F2F7", light, luminance(byte(0xF2), byte(0xF2), byte(0xF7))),
            ("dark card #1C1C1E", dark, luminance(byte(0x1C), byte(0x1C), byte(0x1E))),
            ("dark grouped black", dark, luminance(0, 0, 0))
        ]
        for (name, foreground, background) in backgrounds {
            XCTAssertGreaterThanOrEqual(ratio(foreground, background), Glass.minimumContrast, "Brand.secondaryText on \(name)")
        }
    }
}
