import AVFoundation

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
public final class KSAVPlayerView: UIView {
    public let player = AVQueuePlayer()
    public override init(frame: CGRect) {
        super.init(frame: frame)
        #if os(macOS)
        layer = AVPlayerLayer()
        #endif
        playerLayer.player = player
        if #available(iOS 10.0, OSX 10.12, *) {
            player.automaticallyWaitsToMinimizeStalling = false
        }
    }

    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    #if os(macOS)
    override var contentMode: UIViewContentMode {
        get {
            switch playerLayer.videoGravity {
            case .resize:
                return .scaleToFill
            case .resizeAspect:
                return .scaleAspectFit
            case .resizeAspectFill:
                return .scaleAspectFill
            default:
                return .scaleAspectFit
            }
        }
        set {
            switch newValue {
            case .scaleToFill:
                playerLayer.videoGravity = .resize
            case .scaleAspectFit:
                playerLayer.videoGravity = .resizeAspect
            case .scaleAspectFill:
                playerLayer.videoGravity = .resizeAspectFill
            case .center:
                playerLayer.videoGravity = .resizeAspect
            default:
                break
            }
        }
    }

    #else
    public override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    public override var contentMode: UIViewContentMode {
        didSet {
            switch contentMode {
            case .scaleToFill:
                playerLayer.videoGravity = .resize
            case .scaleAspectFit, .center:
                playerLayer.videoGravity = .resizeAspect
            case .scaleAspectFill:
                playerLayer.videoGravity = .resizeAspectFill
            default:
                break
            }
        }
    }
    #endif
    fileprivate var playerLayer: AVPlayerLayer {
        // swiftlint:disable force_cast
        return layer as! AVPlayerLayer
        // swiftlint:enable force_cast
    }
}

public class KSAVPlayer {
    private let playerView = KSAVPlayerView()
    private var urlAsset: AVURLAsset
    private var shouldSeekTo = TimeInterval(0)
    private var playerLooper: NSObject?
    private var statusObservation: NSKeyValueObservation?
    private var loadedTimeRangesObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var likelyToKeepUpObservation: NSKeyValueObservation?
    private var bufferFullObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var loopCountObservation: NSKeyValueObservation?
    private var loopStatusObservation: NSKeyValueObservation?
    private var error: Error? {
        didSet {
            if let error = error {
                delegate?.finish(player: self, error: error)
            }
        }
    }

    public private(set) var bufferingProgress = 0 {
        didSet {
            delegate?.changeBuffering(player: self, progress: bufferingProgress)
        }
    }

    public var isAutoPlay = true
    public var display: DisplayEnum = .plane
    public weak var delegate: MediaPlayerDelegate?
    public private(set) var duration: TimeInterval = 0
    public private(set) var playableTime: TimeInterval = 0
    public var isLoopPlay = false {
        didSet {
            if isLoopPlay {
                if playerLooper == nil, let playerItem = player.currentItem {
                    setPlayerLooper(playerItem: playerItem)
                }
            } else {
                playerLooper = nil
            }
        }
    }

    public var playbackRate: Float = 1 {
        didSet {
            if playbackState == .playing {
                player.rate = playbackRate
            }
        }
    }

    public var playbackVolume: Float = 1.0 {
        didSet {
            if player.volume != playbackVolume {
                player.volume = playbackVolume
            }
        }
    }

    public private(set) var loadState = MediaLoadState.idle {
        didSet {
            if loadState != oldValue {
                playOrPause()
                if loadState == .loading || loadState == .idle {
                    bufferingProgress = 0
                }
            }
        }
    }

    public private(set) var playbackState = MediaPlaybackState.idle {
        didSet {
            if playbackState != oldValue {
                playOrPause()
                if playbackState == .finished {
                    delegate?.finish(player: self, error: nil)
                }
            }
        }
    }

    public private(set) var isPreparedToPlay = false {
        didSet {
            if isPreparedToPlay != oldValue {
                if isPreparedToPlay {
                    if isAutoPlay {
                        play()
                    }
                    delegate?.preparedToPlay(player: self)
                }
            }
        }
    }

    public required init(url: URL, options: [String: Any]? = nil) {
        urlAsset = AVURLAsset(url: url, options: options)
        setAudioSession()
        itemObservation = player.observe(\.currentItem) { [weak self] player, _ in
            guard let self = self else { return }
            self.observer(playerItem: player.currentItem)
        }
    }
}

extension KSAVPlayer {
    public var player: AVQueuePlayer {
        return playerView.player
    }

    @objc private func moviePlayDidEnd(notification _: Notification) {
        if !isLoopPlay {
            playbackState = .finished
        }
    }

