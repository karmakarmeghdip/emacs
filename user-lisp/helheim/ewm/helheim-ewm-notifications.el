;;; helheim-ewm-notifications.el --- EDNC echo-area previews -*- lexical-binding: t -*-

;;; Commentary:
;; Keep notification history in *ednc-log*, reachable with consult-buffer.
;; Echo-area previews navigate to the notification instead of invoking actions.

;;; Code:

(require 'ednc)
(require 'seq)
(require 'subr-x)

(defvar ewm-mode)
(defvar helheim-ewm-notifications--pending nil)
(defvar helheim-ewm-notifications--timer nil)
(defvar helheim-ewm-notifications--started nil)

(defun helheim-ewm-notifications--open (notification)
  "Open NOTIFICATION in EDNC's history, showing its full details."
  (ednc-pop-to-notification-in-log-buffer notification))

(defun helheim-ewm-notifications--preview (notification)
  "Return a single-line, clickable preview of NOTIFICATION."
  (let* ((text (mapconcat
                #'identity
                (seq-remove #'string-empty-p
                            (mapcar (lambda (value)
                                      (string-trim
                                       (replace-regexp-in-string
                                        "[[:space:]]+" " "
                                        (substring-no-properties (or value "")))))
                                    (list (ednc-notification-app-name notification)
                                          (ednc-notification-summary notification)
                                          (ednc-notification-body notification))))
                " — "))
         (map (make-sparse-keymap)))
    (define-key map [down-mouse-1] #'ignore)
    (define-key map [mouse-1]
                (lambda (_event)
                  (interactive "e")
                  (helheim-ewm-notifications--open notification)))
    (propertize
     (truncate-string-to-width
      text (max 20 (- (window-body-width (minibuffer-window)) 2)) nil nil "…")
     'keymap map 'mouse-face 'highlight
     'help-echo "mouse-1: Read notification in *ednc-log*")))

(defun helheim-ewm-notifications--flush ()
  "Show the latest queued preview without overwriting a minibuffer prompt."
  (setq helheim-ewm-notifications--timer nil)
  (when helheim-ewm-notifications--pending
    (if (active-minibuffer-window)
        (setq helheim-ewm-notifications--timer
              (run-at-time 0.5 nil #'helheim-ewm-notifications--flush))
      (let ((notification helheim-ewm-notifications--pending)
            (message-log-max nil))
        (setq helheim-ewm-notifications--pending nil)
        (message "%s" (helheim-ewm-notifications--preview notification))))))

(defun helheim-ewm-notifications--present (_old new)
  "Queue an echo preview for NEW, leaving EDNC's history handler intact."
  (when new
    (setq helheim-ewm-notifications--pending new)
    (unless (timerp helheim-ewm-notifications--timer)
      (setq helheim-ewm-notifications--timer
            (run-at-time 0.1 nil #'helheim-ewm-notifications--flush)))))

(defun helheim-ewm-notifications--sync ()
  "Run EDNC during EWM sessions without replacing another notification server."
  (if (bound-and-true-p ewm-mode)
      (unless ednc-mode
        (if (member "org.freedesktop.Notifications" (dbus-list-names :session))
            (display-warning 'helheim-ewm-notifications
                             "Another notification server is running; EDNC not started")
          (ednc-mode 1)
          (setq helheim-ewm-notifications--started t)))
    (when (timerp helheim-ewm-notifications--timer)
      (cancel-timer helheim-ewm-notifications--timer))
    (setq helheim-ewm-notifications--timer nil
          helheim-ewm-notifications--pending nil)
    (when helheim-ewm-notifications--started
      (ednc-mode -1)
      (setq helheim-ewm-notifications--started nil))))

;; EDNC's default lighter is unwanted even though it is a global minor mode.
(setf (alist-get 'ednc-mode minor-mode-alist) nil)
(add-hook 'ednc-notification-presentation-functions
          #'helheim-ewm-notifications--present t)
(add-hook 'ewm-mode-hook #'helheim-ewm-notifications--sync)
(helheim-ewm-notifications--sync)

(provide 'helheim-ewm-notifications)
;;; helheim-ewm-notifications.el ends here
