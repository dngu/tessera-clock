import ScreenSaver
import AppKit

// Native port of index.html. A web view stays blank inside macOS's screensaver
// host, so the screensaver draws the same piece with Core Graphics. Keep the
// numbers, fonts and movements here in step with index.html.

private let tau = CGFloat.pi * 2
private let U: CGFloat = 0, R = CGFloat.pi / 2, D = CGFloat.pi, L = CGFloat.pi * 1.5

// MARK: - Tuning (mirrors TUNE in index.html)

private enum Tune {
    static let handLen: CGFloat = 0.40      // < 0.5 so neighbouring hands never touch
    static let handWeight: CGFloat = 0.070
    static let faceRadius: CGFloat = 0.47
    static let recessDepth: CGFloat = 0.045   // how deep the faces look, in clock pitches
    static let shadowOffset: CGFloat = 0.9   // in hand widths
    static let shadowBlur: CGFloat = 1.6
    static let springK: CGFloat = 13
    static let springC: CGFloat = 2 * sqrt(13)   // critically damped
    static let maxSpeed: CGFloat = 2.3
    static let timeHold: Double = 16
    static let patternHold: Double = 11
    static let ripple: Double = 0.10
    static let sweep: Double = 0.13
    static let jitter: Double = 0.45
    static let dimmed: CGFloat = 0.12     // how much of the clock shows behind the password prompt
    static let wakeIdle: Double = 0.6     // input this recent means someone is waking the Mac
    static let restIdle: Double = 15      // no input for this long: show the clock fully again
    static let fadeRate: Double = 4       // fade speed (per second)
}

// MARK: - Numerals

private let glyph: [Character: (CGFloat, CGFloat)] = [
    "┌": (R, D), "┐": (L, D), "└": (U, R), "┘": (U, L), "│": (U, D), "─": (L, R),
    "╶": (R, R), "╴": (L, L), "╵": (U, U), "╷": (D, D),
]

private struct Font { let w: Int, h: Int; let glyphs: [[String]] }

private let compactFont = Font(w: 2, h: 3, glyphs: [
    ["┌┐", "││", "└┘"], [" ╷", " │", " ╵"], ["╶┐", "┌┘", "└╴"], ["╶┐", "╶┘", "╶┘"],
    ["╷╷", "└│", " ╵"], ["┌╴", "└┐", "╶┘"], ["┌╴", "│┐", "└┘"], ["╶┐", " │", " ╵"],
    ["┌┐", "└┘", "└┘"], ["┌┐", "└│", "╶┘"],
])
private let denseFont = Font(w: 3, h: 5, glyphs: [
    ["┌─┐", "│ │", "│ │", "│ │", "└─┘"], ["  ╷", "  │", "  │", "  │", "  ╵"],
    ["╶─┐", "  │", "┌─┘", "│  ", "└─╴"], ["╶─┐", "  │", "╶─┘", "  │", "╶─┘"],
    ["╷ ╷", "│ │", "└─│", "  │", "  ╵"], ["┌─╴", "│  ", "└─┐", "  │", "╶─┘"],
    ["┌─╴", "│  ", "│─┐", "│ │", "└─┘"], ["╶─┐", "  │", "  │", "  │", "  ╵"],
    ["┌─┐", "│ │", "│─│", "│ │", "└─┘"], ["┌─┐", "│ │", "└─│", "  │", "╶─┘"],
])

