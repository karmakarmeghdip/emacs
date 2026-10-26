;;; helheim-ewm.el --- EWM (Emacs Wayland Manager) integration -*- lexical-binding: t -*-

;;; Commentary:
;;
;; Configuration for EWM (Emacs Wayland Manager).
;; Automatically applies display scaling, cursor themes, touchpad gestures,
;; font synchronization, and custom keybindings whenever EWM is loaded, while
;; remaining completely inactive during normal non-EWM Emacs sessions.

;;; Code:

(defun helheim-ewm--get-font-config ()
  "Detect the font family and size configured in `init.el'."
  (let ((font (car (fontset-font t ?a)))
        (size 13.0))
    ;; Parse init.el directly to respect any font or size defined by the user
    (condition-case nil
        (let ((init-file (expand-file-name "init.el" user-emacs-directory)))
          (when (file-readable-p init-file)
            (with-temp-buffer
              (insert-file-contents init-file)
              (goto-char (point-min))
              (when (re-search-forward "(font\\s-+\"\\([^\"]+\\)\")" nil t)
                (setq font (match-string 1)))
              (goto-char (point-min))
              (when (re-search-forward ":size\\s-+\\([0-9.]+\\)" nil t)
                (setq size (string-to-number (match-string 1)))))))
      (error nil))
    (cons (or font "MartianMono Nerd Font") (or size 13.0))))

(defun helheim-ewm--apply-font (&optional frame)
  "Apply the font configured in `init.el' to FRAME (or all graphic frames)."
  (let* ((cfg (helheim-ewm--get-font-config))
         (font (car cfg))
         (size (cdr cfg))
         (height (* (truncate size) 10))
         (font-name (format "%s-%d" font (truncate size))))
    ;; 1. Update default-frame-alist and global faces for future frames
    (add-to-list 'default-frame-alist `(font . ,font-name))
    (set-face-attribute 'default t :family font :height height :weight 'normal)
    (set-face-attribute 'fixed-pitch t :family font :height height :weight 'normal)
    ;; 2. Apply to target frame or existing frames
    (if frame
        (when (display-graphic-p frame)
          (set-face-attribute 'default frame :family font :height height :weight 'normal)
          (set-face-attribute 'fixed-pitch frame :family font :height height :weight 'normal)
          (set-fontset-font t 'unicode font frame 'prepend))
      (dolist (f (frame-list))
        (when (display-graphic-p f)
          (set-face-attribute 'default f :family font :height height :weight 'normal)
          (set-face-attribute 'fixed-pitch f :family font :height height :weight 'normal)
          (set-fontset-font t 'unicode font f 'prepend))))))

(provide 'helheim-ewm)

;;;###autoload
(with-eval-after-load 'ewm
  (unless (featurep 'helheim-ewm)
    (require 'helheim-ewm))
  ;; 1. Display: 1.25x fractional scaling
  (setopt ewm-output-config
          '(("eDP-1" :scale 1.25)
            ("HDMI-A-1" :scale 1.25)
            ("DP-1" :scale 1.25)))

  ;; 2. Cursor: macOS cursor theme and size
  (setopt ewm-cursor-theme "macOS")
  (setopt ewm-cursor-size 32)

  ;; 3. Touchpad: natural scrolling, tap-to-click, and 2-finger right-click
  (setopt ewm-input-config
          '((touchpad
             :natural-scroll t
             :tap t
             :tap-button-map "left-right-middle"
             :click-method "clickfinger")))

  ;; 4. Font: Automatically sync font configured in init.el to all EWM frames
  (helheim-ewm--apply-font)
  (add-hook 'after-make-frame-functions #'helheim-ewm--apply-font)

  ;; 5. Keybindings
  ;; Super+b: Switch buffers / Wayland apps with Consult
  (keymap-set ewm-mode-map "s-b" (ewm-key #'consult-buffer :fullscreen))
  ;; Super+q: Close the focused buffer / Wayland application
  (keymap-set ewm-mode-map "s-q" (ewm-key #'kill-current-buffer :fullscreen)))

;;; helheim-ewm.el ends here
