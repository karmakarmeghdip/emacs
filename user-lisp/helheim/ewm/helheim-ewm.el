;;; helheim-ewm.el --- EWM (Emacs Wayland Manager) integration -*- lexical-binding: t -*-

;;; Commentary:
;;
;; Configuration for EWM (Emacs Wayland Manager).
;; Display, cursor, touchpad, and keybindings, enabled only when EWM loads.
;; Font configuration belongs in init.el, including defaults for daemon frames.

;;; Code:

(require 'helheim-ewm-power)

(defun helheim-ewm-terminal ()
  "Open a new Alacritty terminal in the current local directory."
  (interactive)
  (unless (executable-find "alacritty")
    (user-error "Alacritty is not installed"))
  (let ((default-directory (if (file-remote-p default-directory)
                               (expand-file-name "~/")
                             default-directory)))
    (start-process "alacritty" nil "alacritty"
                   "--working-directory" default-directory)))

;;;###autoload (with-eval-after-load 'ewm (require 'helheim-ewm))
(with-eval-after-load 'ewm
  (with-eval-after-load 'consult
    (require 'helheim-ewm-consult))

  ;; Display: 1.25x fractional scaling
  (setopt ewm-output-config
          '(("eDP-1" :scale 1.25)
            ("HDMI-A-1" :scale 1.25)
            ("DP-1" :scale 1.25)))

  ;; Cursor: macOS cursor theme and size
  (setopt ewm-cursor-theme "macOS")
  (setopt ewm-cursor-size 32)

  ;; Touchpad: natural scrolling, tap-to-click, and 2-finger right-click
  (setopt ewm-input-config
          '((touchpad
             :natural-scroll t
             :tap t
             :tap-button-map "left-right-middle"
             :click-method "clickfinger")))

  ;; Keybindings
  ;; Super+Return: New terminal surface, also available over fullscreen apps.
  (keymap-set ewm-mode-map "s-<return>" (ewm-key #'helheim-ewm-terminal :fullscreen))
  ;; Super+d: Buffers, running Wayland apps, files and XDG apps.
  (keymap-set ewm-mode-map "s-d" (ewm-key #'consult-buffer :fullscreen))
  ;; Super+q: Close the focused buffer / Wayland application
  (keymap-set ewm-mode-map "s-q" (ewm-key #'kill-current-buffer :fullscreen))
  ;; Use the same supervised locker for manual, idle and logind requests.
  (keymap-set ewm-mode-map "s-l" (ewm-key #'helheim-ewm-lock :fullscreen))
  (add-hook 'ewm-mode-hook #'helheim-ewm-power--start)
  (when (bound-and-true-p ewm-mode)
    (helheim-ewm-power--start)))

(provide 'helheim-ewm)

;;; helheim-ewm.el ends here
