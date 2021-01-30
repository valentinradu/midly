import Atomics
import AudioToolbox

private enum Status: UInt32 {
    case on = 0x90
    case off = 0x80
    case program
}

public class Beat {
    public let channel: UInt32
    public let pitch: UInt32
    public let velocity: UInt32
    public let duration: Double
    
    public init(
        channel _channel: UInt32,
        pitch _pitch: UInt32,
        velocity _velocity: UInt32,
        duration _duration: Double)
    {
        channel = _channel
        pitch = _pitch
        velocity = _velocity
        duration = _duration
    }
}

private class OffBeat {
    let channel: UInt32
    let pitch: UInt32
    let velocity: UInt32
    let timestamp: UInt64
    
    init(
        channel _channel: UInt32,
        pitch _pitch: UInt32,
        velocity _velocity: UInt32,
        timestamp _timestamp: UInt64)
    {
        channel = _channel
        pitch = _pitch
        velocity = _velocity
        timestamp = _timestamp
    }
}

public typealias VoidClosure = () -> Void
public typealias BeatClosure = (_ beat: Beat) -> Void

public class Synth {
    fileprivate let ioUnit: AudioUnit
    fileprivate let comp: AudioComponent
    fileprivate var isRunning: Bool
    fileprivate var samplerUnits: [AudioUnit]
    fileprivate var presets: [Int]
    fileprivate var beats: [Beat]
    fileprivate let onQueue: Queue<Beat>
    fileprivate let offQueue: Queue<OffBeat>
    fileprivate var bus: ManagedAtomic<Int>
    fileprivate var didResume: VoidClosure?
    fileprivate var didPause: VoidClosure?
    fileprivate var didBeat: BeatClosure?
    
    public init(bankURL: String, presets _presets: [Int]) throws {
        isRunning = false
        samplerUnits = []
        beats = []
        presets = _presets
        bus = ManagedAtomic<Int>(0)
        onQueue = try Queue(capacity: 200)
        offQueue = try Queue(capacity: 10)
        
        var compDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_RemoteIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        comp = try AudioComponentFindNext(nil, &compDesc)
            .unwrapOr(error: MidlyError.auInitFail)
        
        var ioUnitTmp: AudioComponentInstance?
        try AudioComponentInstanceNew(comp, &ioUnitTmp)
            .noErrOr(error: MidlyError.auInitFail)
        
        guard let ioUnitLocal = ioUnitTmp else {
            throw MidlyError.auInitFail
        }
        
        ioUnit = ioUnitLocal
        
        var flag = UInt32(1)
        try AudioUnitSetProperty(
            ioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,
            &flag,
            UInt32(MemoryLayout<UInt32>.size))
            .noErrOr(error: MidlyError.auInitFail)
        
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44100.00,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0)
        try AudioUnitSetProperty(
            ioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &asbd,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
            .noErrOr(error: MidlyError.auInitFail)
        
        compDesc.componentType = kAudioUnitType_MusicDevice
        compDesc.componentSubType = kAudioUnitSubType_Sampler
        
        guard let samplerComp = AudioComponentFindNext(nil, &compDesc) else {
            throw MidlyError.auInitFail
        }
        
        for preset in presets {
            var samplerUnitTmp: AudioUnit?
            try AudioComponentInstanceNew(samplerComp, &samplerUnitTmp)
                .noErrOr(error: MidlyError.auInitFail)
            
            guard let samplerUnit = samplerUnitTmp else {
                throw MidlyError.auInitFail
            }
            
            var maxFPS: UInt32 = 4096
            try AudioUnitSetProperty(
                samplerUnit,
                kAudioUnitProperty_MaximumFramesPerSlice,
                kAudioUnitScope_Global,
                0,
                &maxFPS,
                UInt32(MemoryLayout<UInt32>.size))
                .noErrOr(error: MidlyError.auInitFail)
            
            let urlString = CFStringCreateWithCString(
                nil,
                bankURL.cString(using: .utf8),
                CFStringBuiltInEncodings.UTF8.rawValue)
            guard let url = CFURLCreateWithString(nil, urlString, nil) else {
                throw MidlyError.auInitFail
            }
            
            var instData = AUSamplerInstrumentData(
                fileURL: Unmanaged.passUnretained(url),
                instrumentType: UInt8(kInstrumentType_SF2Preset),
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB),
                presetID: UInt8(preset))
            
            try AudioUnitSetProperty(
                samplerUnit,
                kAUSamplerProperty_LoadInstrument,
                kAudioUnitScope_Global,
                0,
                &instData,
                UInt32(MemoryLayout<AUSamplerInstrumentData>.size))
                .noErrOr(error: MidlyError.auInitFail)
            
            try AudioUnitAddRenderNotify(
                samplerUnit,
                notifyCallback,
                Unmanaged.passUnretained(self).toOpaque())
                .noErrOr(error: MidlyError.auInitFail)
            
            try AudioUnitInitialize(samplerUnit)
                .noErrOr(error: MidlyError.auInitFail)
            
            samplerUnits.append(samplerUnit)
        }

