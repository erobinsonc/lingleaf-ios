import XCTest

/// The measurement behind the audit's glass-strip rule, on synthetic bitmaps (no app, no simulator state).
final class GlassContrastTests: XCTestCase {
    private typealias Block = (rect: CGRect, grey: UInt8)

    /// A bitmap at scale 1: `background` grey, then each block painted over it.
    private func bitmap(_ blocks: [Block], width: Int = 300, height: Int = 120, background: (Int) -> UInt8 = { _ in 255 }) -> Pixels {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width { set(&rgba, width, x, y, background(y)) }
        }
        for block in blocks {
            for y in Int(block.rect.minY)..<Int(block.rect.maxY) {
                for x in Int(block.rect.minX)..<Int(block.rect.maxX) { set(&rgba, width, x, y, block.grey) }
            }
        }
        return Pixels(rgba: rgba, width: width, height: height, scale: 1)
    }

    private func set(_ rgba: inout [UInt8], _ width: Int, _ x: Int, _ y: Int, _ grey: UInt8) {
        let index = (y * width + x) * 4
        rgba[index] = grey; rgba[index + 1] = grey; rgba[index + 2] = grey; rgba[index + 3] = 255
    }

    private let black: UInt8 = 0
    private let grey999: UInt8 = 0x99
    private let text = CGRect(x: 60, y: 40, width: 100, height: 10)
    private let frame = CGRect(x: 50, y: 35, width: 120, height: 20)

    func testBlackTextOnWhitePasses() throws {
        let ratio = try XCTUnwrap(bitmap([(text, black)]).textContrast(in: frame))
        XCTAssertGreaterThanOrEqual(ratio, Glass.minimumContrast)
    }

    func testLightGreyTextOnWhiteFails() throws {
        let ratio = try XCTUnwrap(bitmap([(text, grey999)]).textContrast(in: frame))
        XCTAssertLessThan(ratio, Glass.minimumContrast, "#999 on white is 2.85:1")
    }

    func testBlackTitleWithGreySubtitleInTheSameFrameFails() throws {
        let title = CGRect(x: 60, y: 35, width: 100, height: 10), subtitle = CGRect(x: 60, y: 52, width: 100, height: 10)
        let ratio = try XCTUnwrap(bitmap([(title, black), (subtitle, grey999)]).textContrast(in: CGRect(x: 50, y: 30, width: 120, height: 40)))
        XCTAssertLessThan(ratio, Glass.minimumContrast, "the weakest line decides, not the strongest pixel")
    }

    func testGreyTextBesideADarkCoverFails() throws {
        let cover = CGRect(x: 10, y: 20, width: 44, height: 62), grey = CGRect(x: 70, y: 40, width: 120, height: 10)
        let ratio = try XCTUnwrap(bitmap([(cover, black), (grey, grey999)]).textContrast(in: CGRect(x: 10, y: 20, width: 200, height: 62)))
        XCTAssertLessThan(ratio, Glass.minimumContrast, "a cover must not vouch for the text next to it")
    }

    func testBlackTextBesideADarkCoverPasses() throws {
        let cover = CGRect(x: 10, y: 20, width: 44, height: 62), black2 = CGRect(x: 70, y: 40, width: 120, height: 10)
        let ratio = try XCTUnwrap(bitmap([(cover, black), (black2, black)]).textContrast(in: CGRect(x: 10, y: 20, width: 200, height: 62)))
        XCTAssertGreaterThanOrEqual(ratio, Glass.minimumContrast)
    }

    func testTheBlursGradientIsNotTextAndBlackTextOnItPasses() throws {
        let gradient: (Int) -> UInt8 = { UInt8(255 - $0 / 3) }   // white fading to 0.84 over 120 rows
        XCTAssertNil(bitmap([], background: gradient).textContrast(in: frame), "no ink: nothing to accept")
        let ratio = try XCTUnwrap(bitmap([(text, black)], background: gradient).textContrast(in: frame))
        XCTAssertGreaterThanOrEqual(ratio, Glass.minimumContrast)
    }

    func testNoPixelsOrAnEmptyFrameFailsClosed() {
        let strip = CGRect(x: 0, y: 20, width: 300, height: 60)
        XCTAssertFalse(Glass.isLegible(.staticText, frame, strip: strip, pixels: nil))
        XCTAssertNil(bitmap([(text, black)]).textContrast(in: CGRect(x: 500, y: 500, width: 10, height: 10)))
        XCTAssertFalse(Glass.isLegible(.staticText, frame, strip: .null, pixels: bitmap([(text, black)])))
    }

    func testOnlyOneLineOfTextMostlyInsideTheStripIsAccepted() {
        let pixels = bitmap([(text, black)])
        let strip = CGRect(x: 0, y: 30, width: 300, height: 40)
        XCTAssertTrue(Glass.isLegible(.staticText, frame, strip: strip, pixels: pixels))
        XCTAssertTrue(Glass.isLegible(.button, frame, strip: strip, pixels: pixels))
        XCTAssertFalse(Glass.isLegible(.other, frame, strip: strip, pixels: pixels), "a container is not text")
        XCTAssertFalse(Glass.isLegible(.staticText, CGRect(x: 0, y: 0, width: 300, height: 80), strip: strip, pixels: pixels), "too tall")
        XCTAssertFalse(Glass.isLegible(.staticText, frame, strip: CGRect(x: 0, y: 50, width: 300, height: 40), pixels: pixels),
                       "only a quarter of the frame is in the strip")
    }
}
