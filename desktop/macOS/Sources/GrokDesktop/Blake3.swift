import Foundation

/// BLAKE3 (default hash mode, 32-byte output), following the single-threaded reference
/// implementation. `/memory` needs it because `memory/forget` only deletes a note whose
/// BLAKE3 digest matches the bytes the user previewed.
enum GrokBlake3 {
    private static let iv: [UInt32] = [0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19]
    private static let permutation = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]
    private static let chunkStart: UInt32 = 1, chunkEnd: UInt32 = 2, parent: UInt32 = 4, root: UInt32 = 8
    private static let blockLength = 64, chunkLength = 1024

    static func hex(_ data: Data) -> String { hash(data).map { String(format: "%02x", $0) }.joined() }
    static func hex(_ text: String) -> String { hex(Data(text.utf8)) }

    static func hash(_ data: Data) -> [UInt8] {
        var hasher = Hasher()
        data.withUnsafeBytes { hasher.update(Array($0.bindMemory(to: UInt8.self))) }
        return hasher.finalize()
    }

    private struct Output {
        var chainingValue: [UInt32]
        var block: [UInt32]
        var counter: UInt64
        var blockLength: UInt32
        var flags: UInt32

        var nextChainingValue: [UInt32] { Array(GrokBlake3.compress(chainingValue, block, counter, blockLength, flags).prefix(8)) }

        func rootBytes() -> [UInt8] {
            let words = GrokBlake3.compress(chainingValue, block, 0, blockLength, flags | GrokBlake3.root)
            var bytes: [UInt8] = []
            bytes.reserveCapacity(32)
            for word in words.prefix(8) {
                for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: word >> UInt32(shift))) }
            }
            return bytes
        }
    }

    private struct ChunkState {
        var chainingValue = GrokBlake3.iv
        var counter: UInt64
        var block = [UInt8](repeating: 0, count: 64)
        var blockLength = 0
        var blocksCompressed = 0

        init(counter: UInt64) { self.counter = counter }

        var length: Int { GrokBlake3.blockLength * blocksCompressed + blockLength }
        var startFlag: UInt32 { blocksCompressed == 0 ? GrokBlake3.chunkStart : 0 }

        mutating func update(_ input: ArraySlice<UInt8>) {
            var input = input
            while !input.isEmpty {
                if blockLength == GrokBlake3.blockLength {
                    chainingValue = Array(GrokBlake3.compress(chainingValue, GrokBlake3.words(block), counter, UInt32(GrokBlake3.blockLength), startFlag).prefix(8))
                    blocksCompressed += 1
                    block = [UInt8](repeating: 0, count: 64)
                    blockLength = 0
                }
                let take = min(GrokBlake3.blockLength - blockLength, input.count)
                for (offset, byte) in input.prefix(take).enumerated() { block[blockLength + offset] = byte }
                blockLength += take
                input = input.dropFirst(take)
            }
        }

        var output: Output {
            Output(chainingValue: chainingValue, block: GrokBlake3.words(block), counter: counter,
                   blockLength: UInt32(blockLength), flags: startFlag | GrokBlake3.chunkEnd)
        }
    }

    private struct Hasher {
        var chunk = ChunkState(counter: 0)
        var stack: [[UInt32]] = []

        mutating func update(_ bytes: [UInt8]) {
            var input = bytes[...]
            while !input.isEmpty {
                if chunk.length == GrokBlake3.chunkLength {
                    var chainingValue = chunk.output.nextChainingValue
                    var totalChunks = chunk.counter + 1
                    // Merge completed subtrees: one merge per trailing zero bit of the chunk count.
                    while totalChunks & 1 == 0, let left = stack.popLast() {
                        chainingValue = GrokBlake3.parentOutput(left, chainingValue).nextChainingValue
                        totalChunks >>= 1
                    }
                    stack.append(chainingValue)
                    chunk = ChunkState(counter: chunk.counter + 1)
                }
                let take = min(GrokBlake3.chunkLength - chunk.length, input.count)
                chunk.update(input.prefix(take))
                input = input.dropFirst(take)
            }
        }

        func finalize() -> [UInt8] {
            var output = chunk.output
            for left in stack.reversed() { output = GrokBlake3.parentOutput(left, output.nextChainingValue) }
            return output.rootBytes()
        }
    }

    private static func parentOutput(_ left: [UInt32], _ right: [UInt32]) -> Output {
        Output(chainingValue: iv, block: left + right, counter: 0, blockLength: UInt32(blockLength), flags: parent)
    }

    private static func words(_ block: [UInt8]) -> [UInt32] {
        (0..<16).map { index in
            let base = index * 4
            return UInt32(block[base]) | UInt32(block[base + 1]) << 8 | UInt32(block[base + 2]) << 16 | UInt32(block[base + 3]) << 24
        }
    }

    private static func compress(_ chainingValue: [UInt32], _ block: [UInt32], _ counter: UInt64, _ blockLength: UInt32, _ flags: UInt32) -> [UInt32] {
        var state = chainingValue + Array(iv.prefix(4)) + [UInt32(truncatingIfNeeded: counter), UInt32(truncatingIfNeeded: counter >> 32), blockLength, flags]
        var message = block
        for round in 0..<7 {
            mix(&state, 0, 4, 8, 12, message[0], message[1])
            mix(&state, 1, 5, 9, 13, message[2], message[3])
            mix(&state, 2, 6, 10, 14, message[4], message[5])
            mix(&state, 3, 7, 11, 15, message[6], message[7])
            mix(&state, 0, 5, 10, 15, message[8], message[9])
            mix(&state, 1, 6, 11, 12, message[10], message[11])
            mix(&state, 2, 7, 8, 13, message[12], message[13])
            mix(&state, 3, 4, 9, 14, message[14], message[15])
            if round < 6 { message = permutation.map { message[$0] } }
        }
        for index in 0..<8 {
            state[index] ^= state[index + 8]
            state[index + 8] ^= chainingValue[index]
        }
        return state
    }

    @inline(__always)
    private static func mix(_ state: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt32, _ y: UInt32) {
        state[a] = state[a] &+ state[b] &+ x
        state[d] = rotateRight(state[d] ^ state[a], 16)
        state[c] = state[c] &+ state[d]
        state[b] = rotateRight(state[b] ^ state[c], 12)
        state[a] = state[a] &+ state[b] &+ y
        state[d] = rotateRight(state[d] ^ state[a], 8)
        state[c] = state[c] &+ state[d]
        state[b] = rotateRight(state[b] ^ state[c], 7)
    }

    @inline(__always)
    private static func rotateRight(_ value: UInt32, _ count: UInt32) -> UInt32 { (value >> count) | (value << (32 - count)) }
}