    @objc private func playerItemFailedToPlayToEndTime(notification: Notification) {
        var playError: Error?
        if let userInfo = notification.userInfo {
            if let error = userInfo["error"] as? Error {
                playError = error
            } else if let error = userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError {
                playError = error
            } else if let errorCode = (userInfo["error"] as? NSNumber)?.intValue {
                playError = NSError(domain: AVFoundationErrorDomain, code: errorCode, userInfo: nil)
            }
        }
        delegate?.finish(player: self, error: playError)
    }

    private func updateStatus(item: AVPlayerItem) {
        if item.status == .readyToPlay {
            let videoTrack = item.tracks.first { $0.assetTrack?.mediaType.rawValue == AVMediaType.video.rawValue }
            if let videoTrack = videoTrack, videoTrack.assetTrack?.isPlayable == false {
                error = NSError(domain: AVFoundationErrorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: "can't player"])
                return
            }
            // 默认选择第一个声道
            item.tracks.filter { $0.assetTrack?.mediaType.rawValue == AVMediaType.audio.rawValue }.dropFirst().forEach { $0.isEnabled = false }
            duration = item.duration.seconds
            isPreparedToPlay = true
        } else if item.status == .failed {
            error = item.error
        }
    }

    private func updatePlayableDuration(item: AVPlayerItem) {
        let first = item.loadedTimeRanges.first { CMTimeRangeContainsTime($0.timeRangeValue, time: item.currentTime()) }
        if let first = first {
            updatePlayableDuration(time: first.timeRangeValue.end)
        }
    }

    private func updatePlayableDuration(time: CMTime) {
        playableTime = time.seconds
        guard playableTime > 0 else { return }
        let loadedTime = playableTime - currentPlaybackTime
        guard loadedTime > 0 else { return }
        bufferingProgress = Int(min(loadedTime * 100 / preferredForwardBufferDuration, 100))
        if bufferingProgress >= 100 {
            loadState = .playable
        }
    }

    private func playOrPause() {
        if playbackState == .playing {
            if loadState == .playable {
                player.play()
                player.rate = playbackRate
            }
        } else {
            player.pause()
        }
        delegate?.changeLoadState(player: self)
    }

    private func setPlayerLooper(playerItem: AVPlayerItem) {
        if #available(iOS 10.0, OSX 10.12, *) {
            player.actionAtItemEnd = .advance
            let playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
            loopCountObservation?.invalidate()
            loopCountObservation = playerLooper.observe(\.loopCount) { [weak self] playerLooper, _ in
                guard let self = self else { return }
                self.delegate?.playBack(player: self, loopCount: playerLooper.loopCount)
            }
            loopStatusObservation?.invalidate()
            loopStatusObservation = playerLooper.observe(\.status) { [weak self] playerLooper, _ in
                guard let self = self else { return }
                if playerLooper.status == .failed {
                    self.error = playerLooper.error
                }
            }
            self.playerLooper = playerLooper
        } else {
            error = NSError(domain: AVFoundationErrorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: "KSAVPlayer not support loop play for iOS 9 and OSX 10.11"])
        }
    }

    private func observer(playerItem: AVPlayerItem?) {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
        statusObservation?.invalidate()
        loadedTimeRangesObservation?.invalidate()
        bufferEmptyObservation?.invalidate()
        likelyToKeepUpObservation?.invalidate()
        bufferFullObservation?.invalidate()
        guard let playerItem = playerItem else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(moviePlayDidEnd), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemFailedToPlayToEndTime), name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
        statusObservation = playerItem.observe(\.status) { [weak self] item, _ in
            guard let self = self else { return }
            self.updateStatus(item: item)
        }
        loadedTimeRangesObservation = playerItem.observe(\.loadedTimeRanges) { [weak self] item, _ in
            guard let self = self else { return }
            // 计算缓冲进度
            self.updatePlayableDuration(item: item)
        }

        let changeHandler: (AVPlayerItem, NSKeyValueObservedChange<Bool>) -> Void = { [weak self] _, _ in
            guard let self = self else { return }
            // 在主线程更新进度
            if playerItem.isPlaybackBufferEmpty {
                self.loadState = .loading
            } else if playerItem.isPlaybackLikelyToKeepUp || playerItem.isPlaybackBufferFull {
                self.loadState = .playable
            }
        }
        bufferEmptyObservation = playerItem.observe(\.isPlaybackBufferEmpty, changeHandler: changeHandler)
        likelyToKeepUpObservation = playerItem.observe(\.isPlaybackLikelyToKeepUp, changeHandler: changeHandler)
        bufferFullObservation = playerItem.observe(\.isPlaybackBufferFull, changeHandler: changeHandler)
    }
}

