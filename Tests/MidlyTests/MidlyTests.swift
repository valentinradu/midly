@testable import Midly
import XCTest

private extension Synth {
    static func test() throws -> Synth {
        guard let url = Bundle.module
            .url(forResource: "soundfont", withExtension: "sf2")
        else {
            fatalError()
        }

        return try Synth(
            bankURL: url.absoluteString,
            presets: [0])
    }
}

private extension Array where Element == Beat {
    static func test(count: Int, duration: Double) -> [Beat] {
        let beat = Beat(
            channel: 0,
            pitch: 60,
            velocity: 100,
            duration: duration)
        return [Beat](repeating: beat, count: count)
    }
}

final class MidlyTests: XCTestCase {
    func testCallbacks() throws {
        let pauseExp = self.expectation(description: "Pause callback is called")
        let resumeExp = self.expectation(description: "Resume callback is called")
        let beatExp = self.expectation(description: "Beat callback is called")
        
        let synth = try Synth.test()
        synth.onBeat { _ in
            beatExp.fulfill()
        }
        synth.onPause {
            pauseExp.fulfill()
        }
        synth.onResume {
            resumeExp.fulfill()
        }
        try synth.schedule(beats: .test(count: 1, duration: 1))
        try synth.start()
        try synth.pause()
        try synth.resume()
        waitForExpectations(timeout: 2)
        try synth.stop()
    }
    
    func testUpdateBeats() throws {
        let synth = try Synth.test()
        try synth.start()
        
        for _ in 0..<10 {
            try synth.schedule(beats: .test(count: 1, duration: 1))
        }
        
        sleep(1)
        try synth.stop()
    }

    static var allTests = [
        ("Basic", testCallbacks, testUpdateBeats),
    ]
}
