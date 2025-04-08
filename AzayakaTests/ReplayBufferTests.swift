import XCTest
import CoreMedia
@testable import Azayaka

class ReplayBufferTests: XCTestCase {
    func testReplayBuffer() {
        let frameRate = 30.0
        let buffer = ReplayBuffer(frameRate: frameRate)
        let capacity = Int(frameRate * 30)

        // Create some dummy sample buffers
        var samples: [CMSampleBuffer] = []
        for i in 0..<capacity * 2 {
            var sampleTiming = CMSampleTimingInfo(duration: CMTime.invalid, presentationTimeStamp: CMTime(value: CMTimeValue(i), timescale: 1), decodeTimeStamp: CMTime.invalid)
            var formatDescription: CMFormatDescription?
            _ = CMFormatDescriptionCreate(withMediaType: kCMMediaType_Video, mediaSubType: kCMVideoCodecType_H264, extensions: nil, formatDescriptionOut: &formatDescription)
            var sampleBuffer: CMSampleBuffer?
            _ = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDescription, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &sampleTiming, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)
            if let sampleBuffer = sampleBuffer {
                samples.append(sampleBuffer)
            } else {
                XCTFail("Failed to create sample buffer")
                return
            }
        }

        // Add samples to the buffer, exceeding its capacity
        for sample in samples {
            buffer.add(sample)
        }

        // Retrieve samples from the buffer
        let retrievedSamples = buffer.getSamples()

        // Check that the number of retrieved samples matches the buffer's capacity
        XCTAssertEqual(retrievedSamples.count, capacity)

        // Check that the retrieved samples are the most recent ones
        for i in 0..<capacity {
            XCTAssertEqual(retrievedSamples[i], samples[i + capacity])
        }
    }
}
