//
//  AudioPlayer.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/16.
//

import AudioToolbox
import CoreAudio

protocol AudioPlayerDelegate: AnyObject {
    func audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer, numberOfSamples: UInt32, numberOfChannels: UInt32)
    func audioPlayerWillRenderSample(sampleTimestamp: AudioTimeStamp)
    func audioPlayerDidRenderSample(sampleTimestamp: AudioTimeStamp)
}

protocol AudioPlayer: AnyObject {
    var delegate: AudioPlayerDelegate? { get set }
    var playbackRate: Float { get set }
    var volume: Float { get set }
    var isMuted: Bool { get set }
    func play()
    func pause()
}

final class AudioGraphPlayer: AudioPlayer {
    private let graph: AUGraph
    private var audioUnitForMixer: AudioUnit!
    private var audioUnitForTimePitch: AudioUnit!
    private var audioStreamBasicDescription = KSDefaultParameter.outputFormat()

    private var isPlaying: Bool {
        var running = DarwinBoolean(false)
        if AUGraphIsRunning(graph, &running) == noErr {
            return running.boolValue
        }
        return false
    }

    private var sampleRate: Float64 {
        return audioStreamBasicDescription.mSampleRate
    }

    private var numberOfChannels: UInt32 {
        return audioStreamBasicDescription.mChannelsPerFrame
    }

    weak var delegate: AudioPlayerDelegate?
    var playbackRate: Float {
        set {
            AudioUnitSetParameter(audioUnitForTimePitch, kNewTimePitchParam_Rate, kAudioUnitScope_Global, 0, newValue, 0)
        }
        get {
            var playbackRate = AudioUnitParameterValue(0.0)
            AudioUnitGetParameter(audioUnitForMixer, kNewTimePitchParam_Rate, kAudioUnitScope_Global, 0, &playbackRate)
            return playbackRate
        }
    }

    var volume: Float {
        set {
            AudioUnitSetParameter(audioUnitForMixer, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, newValue, 0)
        }
        get {
            var volume = AudioUnitParameterValue(0.0)
            AudioUnitGetParameter(audioUnitForMixer, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, &volume)
            return volume
        }
    }

