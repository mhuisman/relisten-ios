//
//  PlaybackController.swift
//  Relisten
//
//  Created by Alec Gorge on 7/3/17.
//  Copyright © 2017 Alec Gorge. All rights reserved.
//

import Foundation

import AGAudioPlayer

public class PlaybackController {
    public let playbackQueue: AGAudioPlayerUpNextQueue
    public let player: AGAudioPlayer
    public let viewController: AGAudioPlayerViewController
    public let shrinker: PlaybackMinibarShrinker
    
    public static var window: UIWindow? = nil
    
    public static let sharedInstance = PlaybackController()
    
    public required init() {
        playbackQueue = AGAudioPlayerUpNextQueue()
        player = AGAudioPlayer(queue: playbackQueue)
        viewController = AGAudioPlayerViewController(player: player)
        
        viewController.loadViewIfNeeded()
        
        shrinker = PlaybackMinibarShrinker(window: PlaybackController.window, barHeight: viewController.barHeight)

        viewController.presentationDelegate = self
    }
    
    public func displayMini(on vc: UIViewController, completion: (() -> Void)?) {
        if let nav = vc.navigationController {
            nav.delegate = shrinker
        }
        
        addBarIfNeeded()
        
        shrinker.fix(viewController: vc)
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
            if let w = PlaybackController.window {
                self.viewController.view.frame = CGRect(
                    x: 0,
                    y: w.bounds.height - self.viewController.barHeight,
                    width: self.viewController.view.bounds.width,
                    height: self.viewController.view.bounds.height
                )
            }
        }, completion: completion)
    }
    
    private var hasBarBeenAdded = false
    public func addBarIfNeeded() {
        if !hasBarBeenAdded, let w = PlaybackController.window {
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
        if let w = PlaybackController.window {
            
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

public class PlaybackMinibarShrinker: NSObject, UINavigationControllerDelegate {
    private let window: UIWindow?
    private let barHeight: CGFloat
    
    public init(window: UIWindow?, barHeight: CGFloat) {
        self.window = window
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