;;; helheim-ewm-clipboard.el --- Clipboard manager integration for EWM -*- lexical-binding: t -*-

;;; Commentary:
;;
;; Clipboard history management for EWM using Consult and Emacs's kill-ring.
;; Synchronizes chosen kill-ring items to the Wayland clipboard via EWM's
;; `ewm-set-selection-module', making selected items the active system clipboard
;; in addition to inserting them into the focused buffer or surface.

;;; Code:

(require 'consult)
(require 'subr-x)

(defvar ewm-mode)
(defvar savehist-additional-variables)

(defgroup helheim-ewm-clipboard nil
  "Clipboard management integration for EWM."
  :group 'environment)

(defcustom helheim-ewm-clipboard-persist t
  "Whether to persist `kill-ring' across Emacs sessions using `savehist'."
  :type 'boolean
  :group 'helheim-ewm-clipboard)

(defun helheim-ewm-clipboard--sync-selection (string &rest _)
  "Promote STRING to the active Wayland selection whenever selected from kill-ring."
  (when (and (stringp string) (bound-and-true-p ewm-mode))
    (setq kill-ring (delete string kill-ring))
    (kill-new string)))

;;;###autoload
(defun helheim-ewm-clipboard (&optional copy-only)
  "Select an item from the clipboard history using Consult.
By default, promotes the chosen item to the active Wayland clipboard
and inserts it into the active text field.
With prefix argument COPY-ONLY (C-u), sets the active Wayland clipboard
without inserting."
  (interactive "P")
  (let ((string (consult--read-from-kill-ring)))
    (when (and string (not (string-empty-p string)))
      (helheim-ewm-clipboard--sync-selection string)
      (if copy-only
          (message "Active clipboard set: %s"
                   (string-truncate-left (string-trim string) 50))
        (condition-case nil
            (progn
              (setq yank-window-start (window-start))
              (push-mark)
              (insert-for-yank string)
              (setq this-command 'yank))
          (buffer-read-only
           (message "Buffer is read-only; active clipboard set: %s"
                    (string-truncate-left (string-trim string) 50))))))))

;; Advise `consult-yank-from-kill-ring' so even M-y inside Emacs syncs the Wayland selection.
(advice-add 'consult-yank-from-kill-ring :after #'helheim-ewm-clipboard--sync-selection)

;; Persist kill-ring across sessions
(with-eval-after-load 'savehist
  (when helheim-ewm-clipboard-persist
    (add-to-list 'savehist-additional-variables 'kill-ring)))

(provide 'helheim-ewm-clipboard)

;;; helheim-ewm-clipboard.el ends here