// Panel numerals: solid seven-segment shapes on a 3×5 bitmap, drawn as the
// outline of the filled blocks. The bitmap's corners are the clock centres, so
// each numeral is 4 × 6 clocks and every hand is horizontal or vertical.
private let blockBitmaps: [[String]] = [
    ["111", "101", "101", "101", "111"], ["001", "001", "001", "001", "001"],
    ["111", "001", "111", "100", "111"], ["111", "001", "111", "001", "111"],
    ["101", "101", "111", "001", "001"], ["111", "100", "111", "001", "111"],
    ["111", "100", "111", "101", "111"], ["111", "001", "001", "001", "001"],
    ["111", "101", "111", "101", "111"], ["111", "101", "111", "001", "111"],
]
private let blockDigits: [[[(CGFloat, CGFloat)?]]] = blockBitmaps.map { bitmap in
    let px = bitmap.map { Array($0) }
    func on(_ r: Int, _ c: Int) -> Bool { r >= 0 && r < 5 && c >= 0 && c < 3 && px[r][c] == "1" }
    return (0..<6).map { r in
        (0..<4).map { c in
            var dirs: [CGFloat] = []
            if on(r - 1, c - 1) != on(r - 1, c) { dirs.append(U) }
            if on(r - 1, c) != on(r, c) { dirs.append(R) }
            if on(r, c - 1) != on(r, c) { dirs.append(D) }
            if on(r - 1, c - 1) != on(r, c - 1) { dirs.append(L) }
            return dirs.count == 2 ? (dirs[0], dirs[1]) : nil
        }
    }
}
private let blockSpans: [(Int, Int)] = blockBitmaps.map { bitmap in
    let inked = (0..<3).filter { c in bitmap.contains { Array($0)[c] == "1" } }
    return (inked.first!, inked.last! - inked.first! + 2)
}
private enum Panel {
    static let rows = 8                       // 6-clock numerals with a row above and below
    static let digitColumns = [0, 5, 10, 15]  // 4-clock numerals, one clock apart
    static let digitsWidth = 19
    static let minCols = 21
    static let handLen: CGFloat = 0.47        // longer hands: strokes nearly join into blocks
}

// MARK: - Varieties (mirrors VARIETIES in index.html)

private struct Grid { let n: Int; let font: Font; let columns: [Int] }
private let grids: [String: Grid] = [
    "compact": Grid(n: 9, font: compactFont, columns: [0, 2, 5, 7]),
    "dense": Grid(n: 15, font: denseFont, columns: [0, 4, 8, 12]),
]

private struct Surface {
    let wall: NSColor, disc: (NSColor, NSColor), rim: NSColor, face: NSColor, well: NSColor, inner: NSColor,
        hand: NSColor, cast: NSColor
}
private func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
            blue: CGFloat(v & 255) / 255, alpha: 1)
}
private func ink(_ w: CGFloat, _ a: CGFloat) -> NSColor { NSColor(white: w, alpha: a) }
private let surfaces: [String: Surface] = [
    "plaster": Surface(wall: hex(0xe6e5e2), disc: (hex(0xbcbcba), hex(0xa8a8a6)), rim: ink(0, 0.30),
                       face: ink(1, 0.45), well: ink(0, 0.05), inner: ink(0, 0.45), hand: hex(0x0c0c0d), cast: ink(0, 0.38)),
    "bone": Surface(wall: hex(0x24231f), disc: (hex(0xf1eee6), hex(0xdedacf)), rim: ink(0, 0.65),
                    face: ink(1, 0.9), well: ink(0, 0.035), inner: ink(0, 0.30), hand: hex(0x161513), cast: ink(0, 0.30)),
    "noir": Surface(wall: hex(0x040405), disc: (hex(0x19191c), hex(0x0d0d0f)), rim: ink(0, 0.9),
                    face: ink(1, 0.10), well: ink(0, 0.22), inner: ink(0, 0.95), hand: hex(0xf3f1ea), cast: ink(0, 0.95)),
]

// MARK: - Clocks

private func wrap(_ x: CGFloat) -> CGFloat {
    var x = x.truncatingRemainder(dividingBy: tau)
    if x > .pi { x -= tau } else if x < -.pi { x += tau }
    return x
}

