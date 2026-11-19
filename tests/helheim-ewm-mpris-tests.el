;;; helheim-ewm-mpris-tests.el --- Tests for EWM MPRIS media controls -*- lexical-binding: t -*-

;;; Commentary:

;; Unit tests for EWM MPRIS player discovery and control dispatch.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'helheim-ewm-mpris)

(ert-deftest helheim-ewm-mpris-find-player-prefers-playing ()
  "Find player prioritizes a player with 'Playing' status."
  (let ((players '("org.mpris.MediaPlayer2.spotify"
                   "org.mpris.MediaPlayer2.chromium.instance123"))
        (status-alist '(("org.mpris.MediaPlayer2.spotify" . "Paused")
                        ("org.mpris.MediaPlayer2.chromium.instance123" . "Playing")))
        (helheim-ewm-mpris--last-player "org.mpris.MediaPlayer2.spotify"))
    (cl-letf (((symbol-function 'helheim-ewm-mpris--players)
               (lambda () players))
              ((symbol-function 'helheim-ewm-mpris--player-status)
               (lambda (p) (cdr (assoc p status-alist)))))
      (should (equal (helheim-ewm-mpris--find-player)
                     "org.mpris.MediaPlayer2.chromium.instance123")))))

(ert-deftest helheim-ewm-mpris-find-player-uses-last-controlled-when-paused ()
  "When no player is playing, prefers the last controlled player if active."
  (let ((players '("org.mpris.MediaPlayer2.vlc"
                   "org.mpris.MediaPlayer2.chromium.instance123"))
        (status-alist '(("org.mpris.MediaPlayer2.vlc" . "Paused")
                        ("org.mpris.MediaPlayer2.chromium.instance123" . "Paused")))
        (helheim-ewm-mpris--last-player "org.mpris.MediaPlayer2.chromium.instance123"))
    (cl-letf (((symbol-function 'helheim-ewm-mpris--players)
               (lambda () players))
              ((symbol-function 'helheim-ewm-mpris--player-status)
               (lambda (p) (cdr (assoc p status-alist)))))
      (should (equal (helheim-ewm-mpris--find-player)
                     "org.mpris.MediaPlayer2.chromium.instance123")))))

(ert-deftest helheim-ewm-mpris-find-player-prefers-paused-over-stopped ()
  "When no player is playing and no last player, prefers paused over stopped."
  (let ((players '("org.mpris.MediaPlayer2.stopped-player"
                   "org.mpris.MediaPlayer2.paused-player"))
        (status-alist '(("org.mpris.MediaPlayer2.stopped-player" . "Stopped")
                        ("org.mpris.MediaPlayer2.paused-player" . "Paused")))
        (helheim-ewm-mpris--last-player nil))
    (cl-letf (((symbol-function 'helheim-ewm-mpris--players)
               (lambda () players))
              ((symbol-function 'helheim-ewm-mpris--player-status)
               (lambda (p) (cdr (assoc p status-alist)))))
      (should (equal (helheim-ewm-mpris--find-player)
                     "org.mpris.MediaPlayer2.paused-player")))))

(ert-deftest helheim-ewm-mpris-find-player-nil-when-none-available ()
  "Returns nil when no MPRIS players are running."
  (cl-letf (((symbol-function 'helheim-ewm-mpris--players)
             (lambda () nil)))
    (should-not (helheim-ewm-mpris--find-player))))

(ert-deftest helheim-ewm-mpris-call-invokes-dbus-asynchronously ()
  "Calling an MPRIS method dispatches dbus-call-method-asynchronously and saves last-player."
  (let (called-args
        (helheim-ewm-mpris--last-player nil))
    (cl-letf (((symbol-function 'helheim-ewm-mpris--find-player)
               (lambda () "org.mpris.MediaPlayer2.test"))
              ((symbol-function 'dbus-call-method-asynchronously)
               (lambda (&rest args) (setq called-args args))))
      (helheim-ewm-mpris-play-pause)
      (should (equal helheim-ewm-mpris--last-player "org.mpris.MediaPlayer2.test"))
      (should (equal called-args
                     '(:session
                       "org.mpris.MediaPlayer2.test"
                       "/org/mpris/MediaPlayer2"
                       "org.mpris.MediaPlayer2.Player"
                       "PlayPause"
                       nil))))))

(ert-deftest helheim-ewm-mpris-call-falls-back-to-playerctl ()
  "Falls back to playerctl when no D-Bus player is detected."
  (let (spawned-cmd
        (helheim-ewm-mpris--last-player nil))
    (cl-letf (((symbol-function 'helheim-ewm-mpris--find-player)
               (lambda () nil))
              ((symbol-function 'executable-find)
               (lambda (bin) (string= bin "playerctl")))
              ((symbol-function 'start-process)
               (lambda (_name _buf &rest args) (setq spawned-cmd args))))
      (helheim-ewm-mpris-play-pause)
      (should (equal spawned-cmd '("playerctl" "play-pause"))))))

(ert-deftest helheim-ewm-mpris-call-messages-when-no-player ()
  "Displays echo message when neither player nor playerctl is found."
  (let (echo-message
        (helheim-ewm-mpris--last-player nil))
    (cl-letf (((symbol-function 'helheim-ewm-mpris--find-player)
               (lambda () nil))
              ((symbol-function 'executable-find)
               (lambda (_) nil))
              ((symbol-function 'message)
               (lambda (fmt &rest _) (setq echo-message fmt))))
      (helheim-ewm-mpris-play-pause)
      (should (equal echo-message "No active MPRIS media players found")))))

(provide 'helheim-ewm-mpris-tests)
;;; helheim-ewm-mpris-tests.el ends here
