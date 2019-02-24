//
//  PlaybackController.swift
//  Relisten
//
//  Created by Alec Gorge on 7/3/17.
//  Copyright © 2017 Alec Gorge. All rights reserved.
//

import Foundation

import AGAudioPlayer
import Observable
import StoreKit
import Crashlytics
import AsyncDisplayKit

extension AGAudioPlayerViewController : TrackStatusActionHandler {
    public func trackButtonTapped(_ button: UIButton, forTrack track: Track) {
        TrackActions.showActionOptions(fromViewController: self, inView: button, forTrack: track)
    }
}

@objc public class PlaybackController : NSObject {
    public let playbackQueue: AGAudioPlayerUpNextQueue
    public let player: AGAudioPlayer
    public let viewController: AGAudioPlayerViewController
    public let shrinker: PlaybackMinibarShrinker
    
    public var observeCurrentTrack : Observable<Track?>
    public var trackWasPlayed : Observable<Track?>
    
    public var eventTrackPlaybackChanged : Event<Track?>
    public var eventTrackPlaybackStarted : Event<Track?>
    public var eventTrackWasPlayed : Event<Track>

    public var window: UIWindow? = nil
        
    public convenience init(withWindow window : UIWindow? = nil, previousPlaybackController: PlaybackController? = nil) {
        self.init()
        
        self.window = window
    }
    
    public required override init() {
        observeCurrentTrack = Observable<Track?>(nil)
        trackWasPlayed = Observable<Track?>(nil)
        
        eventTrackPlaybackChanged = Event<Track?>()
        eventTrackPlaybackStarted = Event<Track?>()
        eventTrackWasPlayed = Event<Track>()
        
        playbackQueue = AGAudioPlayerUpNextQueue()
        player = AGAudioPlayer(queue: playbackQueue)
        viewController = AGAudioPlayerViewController(player: player)
        
        shrinker = PlaybackMinibarShrinker(barHeight: viewController.barHeight)
        
        super.init()
        
        viewController.presentationDelegate = self
        viewController.cellDataSource = self
        viewController.delegate = self
    }
    
    public func inheritObservables(fromPlaybackController previous: PlaybackController) {
        self.observeCurrentTrack = previous.observeCurrentTrack
        self.trackWasPlayed = previous.trackWasPlayed
    
        self.eventTrackPlaybackChanged = previous.eventTrackPlaybackChanged
        self.eventTrackPlaybackStarted = previous.eventTrackPlaybackStarted
        self.eventTrackWasPlayed = previous.eventTrackWasPlayed
    }
    
    public func viewDidLoad() {
        viewController.loadViewIfNeeded()
    }
    
    enum CodingKey:String {
        case queue = "queue"
        case player = "player"
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError()
    }
    
    public func decodeRestorableState(with coder: NSCoder) {
        
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(playbackQueue, forKey: CodingKey.queue.rawValue)
        aCoder.encode(player, forKey: CodingKey.player.rawValue)
    }
    
    public static var supportsSecureCoding: Bool { get { return true } }
    
    public func displayMini(on vc: UIViewController, completion: (() -> Void)?) {
        if let nav = vc.navigationController {
            nav.delegate = shrinker
        }
        
        addBarIfNeeded()
        
        shrinker.fix(viewController: vc)
    }
    
    public func hideMini(_ completion: (() -> Void)? = nil) {
        if hasBarBeenAdded {
            UIView.animate(withDuration: 0.3, animations: {
                if let w = self.window {
                    self.viewController.view.frame = CGRect(
                        x: 0,
                        y: w.bounds.height,
                        width: self.viewController.view.bounds.width,
                        height: self.viewController.view.bounds.height
                    )
                }
            }, completion: { _ in
                if let c = completion {
                    c()
                }
            })
        }
    }
    
    public func display(_ completion: ((Bool) -> Void)? = nil) {
        viewController.viewWillAppear(true)
        viewController.switchToFullPlayer(animated: true)

        UIView.animate(withDuration: 0.3, animations: {
            self.viewController.view.frame = CGRect(
                x: 0,
                y: 0,
                width: self.viewController.view.bounds.width,
                height: self.viewController.view.bounds.height
            )
        }, completion: { (b) -> Void in self.viewController.viewDidAppear(true) })
    }
    
    public func dismiss(_ completion: ((Bool) -> Void)? = nil) {
        viewController.switchToMiniPlayer(animated: true)
        UIView.animate(withDuration: 0.3, animations: {
            if let w = self.window {
                self.viewController.view.frame = CGRect(
                    x: 0,
                    y: w.bounds.height - self.viewController.barHeight,
                    width: self.viewController.view.bounds.width,
                    height: self.viewController.view.bounds.height
                )
            }
        }, completion: completion)
    }
    
