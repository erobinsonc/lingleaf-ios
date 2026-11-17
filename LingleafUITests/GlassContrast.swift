import XCTest

/// The strip above the translucent tab bar, where the audit reports false contrast findings, and what
/// accepting one there takes. Kept apart from the audit so the measurement has its own tests
/// (`GlassContrastTests`, on synthetic bitmaps).
enum Glass {
    /// How far above the tab bar's frame the glass backdrop and the scroll-edge blur reach, in points.
    /// Measured only in portrait, light appearance and the default text size, on the Library screen
    /// (CI simulator, iOS 26, run 43677625249): a row's background starts to change 23 pt above the bar
    /// (white 1.00 at 765 pt, 0.98 at 771, 0.96 at 777, 0.92 at 789; the bar starts at 791).
    static let reach: CGFloat = 24
    /// WCAG AA for normal text. Applied to all text here, which is stricter than the 3:1 of large text.
    static let minimumContrast = 4.5
    /// A finding is accepted only for one line of text (a label), never for a container or a row.
    static let maxLeafHeight: CGFloat = 60
    /// At least this share of the element's height must lie inside the strip.
    static let minimumShareInStrip: CGFloat = 0.5

    /// The strip above the tab bar that the bar's blur reaches.
    static func zone(above tabBar: CGRect) -> CGRect {
        tabBar.isNull ? .null : CGRect(x: tabBar.minX, y: tabBar.minY - reach, width: tabBar.width, height: reach)
    }

    /// A label of one line's height: the only element whose text can be measured on its own. A button is not:
    /// its fill would be measured as text, and its label never on its own.
    static func isTextLeaf(_ type: XCUIElement.ElementType, _ frame: CGRect) -> Bool {
        type == .staticText && frame.height > 0 && frame.height <= maxLeafHeight
    }

    /// The part of `frame` that lies above the blur strip: the only part whose pixels the blur has not touched.
    static func partAboveStrip(_ frame: CGRect, strip: CGRect) -> CGRect? {
        guard !strip.isNull else { return nil }
        let height = min(frame.maxY, strip.minY) - frame.minY
        return height >= 4 ? CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: height) : nil
    }

    /// True for a label lying mostly in the strip AND whose text, measured on the screenshot against its own local
    /// background, reaches WCAG AA. Anything else (no pixels, no ink, a container, low contrast) is false.
    static func isLegible(_ type: XCUIElement.ElementType, _ frame: CGRect, strip: CGRect, pixels: Pixels?) -> Bool {
        guard !strip.isNull, isTextLeaf(type, frame), let pixels else { return false }
        let inside = frame.intersection(strip)
        guard !inside.isNull, inside.height >= frame.height * minimumShareInStrip,
              let ratio = pixels.textContrast(in: frame) else { return false }
        return ratio >= minimumContrast
    }

    /// Whether a finding on an element that touches the tab bar may be set aside. Only what lies under the blur is
    /// exempt: the part above the strip is measured like any text, and an element with weak ink there is reported.
    /// No part above the strip, or no ink in it (text only under the blur), keeps the exemption.
    static func isExemptUnderBar(_ frame: CGRect, strip: CGRect, pixels: Pixels?) -> Bool {
        guard let part = partAboveStrip(frame, strip: strip) else { return true }
        guard let pixels else { return false }
        // Not strict: a cover or an image has no "own background" to agree with; any ink above the strip
        // still has to reach 4.5:1 against the median of the ring around it.
        guard let ratio = pixels.textContrast(in: part, strict: false) else { return true }
        return ratio >= minimumContrast
    }
}

/// The pixels of one screenshot, to measure what is really on screen.
struct Pixels {
    private let rgba: [UInt8]
    private let width: Int
    private let height: Int
    private let scale: CGFloat
    /// Where the screenshot's top left corner lies in the coordinates of element frames. CI runs on iPhone only,
    /// where the window is the screen; the origin keeps a windowed iPad right as well.
    private let origin: CGPoint
    /// A pixel is text ("ink") when it differs from the local background by at least this contrast ratio.
    /// (The blur's gradient measures about 1.07 against its median; faint text, from 1.12, counts and fails.)
    private static let inkRatio = 1.12
    /// Blank space (points) that separates two things on one line (a cover and a title, or a black word and a
    /// grey one). Words of the same text split too, and measure the same, so a narrow gap costs nothing.
    private static let separation: CGFloat = 5
    /// The background must be one thing: the ring outside the frame and the border inside it agree on its
    /// luminance (a dark ring or ornament around grey text would otherwise become the "background"). A label whose
    /// frame is its own tinted chip (a level badge: 0.2 apart on CI) is therefore not measured, not misjudged.
    private static let backgroundAgreement = 0.08
    /// Share of the ring that must lie within `backgroundAgreement` of its median (the blur's gradient does).
    private static let homogeneousShare = 0.9
    /// A block of text counts at this percentile of its ink pixels' ratios (the value reached by the strongest
    /// quarter of them: the strokes, not their anti-aliased edges), so that a few dark pixels (an ornament, a stray
    /// mark) merged into a block of grey text cannot vouch for the block.
    static let blockPercentile = 0.75

