import Foundation
import Compression
import CryptoKit

enum GzipError: LocalizedError {
    case badMagic, unsupportedMethod, headerTooLong, truncated, streamInit, streamFailed
    case sizeMismatch(expected: UInt32, got: UInt32)

    var errorDescription: String? {
        switch self {
        case .badMagic:            return "The downloaded file is not a gzip archive."
        case .unsupportedMethod:   return "Unsupported gzip compression method."
        case .headerTooLong:       return "Malformed gzip header."
        case .truncated:           return "The download ended early."
        case .streamInit:          return "Could not start decompression."
        case .streamFailed:        return "The archive is damaged and could not be expanded."
        case let .sizeMismatch(e, g):
            return "Expanded size mismatch (expected \(e) bytes, got \(g))."
        }
    }
}

/// Streaming gunzip.
///
/// Apple's Compression framework has no gzip container support: COMPRESSION_ZLIB
/// is *raw DEFLATE* (RFC 1951), so handing it a .gz verbatim fails. We parse the
/// RFC 1952 header ourselves, feed the DEFLATE payload through, and check the
/// trailing ISIZE. Memory stays flat -- 64 KB in, 1 MB out, regardless of the
/// 330 MB input.
enum GzipDecoder {
    private static let inChunk = 64 * 1024
    private static let outChunk = 1024 * 1024

    static func decompress(from src: URL,
                           to dst: URL,
                           progress: ((Double) -> Void)? = nil) throws {
        let totalIn = (try FileManager.default.attributesOfItem(atPath: src.path)[.size] as? Int64) ?? 0
        let input = try FileHandle(forReadingFrom: src)
        defer { try? input.close() }

        FileManager.default.createFile(atPath: dst.path, contents: nil)
        let output = try FileHandle(forWritingTo: dst)
        defer { try? output.close() }

        // ---- RFC 1952 header ----------------------------------------------
        var head = try input.read(upToCount: inChunk) ?? Data()
        guard head.count >= 18 else { throw GzipError.truncated }
        guard head[0] == 0x1f, head[1] == 0x8b else { throw GzipError.badMagic }
        guard head[2] == 8 else { throw GzipError.unsupportedMethod }
        let flg = head[3]
        var p = 10
        func need(_ n: Int) throws { if p + n > head.count { throw GzipError.headerTooLong } }
        if flg & 0x04 != 0 {                                  // FEXTRA
            try need(2)
            let xlen = Int(head[p]) | Int(head[p + 1]) << 8
            p += 2 + xlen
        }
        if flg & 0x08 != 0 { while true { try need(1); let b = head[p]; p += 1; if b == 0 { break } } } // FNAME
        if flg & 0x10 != 0 { while true { try need(1); let b = head[p]; p += 1; if b == 0 { break } } } // FCOMMENT
        if flg & 0x02 != 0 { try need(2); p += 2 }            // FHCRC
        guard p <= head.count else { throw GzipError.headerTooLong }

        // ISIZE: uncompressed length mod 2^32, from the last 4 bytes.
        let expandedExpected: UInt32 = try {
            let size = try FileManager.default
                .attributesOfItem(atPath: src.path)[.size] as? Int64 ?? 0
            guard size >= 8 else { throw GzipError.truncated }
            let h = try FileHandle(forReadingFrom: src)
            defer { try? h.close() }
            try h.seek(toOffset: UInt64(size - 4))
            let t = try h.read(upToCount: 4) ?? Data()
            guard t.count == 4 else { throw GzipError.truncated }
            return UInt32(t[0]) | UInt32(t[1]) << 8 | UInt32(t[2]) << 16 | UInt32(t[3]) << 24
        }()

        var pending = head.subdata(in: p ..< head.count)      // DEFLATE bytes already read
        head = Data()

        // ---- streaming inflate --------------------------------------------
        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: -1)!, dst_size: 0,
            src_ptr: UnsafeMutablePointer<UInt8>(bitPattern: -1)!, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else { throw GzipError.streamInit }
        defer { compression_stream_destroy(&stream) }

        let outBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: outChunk)
        defer { outBuf.deallocate() }
        stream.dst_ptr = outBuf
        stream.dst_size = outChunk

        var consumedIn = Int64(head.count)
        var written: UInt64 = 0
        var sourceDone = false

        while true {
            if stream.src_size == 0 {
                if pending.isEmpty {
                    let next = try input.read(upToCount: inChunk) ?? Data()
                    if next.isEmpty { sourceDone = true } else {
                        pending = next
                        consumedIn += Int64(next.count)
                        progress.map { if totalIn > 0 { $0(Double(consumedIn) / Double(totalIn)) } }
                    }
                }
            }

            let status: compression_status = pending.withUnsafeBytes { raw -> compression_status in
                if !pending.isEmpty {
                    stream.src_ptr = raw.bindMemory(to: UInt8.self).baseAddress!
                    stream.src_size = pending.count
                }
                return compression_stream_process(&stream, sourceDone ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
            }
            // Whatever the inflater did not consume is re-presented next pass.
            let leftover = stream.src_size
            if !pending.isEmpty { pending = pending.suffix(leftover) }

            let produced = outChunk - stream.dst_size
            if produced > 0 {
                output.write(Data(bytes: outBuf, count: produced))
                written += UInt64(produced)
                stream.dst_ptr = outBuf
                stream.dst_size = outChunk
            }

            switch status {
            case COMPRESSION_STATUS_OK:  continue
            case COMPRESSION_STATUS_END: 
                let got = UInt32(truncatingIfNeeded: written)
                guard got == expandedExpected else {
                    throw GzipError.sizeMismatch(expected: expandedExpected, got: got)
                }
                progress?(1.0)
                return
            default: throw GzipError.streamFailed
            }
        }
    }
}

enum Digest {
    /// SHA-256 without loading 330 MB into memory.
    static func sha256(of url: URL, progress: ((Double) -> Void)? = nil) throws -> String {
        let total = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        var read: Int64 = 0
        while let chunk = try h.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
            read += Int64(chunk.count)
            progress.map { if total > 0 { $0(Double(read) / Double(total)) } }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