    public private(set) var hasBarBeenAdded = false
    public func addBarIfNeeded() {
        if !hasBarBeenAdded, let w = self.window {
            viewController.viewWillAppear(true)
            
            w.addSubview(viewController.view)
            
            viewController.viewDidAppear(true)
            
            let barHeight = viewController.barHeight
            let windowHeight = w.bounds.height
            
            viewController.view.frame = CGRect(
                x: 0,
                y: windowHeight,
                width: w.bounds.width,
                height: windowHeight
            )
            
            UIView.animate(withDuration: 0.3, animations: { 
                self.viewController.view.frame = CGRect(
                    x: 0,
                    y: windowHeight - barHeight,
                    width: w.bounds.width,
                    height: windowHeight
                )
            })
            
            hasBarBeenAdded = true
        }
    }

    private var cellContentViewWidth: CGFloat = CGFloat(0)
}

extension PlaybackController : AGAudioPlayerViewControllerPresentationDelegate {
    public func fullPlayerRequested() {
        display()
    }

    public func fullPlayerDismissRequested(fromProgress: CGFloat) {
        self.viewController.viewWillDisappear(true)
        
        UIView.animate(withDuration: 0.3, animations: {
            self.fullPlayerDismissProgress(1.0)
        }) { (b) in
            self.viewController.viewDidDisappear(true)
        }
    }
    
    func fullPlayerDismissProgress(_ progress: CGFloat) {
        if let w = self.window {
            
            var vFrame = viewController.view.frame
            
            vFrame.origin.y = (w.bounds.height - viewController.barHeight) * progress
            
            viewController.view.frame = vFrame
            
            viewController.switchToMiniPlayerProgress(progress)
        }
    }
    
    public func fullPlayerDismissUpdatedProgress(_ progress: CGFloat) {
        fullPlayerDismissProgress(progress)
    }
    
    public func fullPlayerDismissCancelled(fromProgress: CGFloat) {
        UIView.animate(withDuration: 0.3) {
            self.fullPlayerDismissProgress(0.0)
        }
    }
    
    public func fullPlayerStartedDismissing() {
        
    }
    
    public func fullPlayerOpenUpdatedProgress(_ progress: CGFloat) {
        fullPlayerDismissProgress(1.0 - progress)
    }
    
    public func fullPlayerOpenCancelled(fromProgress: CGFloat) {
        fullPlayerDismissRequested(fromProgress: fromProgress)
    }
    
    public func fullPlayerOpenRequested(fromProgress: CGFloat) {
        self.viewController.viewWillAppear(true)
        UIView.animate(withDuration: 0.3, animations: {
            self.fullPlayerDismissProgress(0.0)
        }) { (b) in
            self.viewController.viewDidAppear(true)
        }
    }
}

extension PlaybackController : TrackStatusActionHandler {
    public func trackButtonTapped(_ button: UIButton, forTrack track: Track) {
        TrackActions.showActionOptions(fromViewController: viewController, inView: button, forTrack: track)
    }
}

public class PlaybackMinibarShrinker: NSObject, UINavigationControllerDelegate {
    private let barHeight: CGFloat
    
    public init(barHeight: CGFloat) {
        self.barHeight = barHeight
    }
    
    public func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        fix(viewController: viewController)
    }
    
    public func fix(viewController: UIViewController) {
        if let nav = viewController as? UINavigationController {
            for vc in nav.viewControllers {
                fix(viewController: vc)
            }
        }
        else if let scroll = viewController.view as? UIScrollView {
            fix(scrollView: scroll)
        }
        else {
            for v in viewController.view.subviews {
                if let scroll = v as? UIScrollView {
                    fix(scrollView: scroll)
                }
            }
        }
    }
    
    public func fix(scrollView: UIScrollView) {
        var edges = scrollView.contentInset
        
        if edges.bottom < barHeight {
            edges.bottom += barHeight
        }
        
        scrollView.contentInset = edges
        
        edges = scrollView.scrollIndicatorInsets
        
        if edges.bottom < barHeight {
            edges.bottom += barHeight
        }
        
        scrollView.scrollIndicatorInsets = edges
    }
}

extension PlaybackController : AGAudioPlayerViewControllerDelegate {
    public func audioPlayerViewController(_ agAudio: AGAudioPlayerViewController, trackChangedState audioItem: AGAudioItem?) {
        guard let completeInfo = (audioItem as? SourceTrackAudioItem)?.track else { return }

        let _ = MyLibrary.shared.trackWasPlayed(completeInfo)
        
        eventTrackPlaybackChanged.raise(completeInfo)
        observeCurrentTrack.value = completeInfo
    }
    
    public func audioPlayerViewController(_ agAudio: AGAudioPlayerViewController, changedTrackTo audioItem: AGAudioItem?) {
        guard let completeInfo = (audioItem as? SourceTrackAudioItem)?.track else { return }

        eventTrackPlaybackStarted.raise(completeInfo)
        observeCurrentTrack.value = completeInfo
    }
    
