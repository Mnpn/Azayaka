import CoreMedia

class ReplayBuffer {
    private var buffer: [CMSampleBuffer?]
    private var head: Int = 0
    private let capacity: Int

    init(frameRate: Double) {
        self.capacity = Int(frameRate * 30)
        self.buffer = [CMSampleBuffer?](repeating: nil, count: self.capacity)
    }

    func add(_ sample: CMSampleBuffer) {
        buffer[head] = sample
        head = (head + 1) % capacity
    }

    func getSamples() -> [CMSampleBuffer] {
        return buffer.compactMap { $0 }
    }
}