    init(rgba: [UInt8], width: Int, height: Int, scale: CGFloat, origin: CGPoint = .zero) {
        self.rgba = rgba
        self.width = width
        self.height = height
        self.scale = scale
        self.origin = origin
    }

    /// Fails (nil) when the screenshot's scale on the vertical axis differs from the horizontal one by more than 1%:
    /// then the frames of elements would not land on the right pixels.
    init?(app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        guard window.width > 0, window.height > 0, let image = app.screenshot().image.cgImage else { return nil }
        let scale = CGFloat(image.width) / window.width
        guard abs(CGFloat(image.height) / window.height - scale) <= scale * 0.01 else { return nil }
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        self.init(rgba: buffer, width: image.width, height: image.height, scale: scale, origin: window.origin)
    }

    /// The lowest contrast ratio of the text inside `frame` (points) against its local background: the background
    /// is the median of a ring of pixels just outside the frame, which must be homogeneous and agree with the
    /// frame's own border; the text is every line (rows of ink) and, within a line, every block set apart by blank
    /// space, each at the low end of its columns' strongest pixels. The result is the weakest of them, so a grey
    /// subtitle under a black title, or grey text beside a dark cover, fails.
    /// Nil when there is no ink, the background is not one thing (only when `strict`), or the frame cannot be measured.
    /// `percentile` is where in a block's ink pixels the block is read (default 0.75, so decoys cannot vouch);
    /// 1 reads the strongest pixel, the most generous reading, for checks that must not raise false alarms.
    func textContrast(in frame: CGRect, strict: Bool = true, percentile: Double = blockPercentile) -> Double? {
        let x0 = max(0, Int(((frame.minX - origin.x) * scale).rounded(.down)))
        let x1 = min(width, Int(((frame.maxX - origin.x) * scale).rounded(.up)))
        let y0 = max(0, Int(((frame.minY - origin.y) * scale).rounded(.down)))
        let y1 = min(height, Int(((frame.maxY - origin.y) * scale).rounded(.up)))
        guard x1 - x0 >= 4, y1 - y0 >= 4, let background = background(x0, x1, y0, y1, strict: strict) else { return nil }
        var worst: Double?
        var rowsWithInk: [Bool] = []
        for y in y0..<y1 {
            rowsWithInk.append((x0..<x1).contains { Self.ratio(luminance($0, y), background) >= Self.inkRatio })
        }
        var top: Int?
        for (offset, hasInk) in (rowsWithInk + [false]).enumerated() {
            if hasInk, top == nil { top = offset }
            if !hasInk, let start = top {
                let weakest = weakestBlock(rows: (y0 + start)..<(y0 + offset), x0, x1, background, percentile)
                if let weakest { worst = min(worst ?? weakest, weakest) }
                top = nil
            }
        }
        return worst
    }

    /// Within a line, the weakest of its blocks (runs of columns with ink, set apart by blank space).
    private func weakestBlock(rows: Range<Int>, _ x0: Int, _ x1: Int, _ background: Double, _ percentile: Double) -> Double? {
        let gap = max(1, Int((Self.separation * scale).rounded()))
        var worst: Double?
        var inkPixels: [Double] = []
        var blank = 0
        func close() {
            if !inkPixels.isEmpty {
                let value = inkPixels.sorted()[Int(Double(inkPixels.count - 1) * percentile)]
                worst = min(worst ?? value, value)
            }
            inkPixels = []
            blank = 0
        }
        for x in x0..<x1 {
            let column = rows.map { Self.ratio(luminance(x, $0), background) }.filter { $0 >= Self.inkRatio }
            if !column.isEmpty {
                inkPixels += column
                blank = 0
            } else if !inkPixels.isEmpty {
                blank += 1
                if blank >= gap { close() }
            }
        }
        close()
        return worst
    }

    /// The background luminance: median of the ring outside the frame, only if the ring is homogeneous and the
    /// frame's inner border agrees with it.
    private func background(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, strict: Bool) -> Double? {
        let ring = max(1, Int(scale.rounded(.up)))
        var around: [Double] = []
        for y in max(0, y0 - ring)..<min(height, y1 + ring) {
            for x in max(0, x0 - ring)..<min(width, x1 + ring) where !(x >= x0 && x < x1 && y >= y0 && y < y1) {
                around.append(luminance(x, y))
            }
        }
        var border: [Double] = []
        for y in y0..<y1 {
            for x in x0..<x1 where x < x0 + ring || x >= x1 - ring || y < y0 + ring || y >= y1 - ring {
                border.append(luminance(x, y))
            }
        }
        guard around.count >= 8, border.count >= 8 else { return nil }
        let outside = around.sorted()[around.count / 2], inside = border.sorted()[border.count / 2]
        guard strict else { return outside }
        let agreeing = around.filter { abs($0 - outside) <= Self.backgroundAgreement }.count
        guard Double(agreeing) >= Double(around.count) * Self.homogeneousShare,
              abs(outside - inside) <= Self.backgroundAgreement else { return nil }
        return outside
    }

    private static func ratio(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func luminance(_ x: Int, _ y: Int) -> Double {
        func channel(_ byte: UInt8) -> Double {
            let value = Double(byte) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let index = (y * width + x) * 4
        return 0.2126 * channel(rgba[index]) + 0.7152 * channel(rgba[index + 1]) + 0.0722 * channel(rgba[index + 2])
    }
}
