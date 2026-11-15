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
    /// A finding is accepted only for one line of text (a label or a button), never for a container or a row.
    static let maxLeafHeight: CGFloat = 60
    /// At least this share of the element's height must lie inside the strip.
    static let minimumShareInStrip: CGFloat = 0.5

    /// The strip above the tab bar that the bar's blur reaches.
    static func zone(above tabBar: CGRect) -> CGRect {
        tabBar.isNull ? .null : CGRect(x: tabBar.minX, y: tabBar.minY - reach, width: tabBar.width, height: reach)
    }

    /// A label or a button of one line's height: the only elements whose text can be measured on its own.
    static func isTextLeaf(_ type: XCUIElement.ElementType, _ frame: CGRect) -> Bool {
        (type == .staticText || type == .button) && frame.height > 0 && frame.height <= maxLeafHeight
    }

    /// True for a text leaf lying mostly in the strip AND whose text, measured on the screenshot against its
    /// own local background, reaches WCAG AA. Anything else (no pixels, no ink, a container, low contrast) is false.
    static func isLegible(_ type: XCUIElement.ElementType, _ frame: CGRect, strip: CGRect, pixels: Pixels?) -> Bool {
        guard !strip.isNull, isTextLeaf(type, frame), let pixels else { return false }
        let inside = frame.intersection(strip)
        guard !inside.isNull, inside.height >= frame.height * minimumShareInStrip,
              let ratio = pixels.textContrast(in: frame) else { return false }
        return ratio >= minimumContrast
    }
}

/// The pixels of one screenshot, to measure what is really on screen.
struct Pixels {
    private let rgba: [UInt8]
    private let width: Int
    private let height: Int
    private let scale: CGFloat
    /// A pixel is text ("ink") when it differs from the local background by at least this contrast ratio;
    /// the blur's own gradient stays below it.
    private static let inkRatio = 1.25
    /// Blank space (points) that separates two things on one line (a cover and a title); a word gap is smaller.
    private static let separation: CGFloat = 8

    init(rgba: [UInt8], width: Int, height: Int, scale: CGFloat) {
        self.rgba = rgba
        self.width = width
        self.height = height
        self.scale = scale
    }

    init?(app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        guard window.width > 0, let image = app.screenshot().image.cgImage else { return nil }
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
        self.init(rgba: buffer, width: image.width, height: image.height, scale: CGFloat(image.width) / window.width)
    }

    /// The lowest contrast ratio of the text inside `frame` (points) against its local background: the background
    /// is the median of a ring of pixels just outside the frame; the text is every line (rows of ink) and, within a
    /// line, every block set apart by blank space, each at its own farthest pixel from the background. The result
    /// is the weakest of them, so a grey subtitle under a black title, or grey text beside a dark cover, fails.
    /// Nil when there is no ink or the frame cannot be measured.
    func textContrast(in frame: CGRect) -> Double? {
        let x0 = max(0, Int((frame.minX * scale).rounded(.down))), x1 = min(width, Int((frame.maxX * scale).rounded(.up)))
        let y0 = max(0, Int((frame.minY * scale).rounded(.down))), y1 = min(height, Int((frame.maxY * scale).rounded(.up)))
        guard x1 - x0 >= 4, y1 - y0 >= 4, let background = ringMedian(x0, x1, y0, y1) else { return nil }
        var worst: Double?
        var rowsWithInk: [Bool] = []
        for y in y0..<y1 {
            rowsWithInk.append((x0..<x1).contains { Self.ratio(luminance($0, y), background) >= Self.inkRatio })
        }
        var top: Int?
        for (offset, hasInk) in (rowsWithInk + [false]).enumerated() {
            if hasInk, top == nil { top = offset }
            if !hasInk, let start = top {
                let weakest = weakestBlock(rows: (y0 + start)..<(y0 + offset), x0, x1, background)
                if let weakest { worst = min(worst ?? weakest, weakest) }
                top = nil
            }
        }
        return worst
    }

    /// Within a line, the weakest of its blocks (runs of columns with ink, set apart by blank space).
    private func weakestBlock(rows: Range<Int>, _ x0: Int, _ x1: Int, _ background: Double) -> Double? {
        let gap = max(1, Int((Self.separation * scale).rounded()))
        var worst: Double?
        var best = 0.0, blank = 0, inBlock = false
        func close() {
            if inBlock { worst = min(worst ?? best, best) }
            best = 0; blank = 0; inBlock = false
        }
        for x in x0..<x1 {
            let column = rows.map { Self.ratio(luminance(x, $0), background) }.max() ?? 1
            if column >= Self.inkRatio {
                inBlock = true; blank = 0; best = max(best, column)
            } else if inBlock {
                blank += 1
                if blank >= gap { close() }
            }
        }
        close()
        return worst
    }

    private func ringMedian(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int) -> Double? {
        let ring = max(1, Int(scale.rounded(.up)))
        var around: [Double] = []
        for y in max(0, y0 - ring)..<min(height, y1 + ring) {
            for x in max(0, x0 - ring)..<min(width, x1 + ring) where !(x >= x0 && x < x1 && y >= y0 && y < y1) {
                around.append(luminance(x, y))
            }
        }
        guard around.count >= 8 else { return nil }
        return around.sorted()[around.count / 2]
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
