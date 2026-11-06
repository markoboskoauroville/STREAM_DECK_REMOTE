import AppKit
import IOKit.hid

/// The Stream Deck itself, over USB HID, without Elgato's app (only one program can hold the deck).
///
/// The original Stream Deck (Elgato 0x0fd9, product 0x0060; this Mac's, serial AL21I1C06271): 15 keys, 5 across and 3
/// down. Each key takes a 72 × 72 BMP (24-bit, 54-byte header), turned 180°, sent as two output reports of 8191 bytes
/// (report 2, page 1 then page 2, the key numbered from 1 and from the right). Its presses come as input report 1, one
/// byte per key, also numbered from the right. Brightness and reset are feature reports 5 and 11.
/// (The protocol as python-elgato-streamdeck documents it, StreamDeckOriginal; read, not copied.)
///
/// Stream Deck MK.2 and the original v2 (0x0080, 0x006d; added 6.11.2026, Marko: "The deck is coming."): the same 15
/// keys, numbered from the left; each key a 72 × 72 JPEG turned 180°, sent as output reports of 1024 bytes (an 8-byte
/// header 02 07 key last lenLo lenHi pageLo pageHi); presses as input report 1 with 3 bytes before the 15 keys;
/// brightness feature 03 08 pct, reset 03 02.
final class Deck {
    static let cols = 5, rows = 3, keys = 15, px = 72
    private static let vendor = 0x0FD9
    private static let products = [0x0060, 0x006D, 0x0080]   // the original; the original v2 and the MK.2 (JPEG)
    private var jpeg = false
    private static let reportLength = 8191

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var inBuffer = [UInt8](repeating: 0, count: 1024)   // the MK.2 sends 512-byte reports
    private var down = [Bool](repeating: false, count: keys)
    private var sent = [Int: Int]()                   // key → hash of the image on it, so an unchanged key is not resent

    /// Called on the main thread.
    var onPress: ((Int) -> Void)?
    var onChange: ((String) -> Void)?
    private(set) var serial = ""
    var connected: Bool { device != nil }