    public func audioPlayerViewController(_ agAudio: AGAudioPlayerViewController, pressedDotsForAudioItem audioItem: AGAudioItem) {
        guard let completeInfo = (audioItem as? SourceTrackAudioItem)?.track else { return }
        
        TrackActions.showActionOptions(fromViewController: agAudio, inView: agAudio.uiMiniButtonDots, forTrack: completeInfo)
    }
    
    public func audioPlayerViewController(_ agAudio: AGAudioPlayerViewController, pressedPlusForAudioItem audioItem: AGAudioItem) {
        guard let completeInfo = (audioItem as? SourceTrackAudioItem)?.track else { return }

        let a = UIAlertController(
            title: "Favorite \(completeInfo.showInfo.show.display_date)?",
            message: "Would you like to add \(completeInfo.showInfo.show.display_date) to your favorites?",
            preferredStyle: .actionSheet
        )
        
        a.addAction(UIAlertAction(title: "Favorite ❤️", style: .default, handler: { (action) in
            MyLibrary.shared.favoriteSource(show: completeInfo.showInfo)
        }))
        
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        viewController.present(a, animated: true, completion: nil)
    }
    
    public func audioPlayerViewController(_ agAudio: AGAudioPlayerViewController, passedHalfWayFor audioItem: AGAudioItem) {
        guard let completeInfo = (audioItem as? SourceTrackAudioItem)?.track else { return }
        
        let _ = MyLibrary.shared.trackWasPlayed(completeInfo, pastHalfway: true)
        eventTrackWasPlayed.raise(completeInfo)
        trackWasPlayed.value = completeInfo
        
        RelistenApi.recordPlay(completeInfo.sourceTrack)
            .onFailure({ LogError("Failed to record play (perhaps you are offline?): \($0)")})
        
        if RelistenApp.sharedApp.launchCount > 2 {
            // If the app has been launched at least three full times and the user is halfway through a song they probably like the app.
            // Let's ask for a review.
#if !DEBUG
            // Don't prompt on debug builds since a request pops up every time for testing
            LogDebug("⭐️⭐️⭐️⭐️⭐️ Requesting a review. ⭐️⭐️⭐️⭐️⭐️ ")
            SKStoreReviewController.requestReview()
#endif
        }
    }
}

extension PlaybackController : AGAudioPlayerViewControllerCellDataSource {
    public func cell(inTableView tableView: UITableView, basedOnCell cell: UITableViewCell, atIndexPath: IndexPath, forPlaybackItem playbackItem: AGAudioItem, isCurrentlyPlaying: Bool) -> UITableViewCell {
        let completeInfo = (playbackItem as! SourceTrackAudioItem).track
        
        let trackNode = TrackStatusCellNode(
            withTrack: completeInfo,
            withHandler: viewController,
            usingExplicitTrackNumber: atIndexPath.row + 1,
            showingArtistInformation: true
        )
        trackNode.view.frame = CGRect(x: 0, y: 0, width: cell.frame.width - 64, height: cell.frame.height)
        for view in cell.contentView.subviews {
            view.removeFromSuperview()
        }
        cell.contentView.addSubview(trackNode.view)
        
        return cell
    }
    
    public func heightForCell(inTableView tableView: UITableView, atIndexPath: IndexPath, forPlaybackItem playbackItem: AGAudioItem, isCurrentlyPlaying: Bool) -> CGFloat {
        let completeInfo = (playbackItem as! SourceTrackAudioItem).track
        
        let trackNode = TrackStatusCellNode(
            withTrack: completeInfo,
            withHandler: viewController,
            usingExplicitTrackNumber: atIndexPath.row + 1,
            showingArtistInformation: true
        )
        trackNode.displaysAsynchronously = false
        let sizeRange = ASSizeRange(min: CGSize.zero, max: CGSize(width: UIScreen.main.bounds.size.width, height: CGFloat.greatestFiniteMagnitude))
        let layout = trackNode.layoutThatFits(sizeRange)
        
        return layout.size.height
    }
}

extension PlaybackController : AGAudioPlayerLoggingDelegate {
    public func audioPlayer(_ audioPlayer: AGAudioPlayer, loggedLine line: String) {
        LogDebug(line)
    }
    
    public func audioPlayer(_ audioPlayer: AGAudioPlayer, loggedErrorLine line: String) {
        LogError(line)
        
        let err = NSError(domain: "net.relisten.ios", code: 54, userInfo: [
            "assertion": line,
            "currentItemURL": player.currentItem?.playbackURL.absoluteString ?? "no url",
            "currentQueueURLs": player.queue.properQueue(forShuffleEnabled: player.shuffle).map({ $0.playbackURL.absoluteString }),
            "currentQueueUUIDs": player.queue.properQueue(forShuffleEnabled: player.shuffle).map({ ($0 as! SourceTrackAudioItem).track.uuid.uuidString }),
            "playbackPosition": player.elapsed
        ])
        
        Crashlytics.sharedInstance().recordError(err)
    }
}