private struct Hand {
    var pos: CGFloat, vel: CGFloat = 0
    mutating func step(_ target: CGFloat, _ dt: CGFloat) {
        let acc = Tune.springK * wrap(target - pos) - Tune.springC * vel
        vel = max(-Tune.maxSpeed, min(Tune.maxSpeed, vel + acc * dt))
        pos += vel * dt
    }
}

private typealias Movement = (Clock, Double) -> (CGFloat, CGFloat)

private final class Clock {
    let gx: Int, gy: Int, x: CGFloat, y: CGFloat, rr: CGFloat, a: CGFloat
    var h = Hand(pos: 0), m = Hand(pos: 0)
    var fn: Movement, next: Movement?, switchAt: Double = 0
    init(gx: Int, gy: Int, x: CGFloat, y: CGFloat, fn: @escaping Movement, t: Double) {
        self.gx = gx; self.gy = gy; self.x = x; self.y = y
        rr = hypot(x, y); a = atan2(x, -y)
        self.fn = fn
        let (hh, mm) = fn(self, t); h.pos = hh; m.pos = mm
    }
}

// MARK: - Movements

private func chevrons(_ c: Clock, _ t: Double) -> (CGFloat, CGFloat) {
    let open = 0.25 + 1.15 * (0.5 + 0.5 * sin(CGFloat(t) * 0.5 - c.rr * 0.55))
    return (c.a + .pi - open, c.a + .pi + open)
}
private func rings(_ c: Clock, _ t: Double) -> (CGFloat, CGFloat) {
    let twist = 0.7 * sin(CGFloat(t) * 0.45 - c.rr * 0.6)
    return (c.a + R + twist, c.a - R + twist)
}
private func wave(_ c: Clock, _ t: Double) -> (CGFloat, CGFloat) {
    let th = CGFloat(t) * 0.32 + c.x * 0.30 + 0.35 * sin(c.y * 0.5 + CGFloat(t) * 0.4)
    return (th, th + .pi)
}
private func weave(_ c: Clock, _ t: Double) -> (CGFloat, CGFloat) {
    let dir: CGFloat = (c.gx + c.gy) & 1 == 1 ? 1 : -1
    let th = dir * CGFloat(t) * 0.30 + (c.x + c.y) * .pi * 0.25
    return (th, th + R)
}
private let programme: [[Movement]] = [[chevrons, rings], [wave, weave], [rings, wave], [weave, chevrons]]

@objc(TesseraClockView)
final class TesseraClockView: ScreenSaverView {

    // key, label, options (value, label) — first option is the default
    private static let varieties: [(key: String, label: String, options: [(String, String)])] = [
        ("shape", "Shape", [("alternate", "Alternate"), ("round", "Round"), ("panel", "Wide panel")]),
        ("grid", "Round grid", [("compact", "Compact"), ("dense", "Dense")]),
        ("surface", "Surface", [("noir", "Noir"), ("plaster", "Plaster"), ("bone", "Bone")]),
        ("around", "Around the time", [("still", "Still"), ("drift", "Drifting")]),
    ]

    private let bundle = Bundle(for: TesseraClockView.self)
    // One shared instance: writes made on one ScreenSaverDefaults object aren't
    // flushed by synchronize() on another.
    private lazy var defaults: UserDefaults =
        ScreenSaverDefaults(forModuleWithName: bundle.bundleIdentifier ?? "local.tessera-clock") ?? .standard
    private func setting(_ key: String) -> String {
        let v = Self.varieties.first { $0.key == key }!
        if let saved = defaults.string(forKey: key), v.options.contains(where: { $0.0 == saved }) { return saved }
        return v.options[0].0
    }

    private var grid = grids["compact"]!
    private var surface = surfaces["noir"]!
    private var surfaceName = "noir"
    private var drift = false
    private var n = 0                 // round: clocks across the square grid
    private var panel = false
    private var cols = 0, rows = 0    // the grid actually laid out
    private var clocks: [Clock] = []