extension KSAVPlayer: MediaPlayerProtocol {
    public var subtitleDataSouce: SubtitleDataSouce? {
        return nil
    }

    public var preferredForwardBufferDuration: TimeInterval {
        get {
            return KSPlayerManager.preferredForwardBufferDuration
        }
        set {
            if #available(iOS 10.0, OSX 10.12, *) {
                player.currentItem?.preferredForwardBufferDuration = newValue
            }
            KSPlayerManager.preferredForwardBufferDuration = newValue
        }
    }

    public func thumbnailImageAtCurrentTime(handler: @escaping (UIImage?) -> Void) {
        guard let playerItem = player.currentItem, isPreparedToPlay else {
            return handler(nil)
        }
        return urlAsset.thumbnailImage(currentTime: playerItem.currentTime(), handler: handler)
    }

    public var isPlaying: Bool {
        if player.rate > 0 {
            return true
        }
        return playbackState == .playing
    }

    public var view: UIView {
        return playerView
    }

    public var allowsExternalPlayback: Bool {
        get {
            return player.allowsExternalPlayback
        }
        set {
            player.allowsExternalPlayback = newValue
        }
    }

    public var usesExternalPlaybackWhileExternalScreenIsActive: Bool {
        get {
            #if os(macOS)
            return false
            #else
            return player.usesExternalPlaybackWhileExternalScreenIsActive
            #endif
        }
        set {
            #if !os(macOS)
            player.usesExternalPlaybackWhileExternalScreenIsActive = newValue
            #endif
        }
    }

    public var isExternalPlaybackActive: Bool {
        return player.isExternalPlaybackActive
    }

    public var naturalSize: CGSize {
        if let videoTrack = urlAsset.tracks(withMediaType: .video).first {
            return videoTrack.naturalSize
        } else {
            return .zero
        }
    }

    public var currentPlaybackTime: TimeInterval {
        get {
            if shouldSeekTo > 0 {
                return TimeInterval(shouldSeekTo)
            } else {
                // 防止卡主
                return isPreparedToPlay ? player.currentTime().seconds : 0
            }
        }
        set {
            seek(time: newValue)
        }
    }

    public var numberOfBytesTransferred: Int64 {
        guard let playerItem = player.currentItem, let accesslog = playerItem.accessLog(), let event = accesslog.events.first else {
            return 0
        }
        return event.numberOfBytesTransferred
    }

    public func seek(time: TimeInterval, completion handler: ((Bool) -> Void)? = nil) {
        guard time >= 0 else { return }
        shouldSeekTo = time
        let oldPlaybackState = playbackState
        playbackState = .seeking
        runInMainqueue { [weak self] in
            self?.bufferingProgress = 0
        }
        let tolerance: CMTime = KSPlayerManager.isAccurateSeek ? .zero : .positiveInfinity
        player.seek(to: CMTime(seconds: time, preferredTimescale: Int32(NSEC_PER_SEC)), toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            guard let self = self else { return }
            self.playbackState = oldPlaybackState
            self.shouldSeekTo = 0
            handler?(finished)
        }
    }

    public func prepareToPlay() {
        KSLog("prepareToPlay \(self)")
        runInMainqueue { [weak self] in
            guard let self = self else { return }
            self.bufferingProgress = 0
            let playerItem = AVPlayerItem(asset: self.urlAsset)
            if self.isLoopPlay {
                self.setPlayerLooper(playerItem: playerItem)
            } else {
                self.player.replaceCurrentItem(with: playerItem)
                self.player.actionAtItemEnd = .pause
            }
            self.player.volume = self.playbackVolume
        }
    }

    public func play() {
        KSLog("play \(self)")
        playbackState = .playing
    }

    public func pause() {
        KSLog("pause \(self)")
        playbackState = .paused
    }

    public func shutdown() {
        KSLog("shutdown \(self)")
        isPreparedToPlay = false
        playbackState = .stopped
        loadState = .idle
        player.currentItem?.cancelPendingSeeks()
        urlAsset.cancelLoading()
        player.replaceCurrentItem(with: nil)
    }

    public func replace(url: URL, options: [String: Any]? = nil) {
        KSLog("replaceUrl \(self)")
        shutdown()
        urlAsset = AVURLAsset(url: url, options: options)
    }

    public var contentMode: UIViewContentMode {
        set {
            view.contentMode = newValue
        }
        get {
            return view.contentMode
        }
    }

    public func enterBackground() {
        playerView.playerLayer.player = nil
    }

    public func enterForeground() {
        playerView.playerLayer.player = playerView.player
    }

    public var isMuted: Bool {
        set {
            player.isMuted = newValue
            setAudioSession(isMuted: newValue)
        }
        get {
            return player.isMuted
        }
    }
}
