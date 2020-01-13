//
//  KSPlayerLayerView.swift
//  Pods
//
//  Created by kintan on 16/4/28.
//
//
import AVFoundation
import MediaPlayer
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
/**
 Player status emun
 - notSetURL:      not set url yet
 - readyToPlay:    player ready to play
 - buffering:      player buffering
 - bufferFinished: buffer finished
 - playedToTheEnd: played to the End
 - error:          error with playing
 */
public enum KSPlayerState: CustomStringConvertible {
    case notSetURL
    case readyToPlay
    case buffering
    case bufferFinished
    case paused
    case playedToTheEnd
    case error
    public var description: String {
        switch self {
        case .notSetURL:
            return "notSetURL"
        case .readyToPlay:
            return "readyToPlay"
        case .buffering:
            return "buffering"
        case .bufferFinished:
            return "bufferFinished"
        case .paused:
            return "paused"
        case .playedToTheEnd:
            return "playedToTheEnd"
        case .error:
            return "error"
        }
    }

    public var isPlaying: Bool {
        return self == .buffering || self == .bufferFinished
    }
}

public protocol KSPlayerLayerDelegate: AnyObject {
    func player(layer: KSPlayerLayer, state: KSPlayerState)
    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval)
    func player(layer: KSPlayerLayer, finish error: Error?)
    func player(layer: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval)
}

open class KSPlayerLayer: UIView {
    public let bufferingProgress: KSObservable<Int> = KSObservable(0)
    public let loopCount: KSObservable<Int> = KSObservable(0)
    private var timer: Timer?
    private var playOptions: [String: Any]?
    private var bufferedCount = 0
    private var shouldSeekTo: TimeInterval = 0
    private var startTime: TimeInterval = 0
    private(set) var url: URL?
    public var isWirelessRouteActive = false
    public weak var delegate: KSPlayerLayerDelegate?
    public var isAutoPlay = KSPlayerManager.isAutoPlay {
        didSet {
            player?.isAutoPlay = isAutoPlay
        }
    }

    public var player: MediaPlayerProtocol? {
        didSet {
            oldValue?.view.removeFromSuperview()
            oldValue?.shutdown()
            if let player = player {
                KSLog("player is \(player)")
                player.delegate = self
                player.isAutoPlay = isAutoPlay
                player.isLoopPlay = KSPlayerManager.isLoopPlay
                player.contentMode = .scaleAspectFit
                if let oldValue = oldValue {
                    player.playbackRate = oldValue.playbackRate
                    player.playbackVolume = oldValue.playbackVolume
                }
                addSubview(player.view)
                prepareToPlay()
                player.view.frame = bounds
            }
        }
    }

    /// 播发器的几种状态
    public private(set) var state = KSPlayerState.notSetURL {
        didSet {
            if state != oldValue {
                KSLog("playerStateDidChange - \(state)")
                delegate?.player(layer: self, state: state)
            }
        }
    }

    deinit {
        resetPlayer()
    }

