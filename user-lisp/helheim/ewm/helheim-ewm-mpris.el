;;; helheim-ewm-mpris.el --- MPRIS media player control for EWM -*- lexical-binding: t -*-

;;; Commentary:
;;
;; MPRIS media player controls for EWM using D-Bus.
;; Provides play/pause toggling, next, previous, and stop controls.
;; Automatically targets the currently playing media player, falling back
;; to the last controlled player or any active player.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'dbus)

(defgroup helheim-ewm-mpris nil
  "MPRIS media control integration for EWM."
  :group 'environment)

(defvar helheim-ewm-mpris--last-player nil
  "Last controlled MPRIS player service name.")

(defun helheim-ewm-mpris--players ()
  "Return active MPRIS player service names on the session bus."
  (when (featurep 'dbus)
    (seq-filter (lambda (name) (string-prefix-p "org.mpris.MediaPlayer2." name))
                (ignore-errors (dbus-list-names :session)))))

(defun helheim-ewm-mpris--player-status (player)
  "Return the PlaybackStatus string of PLAYER, or nil on error."
  (ignore-errors
    (dbus-get-property :session player
                       "/org/mpris/MediaPlayer2"
                       "org.mpris.MediaPlayer2.Player"
                       "PlaybackStatus")))

(defun helheim-ewm-mpris--find-player ()
  "Find the most appropriate MPRIS player to control.
Prefers currently playing players, then recently controlled player,
then any paused player, and finally any active player."
  (let ((players (helheim-ewm-mpris--players)))
    (when players
      (or
       ;; 1. Currently playing
       (seq-find (lambda (p) (equal "Playing" (helheim-ewm-mpris--player-status p)))
                 players)
       ;; 2. Last controlled player if still active
       (and helheim-ewm-mpris--last-player
            (member helheim-ewm-mpris--last-player players)
            helheim-ewm-mpris--last-player)
       ;; 3. Any paused player
       (seq-find (lambda (p) (equal "Paused" (helheim-ewm-mpris--player-status p)))
                 players)
       ;; 4. First available
       (car players)))))

(defun helheim-ewm-mpris--call (method)
  "Call METHOD on the active MPRIS player, or fallback to playerctl."
  (if-let* ((player (helheim-ewm-mpris--find-player)))
      (progn
        (setq helheim-ewm-mpris--last-player player)
        (dbus-call-method-asynchronously
         :session player
         "/org/mpris/MediaPlayer2"
         "org.mpris.MediaPlayer2.Player"
         method
         nil))
    (if (executable-find "playerctl")
        (let ((cmd (pcase method
                     ("PlayPause" "play-pause")
                     ("Next" "next")
                     ("Previous" "previous")
                     ("Stop" "stop")
                     (_ (downcase method)))))
          (start-process "helheim-ewm-playerctl" nil "playerctl" cmd))
      (message "No active MPRIS media players found"))))

;;;###autoload
(defun helheim-ewm-mpris-play-pause ()
  "Toggle play/pause on the active MPRIS media player."
  (interactive)
  (helheim-ewm-mpris--call "PlayPause"))

;;;###autoload
(defun helheim-ewm-mpris-next ()
  "Skip to the next track on the active MPRIS media player."
  (interactive)
  (helheim-ewm-mpris--call "Next"))

;;;###autoload
(defun helheim-ewm-mpris-previous ()
  "Skip to the previous track on the active MPRIS media player."
  (interactive)
  (helheim-ewm-mpris--call "Previous"))

;;;###autoload
(defun helheim-ewm-mpris-stop ()
  "Stop playback on the active MPRIS media player."
  (interactive)
  (helheim-ewm-mpris--call "Stop"))

(provide 'helheim-ewm-mpris)
;;; helheim-ewm-mpris.el ends here