        try update(bus: 0)
        
        try AudioUnitInitialize(ioUnit)
            .noErrOr(error: MidlyError.auInitFail)
    }
    
    public func start() throws {
        if !isRunning {
            try AudioOutputUnitStart(ioUnit)
                .noErrOr(error: MidlyError.auStartFail)
            
            isRunning = true
        }
    }
    
    public func stop() throws {
        if isRunning {
            try AudioOutputUnitStop(ioUnit)
                .noErrOr(error: MidlyError.auStopFail)
            
            for samplerUnit in samplerUnits {
                try AudioUnitReset(samplerUnit, kAudioUnitScope_Global, 0)
                    .noErrOr(error: MidlyError.auStopFail)
            }
            
            try AudioUnitReset(ioUnit, kAudioUnitScope_Input, 0)
                .noErrOr(error: MidlyError.auStopFail)
            
            onQueue.purge()
            offQueue.purge()
            
            isRunning = false
        }
    }
    
    public func resume() throws {
        try AudioOutputUnitStart(ioUnit)
            .noErrOr(error: MidlyError.auResumeFail)
        didResume?()
    }
    
    public func pause() throws {
        try AudioOutputUnitStop(ioUnit)
            .noErrOr(error: MidlyError.auPauseFail)
        didPause?()
    }
    
    public func update(beats _beats: [Beat], asap: Bool = true) throws {
        beats = _beats
        
        if asap {
            repeat {
                guard let beat = offQueue.dequeue() else {
                    break
                }
                let offset = try toMach(duration: 0.25)
                let newBeat = OffBeat(
                    channel: beat.channel,
                    pitch: beat.pitch,
                    velocity: beat.velocity,
                    timestamp: mach_absolute_time() + offset)
                do {
                    try offQueue.enqueue(newBeat)
                }
                catch {}
            }
            while true
        }
        
        onQueue.purge()
        
        for beat in beats {
            try onQueue.enqueue(beat)
        }
    }
    
    public func update(bus _bus: Int) throws {
        let samplerUnit = samplerUnits[_bus]
        var conn = AudioUnitConnection(
            sourceAudioUnit: samplerUnit,
            sourceOutputNumber: 0,
            destInputNumber: 0)
            
        try AudioUnitSetProperty(
            ioUnit,
            kAudioUnitProperty_MakeConnection,
            kAudioUnitScope_Input,
            0,
            &conn,
            UInt32(MemoryLayout<AudioUnitConnection>.size))
            .noErrOr(error: MidlyError.samplerConnFail)
        
        bus.store(_bus, ordering: .relaxed)
    }
    
    public func onBeat(_ callback: @escaping BeatClosure) {
        didBeat = callback
    }
    
    public func onPause(_ callback: @escaping VoidClosure) {
        didPause = callback
    }
    
    public func onResume(_ callback: @escaping VoidClosure) {
        didResume = callback
    }
    
    fileprivate func toMach(duration: Double) throws -> UInt64 {
        var machInfo = mach_timebase_info_data_t()
        if mach_timebase_info(&machInfo) != KERN_SUCCESS {
            throw MidlyError.machTimeFail
        }
        return UInt64(duration * 1000000000 * Double(machInfo.denom / machInfo.numer))
    }
    
    deinit {
        do {
            try stop()
        }
        catch {
            print(error)
        }
    }
}

private func notifyCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus
{
    guard ioActionFlags.pointee.contains(.unitRenderAction_PreRender) else {
        return noErr
    }
    
    let inRef = Unmanaged<Synth>.fromOpaque(inRefCon).takeUnretainedValue()
    let bus = inRef.bus.load(ordering: .relaxed)
    repeat {
        guard let offbeat = inRef.offQueue.head else {
            break
        }
        
        if offbeat.timestamp <= inTimeStamp.pointee.mHostTime {
            MusicDeviceMIDIEvent(
                inRef.samplerUnits[bus],
                Status.off.rawValue + offbeat.channel,
                offbeat.pitch,
                offbeat.velocity,
                0)
            
            _ = inRef.offQueue.dequeue()
        }
        else {
            break
        }
    }
    while true
    
    repeat {
        if let _ = inRef.offQueue.head {
            break
        }
    
        guard let onbeat = inRef.onQueue.dequeue() else {
            break
        }
        
        MusicDeviceMIDIEvent(
            inRef.samplerUnits[bus],
            Status.on.rawValue + onbeat.channel,
            onbeat.pitch,
            onbeat.velocity,
            0)
        
        DispatchQueue.main.async {
            inRef.didBeat?(onbeat)
        }
        
        do {
            let offset = try inRef.toMach(duration: onbeat.duration)
            let timestamp = inTimeStamp.pointee.mHostTime + offset
            let offbeat = OffBeat(
                channel: onbeat.channel,
                pitch: onbeat.pitch,
                velocity: onbeat.velocity,
                timestamp: timestamp)
        
            try inRef.onQueue.enqueue(onbeat)
            try inRef.offQueue.enqueue(offbeat)
        }
        catch {}
    }
    while true
    
    return noErr
}
