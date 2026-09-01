import Foundation
import Compression

/// A minimal read-only ZIP reader — enough to open an EPUB (a ZIP of XHTML/CSS).
///
/// No external packages: entries stored uncompressed (method 0) are copied;
/// DEFLATE entries (method 8) are inflated with the system Compression
/// framework, whose `COMPRESSION_ZLIB` decodes the raw DEFLATE stream that ZIP
/// stores (no zlib header). ZIP64 is not supported (EPUBs effectively never use
/// it); such an archive simply yields no entries.
struct ZipArchive {
    private let data: Data
    private struct Entry { let method: UInt16; let compressedSize: Int; let uncompressedSize: Int; let localHeaderOffset: Int }
    private let index: [String: Entry]

    var names: [String] { Array(index.keys) }

    init?(data: Data) {
        self.data = data
        guard let eocd = Self.findEOCD(in: data) else { return nil }
        let count = Int(data.u16(eocd + 10))
        var cursor = Int(data.u32(eocd + 16))   // central directory offset
        var map: [String: Entry] = [:]
        for _ in 0..<count {
            guard cursor + 46 <= data.count, data.u32(cursor) == 0x0201_4b50 else { break }
            let method = data.u16(cursor + 10)
            let compSize = Int(data.u32(cursor + 20))
            let uncompSize = Int(data.u32(cursor + 24))
            let nameLen = Int(data.u16(cursor + 28))
            let extraLen = Int(data.u16(cursor + 30))
            let commentLen = Int(data.u16(cursor + 32))
            let localOffset = Int(data.u32(cursor + 42))
            let nameStart = cursor + 46
            guard nameStart + nameLen <= data.count else { break }
            let name = String(decoding: data[nameStart..<nameStart + nameLen], as: UTF8.self)
            map[name] = Entry(method: method, compressedSize: compSize,
                              uncompressedSize: uncompSize, localHeaderOffset: localOffset)
            cursor = nameStart + nameLen + extraLen + commentLen
        }
        if map.isEmpty { return nil }
        index = map
    }

    /// Decompressed bytes for `name`, or nil if absent/unsupported/corrupt.
    func data(for name: String) -> Data? {
        guard let e = index[name] else { return nil }
        let h = e.localHeaderOffset
        guard h + 30 <= data.count, data.u32(h) == 0x0403_4b50 else { return nil }
        // The LOCAL header carries its own name/extra lengths (may differ from central).
        let nameLen = Int(data.u16(h + 26))
        let extraLen = Int(data.u16(h + 28))
        let start = h + 30 + nameLen + extraLen
        guard start + e.compressedSize <= data.count else { return nil }
        let comp = data.subdata(in: start..<start + e.compressedSize)
        switch e.method {
        case 0: return comp                                   // stored
        case 8: return Self.inflateRaw(comp, expected: e.uncompressedSize)
        default: return nil
        }
    }

    // MARK: internals

    private static func findEOCD(in data: Data) -> Int? {
        // End Of Central Directory: signature PK\x05\x06, near the end (after an
        // up-to-64KB comment). Scan backwards.
        let sig: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        let minEOCD = 22
        guard data.count >= minEOCD else { return nil }
        let lowerBound = max(0, data.count - minEOCD - 0xFFFF)
        var i = data.count - minEOCD
        while i >= lowerBound {
            if data[i] == sig[0] && data[i + 1] == sig[1] && data[i + 2] == sig[2] && data[i + 3] == sig[3] {
                return i
            }
            i -= 1
        }
        return nil
    }

    private static func inflateRaw(_ src: Data, expected: Int) -> Data? {
        if expected == 0 { return Data() }
        var dst = Data(count: expected)
        let written = dst.withUnsafeMutableBytes { (dp: UnsafeMutableRawBufferPointer) -> Int in
            src.withUnsafeBytes { (sp: UnsafeRawBufferPointer) -> Int in
                guard let d = dp.bindMemory(to: UInt8.self).baseAddress,
                      let s = sp.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(d, expected, s, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == expected ? dst : nil
    }
}

private extension Data {
    /// Little-endian reads at an absolute byte offset (ZIP is little-endian).
    func u16(_ off: Int) -> UInt16 {
        let b = startIndex + off
        return UInt16(self[b]) | (UInt16(self[b + 1]) << 8)
    }
    func u32(_ off: Int) -> UInt32 {
        let b = startIndex + off
        return UInt32(self[b]) | (UInt32(self[b + 1]) << 8) | (UInt32(self[b + 2]) << 16) | (UInt32(self[b + 3]) << 24)
    }
}