    private var now: Double = 0
    // 1 = fully shown. Drops towards `Tune.dimmed` once you start to wake the
    // Mac, so the password prompt drawn over the screensaver is easy to see.
    private var visibility: CGFloat = 1, visibilityTarget: CGFloat = 1
    private var observers: [NSObjectProtocol] = []
    private var lastTick: CFTimeInterval?
    private var phaseIsTime = true, phaseEnd: Double = 0, setIndex = 0, stepIndex = 0, shownTime = ""

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        start()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        start()
    }

    private func start() {
        animationTimeInterval = 1.0 / 60.0
        if observers.isEmpty && !isPreview { listenForWake() }
        grid = grids[setting("grid")]!
        surfaceName = setting("surface")
        surface = surfaces[surfaceName]!
        background = nil
        drift = setting("around") == "drift"
        panel = resolveShape() == "panel"
        buildGrid()
        showTime()
    }

    // macOS keeps the screensaver running behind the login prompt. It announces
    // when it's dismissing the screensaver and when it starts it again, so fade
    // down on the first and back up on the second.
    private func listenForWake() {
        let centre = DistributedNotificationCenter.default()
        observers = [
            centre.addObserver(forName: .init("com.apple.screensaver.willstop"), object: nil, queue: .main) { [weak self] _ in
                self?.visibilityTarget = Tune.dimmed
            },
            centre.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                self?.visibilityTarget = Tune.dimmed
            },
            centre.addObserver(forName: .init("com.apple.screensaver.didstart"), object: nil, queue: .main) { [weak self] _ in
                self?.visibilityTarget = 1
            },
        ]
    }

    // The notifications above don't reliably arrive, so also watch for input
    // directly: a key press, click or mouse move dims the clock, and a quiet
    // spell brings it back. It only reacts once the Mac has been idle for a
    // moment, so starting the screensaver from a hot corner doesn't dim it.
    private var armed = false
    private func watchForWake() {
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if idle > Tune.restIdle { armed = true; visibilityTarget = 1 }
        else if idle > 2 { armed = true }
        else if armed && idle < Tune.wakeIdle { visibilityTarget = Tune.dimmed }
    }

    deinit {
        let centre = DistributedNotificationCenter.default()
        observers.forEach { centre.removeObserver($0) }
    }

    override func startAnimation() {
        super.startAnimation()
        visibilityTarget = 1
    }

    // "Alternate" swaps shape each time the screensaver starts. Every display
    // gets its own copy, started together, so starts within a few seconds of
    // each other share one shape. The System Settings preview shows the next
    // shape without using up the turn.
    private func resolveShape() -> String {
        let chosen = setting("shape")
        guard chosen == "alternate" else { return chosen }
        let current = defaults.string(forKey: "currentShape") == "panel" ? "panel" : "round"
        if isPreview { return defaults.object(forKey: "currentShape") == nil ? current : (current == "panel" ? "round" : "panel") }
        let stamp = Date().timeIntervalSince1970
        if stamp - defaults.double(forKey: "currentShapeAt") < 8 { return current }
        let next = defaults.object(forKey: "currentShape") == nil ? "round" : (current == "panel" ? "round" : "panel")
        defaults.set(next, forKey: "currentShape")
        defaults.set(stamp, forKey: "currentShapeAt")
        defaults.synchronize()
        return next
    }

    private func panelCols(for size: CGSize) -> Int {
        guard size.width > 0, size.height > 0 else { return Panel.minCols }
        var c = Int((CGFloat(Panel.rows) * size.width / size.height).rounded())
        if c % 2 == 0 { c -= 1 }              // odd, so the numerals sit dead centre
        return max(Panel.minCols, c)
    }

    private func rest(_ c: Clock, _ t: Double) -> (CGFloat, CGFloat) {
        let th = CGFloat.pi * 0.25 + (drift ? 0.24 * sin(CGFloat(t) * 0.55 - (c.x + c.y) * 0.45) : 0)
        return (th, th)
    }

    private func buildGrid() {
        clocks = []
        if panel {
            cols = panelCols(for: bounds.size); rows = Panel.rows
            let mx = CGFloat(cols - 1) / 2, my = CGFloat(rows - 1) / 2
            for gy in 0..<rows {
                for gx in 0..<cols {
                    clocks.append(Clock(gx: gx, gy: gy, x: CGFloat(gx) - mx, y: CGFloat(gy) - my,
                                        fn: { [unowned self] in self.rest($0, $1) }, t: now))
                }
            }
            return
        }
        n = grid.n; cols = n; rows = n
        let mid = CGFloat(n - 1) / 2, reach = pow(CGFloat(n) / 2 - 0.1, 2)
        clocks = []
        for gy in 0..<n {
            for gx in 0..<n {
                let x = CGFloat(gx) - mid, y = CGFloat(gy) - mid
                if x * x + y * y > reach { continue }
                clocks.append(Clock(gx: gx, gy: gy, x: x, y: y, fn: { [unowned self] in self.rest($0, $1) }, t: now))
            }
        }
    }

    // MARK: Time

    private func timeString() -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return String(format: "%02d%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private func timeMovement(_ str: String) -> Movement {
        var cells: [Int: (CGFloat, CGFloat)] = [:]
        let n = cols
        if panel {
            // Pack numerals by inked width (a 1 is narrow), one clock apart and
            // two between hours and minutes, then centre the group.
            let ds = str.map { $0.wholeNumberValue ?? 0 }
            var starts: [Int] = [], x = 0
            for (i, d) in ds.enumerated() {
                let (a, w) = blockSpans[d]
                starts.append(x - a)
                x += w + (i == 1 ? 2 : 1)
            }
            let left = Int((Double(cols - (x - 1)) / 2).rounded()), top = 1
            for (i, d) in ds.enumerated() {
                let digit = blockDigits[d]
                for r in 0..<6 {
                    for k in 0..<4 {
                        if let pair = digit[r][k] { cells[(top + r) * n + left + starts[i] + k] = pair }
                    }
                }
            }
            return { [unowned self] c, t in cells[c.gy * n + c.gx] ?? self.rest(c, t) }
        }
        let font = grid.font, top = (rows - font.h) / 2
        for (i, ch) in str.enumerated() {
            let rows = font.glyphs[ch.wholeNumberValue ?? 0]
            for r in 0..<font.h {
                for (k, g) in rows[r].enumerated() {
                    if let pair = glyph[g] { cells[(top + r) * n + grid.columns[i] + k] = pair }
                }
            }
        }
        return { [unowned self] c, t in cells[c.gy * n + c.gx] ?? self.rest(c, t) }
    }

    // MARK: Sequencing — hands never jump; each clock takes the new movement at its own moment

    private func handOver(_ fn: @escaping Movement, delay: (Clock) -> Double) {
        for c in clocks {
            c.next = fn
            c.switchAt = now + delay(c) + Double.random(in: 0..<Tune.jitter)
        }
    }
    private func showTime() {
        shownTime = timeString()
        let half = Double(cols) / 2
        handOver(timeMovement(shownTime)) { (Double($0.x) + half) * Tune.sweep }
        phaseIsTime = true; phaseEnd = now + Tune.timeHold
    }
    private func showPattern() {
        guard let origin = clocks.randomElement() else { return }
        handOver(programme[setIndex % programme.count][stepIndex]) {
            Double(hypot($0.x - origin.x, $0.y - origin.y)) * Tune.ripple
        }
        phaseIsTime = false; phaseEnd = now + Tune.patternHold
    }
    private func advance() {
        if phaseIsTime {
            if now >= phaseEnd { stepIndex = 0; showPattern() }
            else if timeString() != shownTime { let end = phaseEnd; showTime(); phaseEnd = max(end, now + 6) }
        } else if now >= phaseEnd {
            stepIndex += 1
            if stepIndex < programme[setIndex % programme.count].count { showPattern() }
            else { setIndex += 1; showTime() }
        }
    }

    // MARK: Animation — fixed small steps, so a late frame catches up smoothly

    override func animateOneFrame() {
        let tick = CACurrentMediaTime()
        let elapsed = min(tick - (lastTick ?? tick), 3)
        lastTick = tick
        if !isPreview { watchForWake() }
        visibility += (visibilityTarget - visibility) * CGFloat(1 - exp(-elapsed * Tune.fadeRate))
        let steps = Int((elapsed * 60).rounded(.up))
        if steps > 0 {
            let dt = elapsed / Double(steps)
            for _ in 0..<steps {
                now += dt
                advance()
                for c in clocks {
                    if let next = c.next, now >= c.switchAt { c.fn = next; c.next = nil }
                    let (h, m) = c.fn(c, now)
                    c.h.step(h, CGFloat(dt)); c.m.step(m, CGFloat(dt))
                }
            }
        }
        needsDisplay = true
    }

    // MARK: Drawing

    private var background: CGImage?
    private var backgroundKey = ""

    private func paintBackground(pitch: CGFloat, board: CGRect, c0: CGPoint) -> CGImage? {
        let scale = window?.backingScaleFactor ?? 2
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        let s = surface

        ctx.setFillColor(s.wall.cgColor)
        ctx.fill(bounds)

        // The board — a disc, or a wide panel — lit from above, with a soft shadow
        let disc = board
        let shape = panel
            ? CGPath(roundedRect: board, cornerWidth: pitch * 0.12, cornerHeight: pitch * 0.12, transform: nil)
            : CGPath(ellipseIn: board, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -pitch * 0.14 * scale), blur: pitch * 0.55 * scale, color: s.rim.cgColor)
        ctx.setFillColor(s.disc.1.cgColor)
        ctx.addPath(shape)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [s.disc.0.cgColor, s.disc.1.cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: c0.x, y: disc.maxY), end: CGPoint(x: c0.x, y: disc.minY), options: [])
        }
        ctx.restoreGState()

        // Clock faces, milled a little way into the disc: a slightly darker floor,
        // a shadow under the upper-left wall, and light catching the lower-right lip.
        // (Shadow offsets and blur are in device pixels, hence the scale.)
        let r = pitch * Tune.faceRadius, depth = pitch * Tune.recessDepth
        for c in clocks {
            let p = CGPoint(x: c0.x + c.x * pitch, y: c0.y - c.y * pitch)
            let face = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            ctx.saveGState()
            ctx.addEllipse(in: face)
            ctx.clip()
            ctx.setFillColor(s.well.cgColor)
            ctx.fill(face)
            // Fill everything outside the circle; its shadow falls inside the rim.
            ctx.addRect(face.insetBy(dx: -r * 2, dy: -r * 2))
            ctx.addEllipse(in: face)
            ctx.setShadow(offset: CGSize(width: depth * 0.6 * scale, height: -depth * scale),
                          blur: depth * 2.2 * scale, color: s.inner.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()
            // Lower-right lip: in AppKit angles run anticlockwise from +x.
            ctx.addArc(center: p, radius: r, startAngle: .pi * 0.15, endAngle: -.pi * 0.85, clockwise: true)
            ctx.setStrokeColor(s.face.cgColor)
            ctx.setLineWidth(max(1, pitch * 0.012))
            ctx.strokePath()
        }
        return ctx.makeImage()
    }

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let s = surface
        if panel && panelCols(for: bounds.size) != cols {   // the screen changed shape
            buildGrid(); showTime()
        }
        let c0 = CGPoint(x: bounds.midX, y: bounds.midY)
        let pitch: CGFloat, board: CGRect
        if panel {
            pitch = min(bounds.width * 0.96 / (CGFloat(cols) + 0.5), bounds.height * 0.86 / (CGFloat(rows) + 0.5))
            let bw = (CGFloat(cols) + 0.5) * pitch, bh = (CGFloat(rows) + 0.5) * pitch
            board = CGRect(x: c0.x - bw / 2, y: c0.y - bh / 2, width: bw, height: bh)
        } else {
            pitch = min(bounds.width, bounds.height) * 0.90 / (CGFloat(n) + 1.7)
            let discR = (CGFloat(n) / 2 + 0.85) * pitch
            board = CGRect(x: c0.x - discR, y: c0.y - discR, width: discR * 2, height: discR * 2)
        }

        // The disc and its recessed faces never move, so they're drawn once into a
        // cached image and redrawn only when the size, grid or surface changes.
        let key = "\(bounds.size):\(panel):\(cols):\(surfaceName)"
        if backgroundKey != key || background == nil {
            backgroundKey = key
            background = paintBackground(pitch: pitch, board: board, c0: c0)
        }
        if let background { ctx.draw(background, in: bounds) }

        // Grid y runs downward like the page; AppKit's y runs up.
        func centre(_ c: Clock) -> CGPoint { CGPoint(x: c0.x + c.x * pitch, y: c0.y - c.y * pitch) }

        // Hands: flat bars with a short tail past the pivot. They stand off the
        // disc, so each casts a soft shadow down and to the right, as if lit from
        // the upper left.
        let len = pitch * (panel ? Panel.handLen : Tune.handLen), w = max(pitch * Tune.handWeight, 1.5), tail = w / 2
        for c in clocks {
            let p = centre(c)
            for a in [c.h.pos, c.m.pos] {
                let sx = sin(a), sy = cos(a)
                ctx.move(to: CGPoint(x: p.x - sx * tail, y: p.y - sy * tail))
                ctx.addLine(to: CGPoint(x: p.x + sx * len, y: p.y + sy * len))
            }
        }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: w * Tune.shadowOffset, height: -w * Tune.shadowOffset * 1.4),
                      blur: w * Tune.shadowBlur, color: s.cast.cgColor)
        ctx.setLineCap(.butt)
        ctx.setLineWidth(w)
        ctx.setStrokeColor(s.hand.cgColor)
        ctx.strokePath()
        ctx.restoreGState()

        if visibility < 0.999 {
            ctx.setFillColor(NSColor.black.withAlphaComponent(1 - visibility).cgColor)
            ctx.fill(bounds)
        }
    }

    // MARK: - Options (System Settings → Screen Saver → Options…)

    private var sheet: NSWindow?
    private var popups: [NSPopUpButton] = []

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        popups = Self.varieties.map { v in
            let popup = NSPopUpButton()
            popup.addItems(withTitles: v.options.map(\.1))
            popup.selectItem(at: v.options.firstIndex { $0.0 == setting(v.key) } ?? 0)
            return popup
        }
        let done = NSButton(title: "Done", target: self, action: #selector(closeSheet))
        done.keyEquivalent = "\r"
        var rows: [[NSView]] = zip(Self.varieties, popups).map { [NSTextField(labelWithString: $0.label), $1] }
        rows.append([NSGridCell.emptyContentView, done])
        let gridView = NSGridView(views: rows)
        gridView.column(at: 0).xPlacement = .trailing
        gridView.rowSpacing = 10
        gridView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 210),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let content = NSView()
        content.addSubview(gridView)
        NSLayoutConstraint.activate([
            gridView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            gridView.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        window.contentView = content
        sheet = window
        return window
    }

    @objc private func closeSheet() {
        for (v, popup) in zip(Self.varieties, popups) {
            defaults.set(v.options[max(0, popup.indexOfSelectedItem)].0, forKey: v.key)
        }
        defaults.synchronize()
        start()
        if let sheet {
            if let parent = sheet.sheetParent { parent.endSheet(sheet) } else { sheet.close() }
        }
    }
}