    public func set(url: URL, options: [String: Any]?, display: DisplayEnum = .plane) {
        self.url = url
        playOptions = options
        if let cookies = playOptions?["Cookie"] as? [HTTPCookie] {
            #if !os(macOS)
            playOptions?[AVURLAssetHTTPCookiesKey] = cookies
            #endif
            var cookieStr = "Cookie: "
            for cookie in cookies {
                cookieStr.append("\(cookie.name)=\(cookie.value); ")
            }
            cookieStr = String(cookieStr.dropLast(2))
            cookieStr.append("\r\n")
            playOptions?["headers"] = cookieStr
        }
        let firstPlayerType: MediaPlayerProtocol.Type
        if isWirelessRouteActive {
            // airplay的话，默认使用KSAVPlayer
            firstPlayerType = KSAVPlayer.self
        } else if display != .plane {
            // AR模式只能用KSMEPlayer
            // swiftlint:disable force_cast
            firstPlayerType = NSClassFromString("KSPlayer.KSMEPlayer") as! MediaPlayerProtocol.Type
            // swiftlint:enable force_cast
        } else {
            firstPlayerType = KSPlayerManager.firstPlayerType
        }
        if let player = player, type(of: player) == firstPlayerType {
            player.replace(url: url, options: playOptions)
            prepareToPlay()
        } else {
            player = firstPlayerType.init(url: url, options: playOptions)
        }
        player?.display = display
        timer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(playerTimerAction), userInfo: nil, repeats: true)
        timer?.fireDate = Date.distantFuture
        registerRemoteControllEvent()
    }

    open func play() {
        UIApplication.shared.isIdleTimerDisabled = true
        isAutoPlay = true
        if let player = player {
            if player.isPreparedToPlay {
                player.play()
                timer?.fireDate = Date.distantPast
            } else {
                if state == .error {
                    player.prepareToPlay()
                }
            }
            state = player.loadState == .playable ? .bufferFinished : .buffering
        } else {
            state = .buffering
        }
    }

    open func pause() {
        if #available(OSX 10.12.2, *) {
            if let player = player {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                    MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentPlaybackTime,
                    MPMediaItemPropertyPlaybackDuration: player.duration,
                ]
            }
        }
        isAutoPlay = false
        player?.pause()
        timer?.fireDate = Date.distantFuture
        state = .paused
        UIApplication.shared.isIdleTimerDisabled = false
    }

    open func resetPlayer() {
        KSLog("resetPlayer")
        unregisterRemoteControllEvent()
        timer?.invalidate()
        timer = nil
        state = .notSetURL
        bufferedCount = 0
        shouldSeekTo = 0
        isAutoPlay = KSPlayerManager.isAutoPlay
        player?.playbackRate = 1
        player?.playbackVolume = 1
        player?.shutdown()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    open func seek(time: TimeInterval, autoPlay: Bool = KSPlayerManager.isSeekedAutoPlay, completion handler: ((Bool) -> Void)? = nil) {
        if time.isInfinite || time.isNaN {
            return
        }
        if autoPlay {
            state = .buffering
        }
        if let player = player, player.isPreparedToPlay {
            player.seek(time: time) { [weak self] finished in
                guard let self = self else { return }
                if finished, autoPlay {
                    self.play()
                }
                handler?(finished)
            }
        } else {
            isAutoPlay = autoPlay
            shouldSeekTo = time
        }
    }

    #if os(macOS)
    open override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        player?.view.frame = bounds
    }

    #else
    open override func layoutSubviews() {
        super.layoutSubviews()
        player?.view.frame = bounds
    }
    #endif
}

// MARK: - MediaPlayerDelegate

extension KSPlayerLayer: MediaPlayerDelegate {
    public func preparedToPlay(player: MediaPlayerProtocol) {
        if #available(OSX 10.12.2, *) {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyPlaybackDuration: player.duration,
            ]
        }
        state = .readyToPlay
        if player.isAutoPlay {
            if shouldSeekTo > 0 {
                seek(time: shouldSeekTo, autoPlay: true) { [weak self] _ in
                    guard let self = self else { return }
                    self.shouldSeekTo = 0
                }
            } else {
                play()
            }
        }
    }

    public func changeLoadState(player: MediaPlayerProtocol) {
        guard player.playbackState != .seeking else { return }
        if player.loadState == .playable, startTime > 0 {
            let diff = CACurrentMediaTime() - startTime
            delegate?.player(layer: self, bufferedCount: bufferedCount, consumeTime: diff)
            if bufferedCount == 0 {
                KSLog("首屏耗时：\(diff)")
            }
            bufferedCount += 1
            startTime = 0
        }
        guard state.isPlaying else { return }
        if player.loadState == .playable {
            state = .bufferFinished
        } else {
            if state == .bufferFinished {
                startTime = CACurrentMediaTime()
            }
            state = .buffering
        }
    }

    public func changeBuffering(player _: MediaPlayerProtocol, progress: Int) {
        bufferingProgress.value = progress
    }

    public func playBack(player _: MediaPlayerProtocol, loopCount: Int) {
        self.loopCount.value = loopCount
    }

    public func finish(player: MediaPlayerProtocol, error: Error?) {
        if let error = error as NSError? {
            if error.domain == "AVMoviePlayer" || error.domain == AVFoundationErrorDomain, let secondPlayerType = KSPlayerManager.secondPlayerType {
                player.shutdown()
                self.player = secondPlayerType.init(url: url!, options: playOptions)
                return
            }
            state = .error
        } else {
            let duration = player.duration
            delegate?.player(layer: self, currentTime: duration, totalTime: duration)
            state = .playedToTheEnd
        }
        timer?.fireDate = Date.distantFuture
        bufferedCount = 1
        delegate?.player(layer: self, finish: error)
    }
}

