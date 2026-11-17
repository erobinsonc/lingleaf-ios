import XCTest

/// The measurement behind the audit's glass-strip rule, on synthetic bitmaps (no app, no simulator state).
final class GlassContrastTests: XCTestCase {
    private typealias Block = (rect: CGRect, grey: UInt8)

    /// A bitmap at scale 1: `background` grey (by row), then each block painted over it, in order.
    private func bitmap(_ blocks: [Block], origin: CGPoint = .zero, background: (Int) -> UInt8 = { _ in 255 }) -> Pixels {
        let width = 300, height = 120
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width { set(&rgba, width, x, y, background(y)) }
        }
        for block in blocks {
            for y in Int(block.rect.minY)..<Int(block.rect.maxY) {
                for x in Int(block.rect.minX)..<Int(block.rect.maxX) { set(&rgba, width, x, y, block.grey) }
            }
        }
        return Pixels(rgba: rgba, width: width, height: height, scale: 1, origin: origin)
    }

    private func set(_ rgba: inout [UInt8], _ width: Int, _ x: Int, _ y: Int, _ grey: UInt8) {
        let index = (y * width + x) * 4
        rgba[index] = grey
        rgba[index + 1] = grey
        rgba[index + 2] = grey
        rgba[index + 3] = 255
    }

    private let black: UInt8 = 0
    private let grey999: UInt8 = 0x99
    private let text = CGRect(x: 60, y: 40, width: 100, height: 10)
    private let frame = CGRect(x: 50, y: 35, width: 120, height: 20)
    private func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    func testBlackTextOnWhitePasses() throws {
        let ratio = try XCTUnwrap(bitmap([(text, black)]).textContrast(in: frame))
        XCTAssertGreaterThanOrEqual(ratio, Glass.minimumContrast)
    }

    func testLightGreyTextOnWhiteFails() throws {
        let ratio = try XCTUnwrap(bitmap([(text, grey999)]).textContrast(in: frame))
        XCTAssertLessThan(ratio, Glass.minimumContrast, "#999 on white is 2.85:1")
    }

    func testBlackTitleWithGreySubtitleInTheSameFrameFails() throws {
        let pixels = bitmap([(rect(60, 35, 100, 10), black), (rect(60, 52, 100, 10), grey999)])
        let ratio = try XCTUnwrap(pixels.textContrast(in: rect(50, 30, 120, 40)))
        XCTAssertLessThan(ratio, Glass.minimumContrast, "the weakest line decides, not the strongest pixel")
    }

    func testGreyTextBesideADarkCoverFailsAndBlackTextBesideItPasses() throws {
        let cover = (rect(10, 20, 44, 62), black), wide = rect(10, 20, 200, 62)
        let grey = try XCTUnwrap(bitmap([cover, (rect(70, 40, 120, 10), grey999)]).textContrast(in: wide))
        XCTAssertLessThan(grey, Glass.minimumContrast, "a cover must not vouch for the text next to it")
        let dark = try XCTUnwrap(bitmap([cover, (rect(70, 40, 120, 10), black)]).textContrast(in: wide))
        XCTAssertGreaterThanOrEqual(dark, Glass.minimumContrast)
    }

    func testFaintTextBesideStrongTextFails() throws {
        let pixels = bitmap([(rect(60, 40, 40, 10), black), (rect(130, 40, 40, 10), 0xEA)])
        let ratio = try XCTUnwrap(pixels.textContrast(in: frame))
        XCTAssertLessThan(ratio, Glass.minimumContrast, "#eaeaea on white is 1.2:1: faint is not invisible")
    }

    func testGreyTextSixPointsFromBlackTextFails() throws {
        let pixels = bitmap([(rect(60, 40, 50, 10), black), (rect(116, 40, 50, 10), grey999)])
        let ratio = try XCTUnwrap(pixels.textContrast(in: frame))
        XCTAssertLessThan(ratio, Glass.minimumContrast, "a 6 pt gap separates two blocks; the grey one counts")
    }

    func testADarkOrnamentTouchingGreyTextDoesNotVouchForIt() throws {
        let pixels = bitmap([(rect(60, 40, 4, 10), black), (rect(67, 40, 100, 10), grey999)])
        let ratio = try XCTUnwrap(pixels.textContrast(in: frame))
        XCTAssertLessThan(ratio, Glass.minimumContrast, "3 pt apart is one block: a few dark columns do not decide it")
    }

    func testADarkRingAroundGreyTextIsNotAnAcceptableBackground() {
        let pixels = bitmap([(rect(47, 32, 126, 26), black), (frame, 255), (rect(60, 40, 100, 10), grey999)])
        XCTAssertNil(pixels.textContrast(in: frame), "outside black, inside white: not one background")
        XCTAssertFalse(Glass.isLegible(.staticText, frame, strip: rect(0, 30, 300, 40), pixels: pixels))
    }

    func testTheBlursGradientIsNotTextAndBlackTextOnItPasses() throws {
        let gradient: (Int) -> UInt8 = { UInt8(255 - $0 / 3) }
        XCTAssertNil(bitmap([], background: gradient).textContrast(in: frame), "no ink: nothing to accept")
        let ratio = try XCTUnwrap(bitmap([(text, black)], background: gradient).textContrast(in: frame))
        XCTAssertGreaterThanOrEqual(ratio, Glass.minimumContrast)
    }

    func testLabelsOnADarkFillAreMeasuredAgainstTheFill() throws {
        let fill = (rect(40, 25, 140, 40), UInt8(0x22)), inside = rect(50, 30, 120, 25)
        let grey = try XCTUnwrap(bitmap([fill, (rect(60, 40, 100, 10), 0x55)]).textContrast(in: inside))
        XCTAssertLessThan(grey, Glass.minimumContrast, "#555 on #222 is about 2:1")
        let light = try XCTUnwrap(bitmap([fill, (rect(60, 40, 100, 10), 255)]).textContrast(in: inside))
        XCTAssertGreaterThanOrEqual(light, Glass.minimumContrast)
    }

    func testALabelOnItsOwnTintedChipIsNotMeasuredAgainstThePage() {
        let chip = rect(60, 38, 40, 18)    // frame == chip: white page outside, tint inside
        let pixels = bitmap([(chip, 0xC8), (rect(68, 42, 24, 8), 0x40)])
        XCTAssertNil(pixels.textContrast(in: chip), "outside white, inside tint: not one background, so no verdict")
    }

    func testTheFramesOriginIsSubtractedBeforeMeasuring() throws {
        let pixels = bitmap([(text, black)], origin: CGPoint(x: 100, y: 50))
        let ratio = try XCTUnwrap(pixels.textContrast(in: frame.offsetBy(dx: 100, dy: 50)))
        XCTAssertGreaterThanOrEqual(ratio, Glass.minimumContrast)
    }

    func testNoPixelsOrAnEmptyFrameFailsClosed() {
        let strip = rect(0, 20, 300, 60)
        XCTAssertFalse(Glass.isLegible(.staticText, frame, strip: strip, pixels: nil))
        XCTAssertNil(bitmap([(text, black)]).textContrast(in: rect(500, 500, 10, 10)))
        XCTAssertFalse(Glass.isLegible(.staticText, frame, strip: .null, pixels: bitmap([(text, black)])))
    }

    func testOnlyOneLabelMostlyInsideTheStripIsAccepted() {
        let pixels = bitmap([(text, black)])
        let strip = rect(0, 30, 300, 40)
        XCTAssertTrue(Glass.isLegible(.staticText, frame, strip: strip, pixels: pixels))
        XCTAssertFalse(Glass.isLegible(.button, frame, strip: strip, pixels: pixels), "a button's fill is not its label")
        XCTAssertFalse(Glass.isLegible(.other, frame, strip: strip, pixels: pixels), "a container is not text")
        XCTAssertFalse(Glass.isLegible(.staticText, rect(0, 0, 300, 80), strip: strip, pixels: pixels), "too tall")
        XCTAssertFalse(Glass.isLegible(.staticText, frame, strip: rect(0, 50, 300, 40), pixels: pixels), "a quarter in the strip")
    }

    func testUnderTheBarOnlyWhatTheBlurCoversIsExempt() {
        let strip = rect(0, 70, 300, 24)
        let tall = rect(40, 10, 140, 100)   // a combined row that reaches into the bar
        let above = bitmap([(rect(60, 20, 100, 10), black)])
        XCTAssertTrue(Glass.isExemptUnderBar(tall, strip: strip, pixels: above), "black text above the strip")
        let grey = bitmap([(rect(60, 20, 100, 10), grey999), (rect(60, 80, 100, 10), black)])
        XCTAssertFalse(Glass.isExemptUnderBar(tall, strip: strip, pixels: grey), "grey text 50 pt above the blur is reported")
        let underBlur = bitmap([(rect(60, 80, 100, 10), grey999)])
        XCTAssertTrue(Glass.isExemptUnderBar(tall, strip: strip, pixels: underBlur), "text only under the blur: nothing to measure above")
        XCTAssertTrue(Glass.isExemptUnderBar(rect(50, 75, 100, 15), strip: strip, pixels: nil), "wholly inside the strip")
        XCTAssertFalse(Glass.isExemptUnderBar(tall, strip: strip, pixels: nil), "a part above the strip and no pixels: not exempt")
        XCTAssertEqual(Glass.partAboveStrip(tall, strip: strip), rect(40, 10, 140, 60))
        XCTAssertNil(Glass.partAboveStrip(rect(50, 68, 100, 15), strip: strip), "2 pt above the strip is too little to measure")
    }

    func testAFilledCoverAboveTheStripHasNoTextToMeasure() {
        let cover = rect(10, 20, 44, 62)
        let pixels = bitmap([(cover, black)])
        XCTAssertNil(pixels.textContrast(in: cover), "strict: the fill is not a background of its own")
        XCTAssertNil(pixels.textContrast(in: cover, strict: false), "the fill is its own background: no ink")
        XCTAssertTrue(Glass.isExemptUnderBar(cover, strip: rect(0, 70, 300, 24), pixels: pixels))
    }

    func testTextOnGreySurfaceBesideAWhiteCellIsMeasuredAgainstTheSurface() throws {
        let surface = (rect(0, 30, 300, 90), UInt8(0xE0)), part = rect(20, 30, 200, 40)   // part touches the white above
        let strong = try XCTUnwrap(bitmap([surface, (rect(30, 45, 120, 10), black)]).textContrast(in: part, strict: false))
        XCTAssertGreaterThanOrEqual(strong, Glass.minimumContrast)
        let weak = try XCTUnwrap(bitmap([surface, (rect(30, 45, 120, 10), grey999)]).textContrast(in: part, strict: false))
        XCTAssertLessThan(weak, Glass.minimumContrast, "#999 on #e0e0e0 is about 2.2:1")
    }
}
