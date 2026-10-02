import AVFoundation

public enum PCMUtilities {
    public static func copyPCM(_ sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sample),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              stream.pointee.mFormatID == kAudioFormatLinearPCM else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))) else { return nil }
        buffer.frameLength = buffer.frameCapacity
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(buffer.frameLength),
            into: buffer.mutableAudioBufferList) == noErr else { return nil }
        return buffer
    }

    public static func convert(_ input: AVAudioPCMBuffer, to format: AVAudioFormat,
                               converter: inout AVAudioConverter?) -> AVAudioPCMBuffer? {
        if input.format == format { return input }
        if converter?.inputFormat != input.format || converter?.outputFormat != format {
            converter = AVAudioConverter(from: input.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter,
              let output = AVAudioPCMBuffer(pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(ceil(Double(input.frameLength) * format.sampleRate / input.format.sampleRate)) + 32) else { return nil }
        var delivered = false
        var error: NSError?
        let result = converter.convert(to: output, error: &error) { _, status in
            if delivered { status.pointee = .noDataNow; return nil }
            delivered = true; status.pointee = .haveData; return input
        }
        guard result != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    public static func sample(samples: [Float], at frame: Int64) -> CMSampleBuffer? {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: true)!
        let bytes = samples.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: bytes, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block) == noErr, let block else { return nil }
        let copied = samples.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
        }
        guard copied == noErr else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
            presentationTimeStamp: CMTime(value: frame, timescale: 48_000), decodeTimeStamp: .invalid)
        var size = 8
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
            formatDescription: format.formatDescription, sampleCount: samples.count / 2,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }
}