// MARK: - private functions

extension KSPlayerLayer {
    private func prepareToPlay() {
        startTime = CACurrentMediaTime()
        bufferedCount = 0
        player?.prepareToPlay()
        if isAutoPlay {
            state = .buffering
        } else {
            state = .notSetURL
        }
    }

    @objc private func playerTimerAction() {
        guard let player = player, player.isPreparedToPlay else { return }
        delegate?.player(layer: self, currentTime: player.currentPlaybackTime, totalTime: player.duration)
        if player.playbackState == .playing, player.loadState == .playable, state == .buffering {
            // 一个兜底保护，正常不能走到这里
            state = .bufferFinished
        }
    }

    private func registerRemoteControllEvent() {
        if #available(OSX 10.12.2, *) {
            MPRemoteCommandCenter.shared().playCommand.addTarget(self, action: #selector(remoteCommandAction(event:)))
            MPRemoteCommandCenter.shared().pauseCommand.addTarget(self, action: #selector(remoteCommandAction(event:)))
            MPRemoteCommandCenter.shared().togglePlayPauseCommand.addTarget(self, action: #selector(remoteCommandAction(event:)))
            MPRemoteCommandCenter.shared().seekForwardCommand.addTarget(self, action: #selector(remoteCommandAction(event:)))
            MPRemoteCommandCenter.shared().seekBackwardCommand.addTarget(self, action: #selector(remoteCommandAction(event:)))
            MPRemoteCommandCenter.shared().changePlaybackRateCommand.addTarget(self, action: #selector(remoteCommandAction(event:)))
        }
        if #available(iOS 9.1, OSX 10.12.2, *) {
            MPRemoteCommandCenter.shared().changePlaybackPositionCommand.addTarget(self, action: #selector(remoteCommandAction(event:)))
        }
    }

    private func unregisterRemoteControllEvent() {
        if #available(OSX 10.12.2, *) {
            MPRemoteCommandCenter.shared().playCommand.removeTarget(self)
            MPRemoteCommandCenter.shared().pauseCommand.removeTarget(self)
            MPRemoteCommandCenter.shared().togglePlayPauseCommand.removeTarget(self)
            MPRemoteCommandCenter.shared().seekForwardCommand.removeTarget(self)
            MPRemoteCommandCenter.shared().seekBackwardCommand.removeTarget(self)
            MPRemoteCommandCenter.shared().changePlaybackRateCommand.removeTarget(self)
        }
        if #available(iOS 9.1, OSX 10.12.2, *) {
            MPRemoteCommandCenter.shared().changePlaybackPositionCommand.removeTarget(self)
        }
    }

    @available(OSX 10.12.2, *)
    @objc private func remoteCommandAction(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard let player = player else {
            return .noSuchContent
        }
        if event.command == MPRemoteCommandCenter.shared().playCommand {
            play()
        } else if event.command == MPRemoteCommandCenter.shared().pauseCommand {
            pause()
        } else if event.command == MPRemoteCommandCenter.shared().togglePlayPauseCommand {
            if state.isPlaying {
                pause()
            } else {
                play()
            }
        } else if event.command == MPRemoteCommandCenter.shared().seekForwardCommand {
            seek(time: player.currentPlaybackTime + player.duration * 0.01)
        } else if event.command == MPRemoteCommandCenter.shared().seekBackwardCommand {
            seek(time: player.currentPlaybackTime - player.duration * 0.01)
        } else if let event = event as? MPChangePlaybackPositionCommandEvent {
            seek(time: event.positionTime)
        } else if let event = event as? MPChangePlaybackRateCommandEvent {
            player.playbackRate = event.playbackRate
        }
        return .success
    }
}