    public var isMuted: Bool {
        set {
            let value = newValue ? 0 : 1
            AudioUnitSetParameter(audioUnitForMixer, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, 0, AudioUnitParameterValue(value), 0)
        }
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForMixer, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, 0, &value)
            return value == 0
        }
    }

    init() {
        var newGraph: AUGraph!
        NewAUGraph(&newGraph)
        graph = newGraph
        var descriptionForTimePitch = AudioComponentDescription()
        descriptionForTimePitch.componentType = kAudioUnitType_FormatConverter
        descriptionForTimePitch.componentSubType = kAudioUnitSubType_NewTimePitch
        descriptionForTimePitch.componentManufacturer = kAudioUnitManufacturer_Apple

        var descriptionForMixer = AudioComponentDescription()
        descriptionForMixer.componentType = kAudioUnitType_Mixer
        descriptionForMixer.componentManufacturer = kAudioUnitManufacturer_Apple
        #if os(macOS) || targetEnvironment(macCatalyst)
        descriptionForMixer.componentSubType = kAudioUnitSubType_SpatialMixer
        #else
        descriptionForMixer.componentSubType = kAudioUnitSubType_MultiChannelMixer
        #endif
        var descriptionForOutput = AudioComponentDescription()
        descriptionForOutput.componentType = kAudioUnitType_Output
        descriptionForOutput.componentManufacturer = kAudioUnitManufacturer_Apple
        #if os(macOS)
        descriptionForOutput.componentSubType = kAudioUnitSubType_DefaultOutput
        #else
        descriptionForOutput.componentSubType = kAudioUnitSubType_RemoteIO
        #endif
        var nodeForTimePitch = AUNode()
        var nodeForMixer = AUNode()
        var nodeForOutput = AUNode()
        var audioUnitForOutput: AudioUnit!
        AUGraphAddNode(graph, &descriptionForTimePitch, &nodeForTimePitch)
        AUGraphAddNode(graph, &descriptionForMixer, &nodeForMixer)
        AUGraphAddNode(graph, &descriptionForOutput, &nodeForOutput)
        AUGraphOpen(graph)
        AUGraphConnectNodeInput(graph, nodeForTimePitch, 0, nodeForMixer, 0)
        AUGraphConnectNodeInput(graph, nodeForMixer, 0, nodeForOutput, 0)
        AUGraphNodeInfo(graph, nodeForTimePitch, &descriptionForTimePitch, &audioUnitForTimePitch)
        AUGraphNodeInfo(graph, nodeForMixer, &descriptionForMixer, &audioUnitForMixer)
        AUGraphNodeInfo(graph, nodeForOutput, &descriptionForOutput, &audioUnitForOutput)
        let inDataSize = UInt32(MemoryLayout.size(ofValue: KSDefaultParameter.audioPlayerMaximumFramesPerSlice))
        AudioUnitSetProperty(audioUnitForTimePitch,
                             kAudioUnitProperty_MaximumFramesPerSlice,
                             kAudioUnitScope_Global, 0,
                             &KSDefaultParameter.audioPlayerMaximumFramesPerSlice,
                             inDataSize)
        AudioUnitSetProperty(audioUnitForMixer,
                             kAudioUnitProperty_MaximumFramesPerSlice,
                             kAudioUnitScope_Global, 0,
                             &KSDefaultParameter.audioPlayerMaximumFramesPerSlice,
                             inDataSize)
        AudioUnitSetProperty(audioUnitForOutput,
                             kAudioUnitProperty_MaximumFramesPerSlice,
                             kAudioUnitScope_Global, 0,
                             &KSDefaultParameter.audioPlayerMaximumFramesPerSlice,
                             inDataSize)
        var inputCallbackStruct = renderCallbackStruct()
        AUGraphSetNodeInputCallback(graph, nodeForTimePitch, 0, &inputCallbackStruct)
        addRenderNotify(audioUnit: audioUnitForOutput)
        let audioStreamBasicDescriptionSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        AudioUnitSetProperty(audioUnitForTimePitch,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, 0,
                             &audioStreamBasicDescription,
                             audioStreamBasicDescriptionSize)
        AudioUnitSetProperty(audioUnitForTimePitch,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Output, 0,
                             &audioStreamBasicDescription,
                             audioStreamBasicDescriptionSize)
        AudioUnitSetProperty(audioUnitForMixer,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, 0,
                             &audioStreamBasicDescription,
                             audioStreamBasicDescriptionSize)
        AudioUnitSetProperty(audioUnitForMixer,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Output, 0,
                             &audioStreamBasicDescription,
                             audioStreamBasicDescriptionSize)
        AudioUnitSetProperty(audioUnitForOutput,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, 0,
                             &audioStreamBasicDescription,
                             audioStreamBasicDescriptionSize)
        AudioUnitSetProperty(audioUnitForOutput,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, 0,
                             &audioStreamBasicDescription,
                             audioStreamBasicDescriptionSize)
        AUGraphInitialize(graph)
    }

    private func renderCallbackStruct() -> AURenderCallbackStruct {
        var inputCallbackStruct = AURenderCallbackStruct()
        inputCallbackStruct.inputProcRefCon = Unmanaged.passUnretained(self).toOpaque()
        inputCallbackStruct.inputProc = { refCon, _, _, _, inNumberFrames, ioData in
            guard let ioData = ioData else {
                return noErr
            }
            let `self` = Unmanaged<AudioGraphPlayer>.fromOpaque(refCon).takeUnretainedValue()
            self.delegate?.audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer(ioData), numberOfSamples: inNumberFrames, numberOfChannels: self.numberOfChannels)
            return noErr
        }
        return inputCallbackStruct
    }

    private func addRenderNotify(audioUnit: AudioUnit) {
        AudioUnitAddRenderNotify(audioUnit, { refCon, ioActionFlags, inTimeStamp, _, _, _ in
            let `self` = Unmanaged<AudioGraphPlayer>.fromOpaque(refCon).takeUnretainedValue()
            if ioActionFlags.pointee.contains(.unitRenderAction_PreRender) {
                self.delegate?.audioPlayerWillRenderSample(sampleTimestamp: inTimeStamp.pointee)
            } else if ioActionFlags.pointee.contains(.unitRenderAction_PostRender) {
                self.delegate?.audioPlayerDidRenderSample(sampleTimestamp: inTimeStamp.pointee)
            }
            return noErr
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func play() {
        if !isPlaying {
            AUGraphStart(graph)
        }
    }

    func pause() {
        if isPlaying {
            AUGraphStop(graph)
        }
    }

    deinit {
        AUGraphStop(graph)
        AUGraphUninitialize(graph)
        AUGraphClose(graph)
        DisposeAUGraph(graph)
    }
}

import AVFoundation

import Accelerate

extension AVAudioPlayerNode {
//    func schedule(at: AVAudioTime? = nil, channels c: Int, format: AVAudioFormat, audioDatas datas: [UnsafePointer<UInt8>], floatsLength: Int, samples: Int, completion: AVAudioNodeCompletionHandler? ) {
//
//        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(floatsLength)) else { return }
//        buf.frameLength = AVAudioFrameCount(samples)
//        let channels = buf.floatChannelData
//        for i in 0..<datas.count {
//            let data = datas[i]
//            guard let channel = channels?[i % c] else {
//                break
//            }
//            let floats = data.withMemoryRebound(to: Float.self, capacity: floatsLength){$0}
//            if i < c {
//                cblas_scopy(Int32(floatsLength), floats, 1, channel, 1)
//            } else {
//                vDSP_vadd(channel, 1, floats, 1, channel, 1, vDSP_Length(floatsLength))
//            }
//        }
//
//        self.scheduleBuffer(buf, completionHandler: completion)
//    }
}

@available(OSX 10.13, tvOS 11.0, iOS 11.0, *)
final class AudioEnginePlayer: AudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let picth = AVAudioUnitTimePitch()
    weak var delegate: AudioPlayerDelegate?

    var playbackRate: Float {
        get {
            return picth.rate
        }
        set {
            picth.rate = min(32, max(1.0 / 32.0, newValue))
        }
    }

    var volume: Float {
        get {
            return player.volume
        }
        set {
            player.volume = newValue
        }
    }

    var isMuted: Bool {
        get {
            return volume == 0
        }
        set {}
    }

    init() {
        engine.attach(player)
        engine.attach(picth)
        let format = KSDefaultParameter.audioDefaultFormat
        engine.connect(player, to: picth, format: format)
        engine.connect(picth, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try? engine.enableManualRenderingMode(.realtime, format: format, maximumFrameCount: KSDefaultParameter.audioPlayerMaximumFramesPerSlice)
//        engine.inputNode.setManualRenderingInputPCMFormat(format) { count -> UnsafePointer<AudioBufferList>? in
//            self.delegate?.audioPlayerShouldInputData(ioData: <#T##UnsafeMutableAudioBufferListPointer#>, numberOfSamples: <#T##UInt32#>, numberOfChannels: <#T##UInt32#>)
//        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func audioPlay(buffer: AVAudioPCMBuffer) {
        player.scheduleBuffer(buffer, completionHandler: nil)
    }
}

extension AVAudioFormat {
    func toPCMBuffer(data: NSData) -> AVAudioPCMBuffer? {
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: self, frameCapacity: UInt32(data.length) / streamDescription.pointee.mBytesPerFrame) else {
            return nil
        }
        pcmBuffer.frameLength = pcmBuffer.frameCapacity
        let channels = UnsafeBufferPointer(start: pcmBuffer.floatChannelData, count: Int(pcmBuffer.format.channelCount))
        data.getBytes(UnsafeMutableRawPointer(channels[0]), length: data.length)
        return pcmBuffer
    }
}
