//
//  PlayerControlsViewController.swift
//  Audiobook Player
//
//  Created by Florian Pichler on 05.04.18.
//  Copyright © 2018 Tortuga Power. All rights reserved.
//

import UIKit

class PlayerControlsViewController: PlayerContainerViewController, UIGestureRecognizerDelegate {
    @IBOutlet private weak var artworkView: UIView!
    @IBOutlet private weak var artwork: UIImageView!
    @IBOutlet private weak var playPauseButton: UIButton!
    @IBOutlet private weak var rewindIcon: PlayerForwardIconView!
    @IBOutlet private weak var forwardIcon: PlayerRewindIconView!
    @IBOutlet private weak var artworkHeight: NSLayoutConstraint!
    @IBOutlet private weak var artworkHorizontal: NSLayoutConstraint!
    @IBOutlet private weak var forwardIconHorizontal: NSLayoutConstraint!
    @IBOutlet private weak var rewindIconHorizontal: NSLayoutConstraint!

    private let playImage = UIImage(named: "playButton")
    private let pauseImage = UIImage(named: "pauseButton")
    private var pan: UIPanGestureRecognizer!
    private var originalHeight: CGFloat!
    private let jumpIconAlpha: CGFloat = 0.15
    private var triggeredPanAction: Bool = false

    private var isPlaying: Bool = false {
        didSet {
            self.playPauseButton.alpha = 1.0
            self.playPauseButton.setImage(self.isPlaying ? self.pauseImage : self.playImage, for: UIControlState())

            self.view.layoutIfNeeded()
            self.artworkHeight.constant = self.isPlaying ? self.originalHeight : self.originalHeight * 255/325
            self.forwardIconHorizontal.constant = self.isPlaying ? 25.0 : 15.0
            self.rewindIconHorizontal.constant = self.isPlaying ? 25.0 : 15.0
            self.view.setNeedsLayout()

            UIView.animate(
                withDuration: 0.25,
                delay: 0.0,
                usingSpringWithDamping: 0.6,
                initialSpringVelocity: 1.4,
                options: .preferredFramesPerSecond60,
                animations: {
                    self.view.layoutIfNeeded()
            },
                completion: nil
            )

            UIView.animate(withDuration: 0.3, delay: 2.2, options: .allowUserInteraction, animations: {
                self.playPauseButton.alpha = 0.05
            }, completion: nil)
        }
    }

    var book: Book? {
        didSet {
            self.artwork.image = self.book?.artwork
        }
    }

    var colors: [UIColor]? {
        didSet {
            guard let colors = self.colors else {
                return
            }

            self.rewindIcon.tintColor = colors[3]
            self.forwardIcon.tintColor = colors[3]

            self.artwork.layer.shadowOpacity = 0.2 + Float(1.0 - colors[0].luminance) * 0.2
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.originalHeight = self.artworkHeight.constant
        self.isPlaying = PlayerManager.sharedInstance.isPlaying

        self.artwork.layer.shadowColor = UIColor.black.cgColor
        self.artwork.layer.shadowOffset = CGSize(width: 0.0, height: 4.0)
        self.artwork.layer.shadowOpacity = 0.2
        self.artwork.layer.shadowRadius = 12.0
        self.artwork.clipsToBounds = false

        self.rewindIcon.title = "−30s"
        self.forwardIcon.title = "+30s"

        self.rewindIcon.alpha = self.jumpIconAlpha
        self.forwardIcon.alpha = self.jumpIconAlpha

        NotificationCenter.default.addObserver(self, selector: #selector(self.onBookPlay), name: Notification.Name.AudiobookPlayer.bookPlayed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.onBookPause), name: Notification.Name.AudiobookPlayer.bookPaused, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.onBookPause), name: Notification.Name.AudiobookPlayer.bookEnd, object: nil)

        self.setupGestures()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    // toggle play/pause of book
    @IBAction private func play(_ sender: Any) {
        PlayerManager.sharedInstance.playPause()

        self.isPlaying = PlayerManager.sharedInstance.isPlaying
    }

    @objc private func onBookPlay() {
        self.isPlaying = true
    }

    @objc private func onBookPause() {
        self.isPlaying = false
    }

    // MARK: Gesture recognizers

    private func setupGestures() {
        self.pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        self.pan!.delegate = self
        self.pan!.maximumNumberOfTouches = 1
        self.pan!.cancelsTouchesInView = true

        self.view.addGestureRecognizer(self.pan!)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == self.pan {
            let velocity: CGPoint = self.pan.velocity(in: self.pan.view)
            let degree: CGFloat = atan(velocity.y / velocity.x) * 180 / CGFloat.pi

            return fabs(degree) < 30.0
        }

        return true
    }

    private func updateArtworkViewForTranslation(_ xTranslation: CGFloat) {
        let sign: CGFloat = xTranslation < 0 ? -1 : 1
        let width: CGFloat = self.rewindIcon.bounds.width
        let actionThreshold: CGFloat = width - 10.0
        let maximumPull: CGFloat = width + 5.0
        let translation: CGFloat = rubberBandDistance(fabs(xTranslation), dimension: width * 2 + 10.0, constant: 0.6)

        self.artworkHorizontal.constant = translation * sign

        let alpha: CGFloat = self.jumpIconAlpha + min(translation / actionThreshold, 1.0) * (1.0 - self.jumpIconAlpha)

        if !self.triggeredPanAction {
            if sign < 0 {
                self.rewindIcon.alpha = alpha
            } else {
                self.forwardIcon.alpha = alpha
            }
        }

        if translation > actionThreshold && !self.triggeredPanAction {
            if #available(iOS 10.0, *) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            UIView.animate(withDuration: 0.2) {
                self.rewindIcon.alpha = self.jumpIconAlpha
                self.forwardIcon.alpha = self.jumpIconAlpha
            }

            if sign < 0 {
                PlayerManager.sharedInstance.forward()
            } else {
                PlayerManager.sharedInstance.rewind()
            }

            self.triggeredPanAction = true
        }

        if translation > maximumPull {
            self.resetArtworkViewHorizontalConstraintAnimated()

            self.pan.isEnabled = false
            self.pan.isEnabled = true
        }
    }

    func resetArtworkViewHorizontalConstraintAnimated() {
        self.artworkHorizontal.constant = 0.0

        UIView.animate(
            withDuration: 0.3,
            delay: 0.0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 1.5,
            options: .preferredFramesPerSecond60,
            animations: {
                self.view.layoutIfNeeded()
        },
            completion: nil
        )

        UIView.animate(withDuration: 0.20, delay: 0.10, options: .curveEaseOut, animations: {
            self.rewindIcon.alpha = self.jumpIconAlpha
            self.forwardIcon.alpha = self.jumpIconAlpha
        }, completion: nil)

        self.triggeredPanAction = false
    }

    @objc private func handlePan(gestureRecognizer: UIPanGestureRecognizer) {
        guard gestureRecognizer.isEqual(self.pan) else {
            return
        }

        switch gestureRecognizer.state {
            case .began:
                gestureRecognizer.setTranslation(CGPoint(x: 0, y: 0), in: self.artworkView.superview)

            case .changed:
                let translation = gestureRecognizer.translation(in: self.artworkView)

                self.updateArtworkViewForTranslation(translation.x)

            case .ended, .cancelled, .failed:
                self.resetArtworkViewHorizontalConstraintAnimated()

            case .possible: break
        }
    }
}