    func start() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(m, Deck.products.map {
            [kIOHIDVendorIDKey: Deck.vendor, kIOHIDProductIDKey: $0] as CFDictionary } as CFArray)
        let me = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, d in
            Unmanaged<Deck>.fromOpaque(ctx!).takeUnretainedValue().attach(d)
        }, me)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, d in
            Unmanaged<Deck>.fromOpaque(ctx!).takeUnretainedValue().detach(d)
        }, me)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        if r != kIOReturnSuccess { onChange?(Deck.why(r)) }
        manager = m
    }

    private static func why(_ r: IOReturn) -> String {
        r == kIOReturnExclusiveAccess || r == kIOReturnNotPermitted
            ? "The Stream Deck is held by another program (quit Elgato's Stream Deck app)"
            : String(format: "The Stream Deck could not be opened (0x%08x)", r)
    }

    private func attach(_ d: IOHIDDevice) {
        let r = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { onChange?(Deck.why(r)); return }
        device = d
        jpeg = ((IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int) ?? 0x60) != 0x60
        serial = (IOHIDDeviceGetProperty(d, kIOHIDSerialNumberKey as CFString) as? String) ?? ""
        sent.removeAll()
        down = [Bool](repeating: false, count: Deck.keys)
        IOHIDDeviceRegisterInputReportCallback(d, &inBuffer, inBuffer.count, { ctx, _, _, _, id, report, length in
            Unmanaged<Deck>.fromOpaque(ctx!).takeUnretainedValue().input(id: id, report: report, length: length)
        }, Unmanaged.passUnretained(self).toOpaque())
        brightness(80)
        onChange?("Stream Deck \(serial) connected")
    }

    private func detach(_ d: IOHIDDevice) {
        guard d == device else { return }
        device = nil
        onChange?("The Stream Deck was unplugged")
    }

    /// Input report 1: a byte per key after the report id (some macOS versions hand the id over, some do not).
    private func input(id: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        // MK.2: [01] 00 0F 00 then the keys; the report id byte is there on some macOS versions, not on others
        let states = jpeg ? Array(bytes.dropFirst(bytes.count > 2 && bytes[0] == 0x01 && bytes[2] == 0x0F ? 4 : 3))
                          : (bytes.count > Deck.keys ? Array(bytes.dropFirst()) : bytes)
        for raw in 0..<min(Deck.keys, states.count) {
            let key = jpeg ? raw : Deck.fromRight(raw)
            let now = states[raw] != 0
            if now && !down[key] { DispatchQueue.main.async { self.onPress?(key) } }
            down[key] = now
        }
    }

    /// Key numbers on this deck run from the right of each row; the app counts from the left.
    static func fromRight(_ k: Int) -> Int { let c = k % cols; return k - c + (cols - 1 - c) }

    func brightness(_ percent: Int) {
        let p = UInt8(max(0, min(100, percent)))
        jpeg ? feature([0x03, 0x08, p], length: 32) : feature([0x05, 0x55, 0xAA, 0xD1, 0x01, p])
    }

    /// Every key black, by sending a black picture (v4, 6.11.2026): the deck's reset command, used before, left the
    /// keys blank blue and tore the pictures sent right after it (seen through the Pixel's camera).
    func clear() {
        let black = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Deck.px, pixelsHigh: Deck.px, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: black)
        NSColor.black.setFill(); NSRect(x: 0, y: 0, width: Deck.px, height: Deck.px).fill()
        NSGraphicsContext.restoreGraphicsState()
        sent.removeAll()
        for k in 0..<Deck.keys { show(k, black, hash: -1) }
    }

    /// Every key sent again at the next show (nothing is erased first).
    func forget() { sent.removeAll() }

    private func feature(_ b: [UInt8], length: Int = 17) {
        guard let d = device else { return }
        var p = b + [UInt8](repeating: 0, count: length - b.count)
        _ = IOHIDDeviceSetReport(d, kIOHIDReportTypeFeature, CFIndex(p[0]), &p, p.count)
    }

    /// One key's picture (72 × 72, drawn upright); nothing is sent when the key already shows it.
    func show(_ key: Int, _ image: NSBitmapImageRep, hash: Int) {
        guard let d = device, (0..<Deck.keys).contains(key), sent[key] != hash else { return }
        if jpeg { showJPEG(d, key, image); sent[key] = hash; return }
        let bmp = Deck.bmp(image)
        let k = UInt8(Deck.fromRight(key) + 1)
        // v3 (6.11.2026): each report filled to 8191 bytes, 16 of header and 8175 of picture, the last page shorter
        // (python-elgato-streamdeck's StreamDeckOriginal today). The 7749-byte first page of v1-v2 (and of Stream
        // Deck Control) tore the pictures into shifted bands, seen through the Pixel's camera.
        let body = Deck.reportLength - 16
        var page = 0, at = 0
        while at < bmp.count {
            let part = bmp[at..<min(bmp.count, at + body)]
            let last: UInt8 = at + body >= bmp.count ? 1 : 0
            var p: [UInt8] = [0x02, 0x01, UInt8(page + 1), 0x00, last, k] + [UInt8](repeating: 0, count: 10)
            p += part
            p += [UInt8](repeating: 0, count: Deck.reportLength - p.count)
            let r = IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, 2, &p, p.count)
            if r != kIOReturnSuccess { onChange?(String(format: "A key's picture was refused (0x%08x)", r)); return }
            at += body; page += 1
        }
        sent[key] = hash
    }

    private func showJPEG(_ d: IOHIDDevice, _ key: Int, _ image: NSBitmapImageRep) {
        // turned 180°, then JPEG
        let n = Deck.px
        guard let turned = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: turned)
        NSGraphicsContext.current = ctx
        NSColor.black.setFill(); NSRect(x: 0, y: 0, width: n, height: n).fill()
        let t = NSAffineTransform(); t.translateX(by: CGFloat(n), yBy: CGFloat(n)); t.rotate(byDegrees: 180); t.concat()
        image.draw(in: NSRect(x: 0, y: 0, width: n, height: n))
        NSGraphicsContext.restoreGraphicsState()
        guard let jpg = turned.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else { return }
        let bytes = [UInt8](jpg), body = 1024 - 8
        var page = 0, at = 0
        while at < bytes.count {
            let part = bytes[at..<min(bytes.count, at + body)]
            let last: UInt8 = at + body >= bytes.count ? 1 : 0
            var p: [UInt8] = [0x02, 0x07, UInt8(key), last, UInt8(part.count & 0xFF), UInt8(part.count >> 8),
                              UInt8(page & 0xFF), UInt8(page >> 8)] + part
            p += [UInt8](repeating: 0, count: 1024 - p.count)
            let r = IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, 2, &p, p.count)
            if r != kIOReturnSuccess { onChange?(String(format: "A key's picture was refused (0x%08x)", r)); return }
            at += body; page += 1
        }
    }

    /// A 24-bit BMP turned 180°: BMP stores the bottom row first, so the 180° turn leaves the rows top first, each
    /// one right to left, in BGR.
    static func bmp(_ img: NSBitmapImageRep) -> [UInt8] {
        let n = px, row = n * 3, size = 54 + row * n
        var b = [UInt8](repeating: 0, count: size)
        func le32(_ at: Int, _ v: Int) { for i in 0..<4 { b[at + i] = UInt8((v >> (8 * i)) & 0xFF) } }
        b[0] = 0x42; b[1] = 0x4D; le32(2, size); le32(10, 54)
        le32(14, 40); le32(18, n); le32(22, n); b[26] = 1; b[28] = 24; le32(34, row * n)
        le32(38, 2835); le32(42, 2835)
        var at = 54
        for y in 0..<n {
            for x in stride(from: n - 1, through: 0, by: -1) {
                let c = img.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) ?? .black
                b[at] = UInt8(max(0, min(255, c.blueComponent * 255)))
                b[at + 1] = UInt8(max(0, min(255, c.greenComponent * 255)))
                b[at + 2] = UInt8(max(0, min(255, c.redComponent * 255)))
                at += 3
            }
        }
        return b
    }
}
