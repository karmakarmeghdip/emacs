;;; helheim-ewm-notifications.el --- EDNC echo-area previews -*- lexical-binding: t -*-

;;; Commentary:
;; Keep notification history in *ednc-log*, reachable with consult-buffer.
;; Echo-area clicks invoke the application's default notification action.

;;; Code:

(require 'ednc)
(require 'seq)
(require 'subr-x)

(defvar ewm-mode)
(defgroup helheim-ewm-notifications nil
  "Notification presentation in EWM."
  :group 'environment)

(defcustom helheim-ewm-notifications-preview-duration 15
  "Seconds to display an echo-area notification preview.
This does not expire or remove the notification from EDNC's history."
  :type '(number :tag "Seconds"))

(defvar helheim-ewm-notifications--pending nil)
(defvar helheim-ewm-notifications--timer nil)
(defvar helheim-ewm-notifications--clear-timer nil)
(defvar helheim-ewm-notifications--started nil)
(declare-function ewm-create-activation-token "ewm-core" ())

(defun helheim-ewm-notifications--open (notification)
  "Open NOTIFICATION in EDNC's history, showing its full details."
  (ednc-pop-to-notification-in-log-buffer notification))

(defun helheim-ewm-notifications--activate (notification)
  "Invoke NOTIFICATION's default action, or show its history entry.
Send a Wayland activation token first so supporting clients can focus their
window.  Do not guess a window from an application name or PID."
  (if (and (ednc-notification-parent notification)
           (member "default" (cl-loop for (key _label) on
                                     (ednc-notification-actions notification)
                                     by #'cddr collect key)))
      (progn
        (when (and (bound-and-true-p ewm-mode)
                   (fboundp 'ewm-create-activation-token))
          (when-let* ((token (ewm-create-activation-token)))
            (dbus-send-signal :session (ednc-notification-client notification)
                              "/org/freedesktop/Notifications"
                              "org.freedesktop.Notifications" "ActivationToken"
                              :uint32 (ednc-notification-id notification) token)))
        (ednc-invoke-action notification))
    (helheim-ewm-notifications--open notification)))

(defun helheim-ewm-notifications--echo-click (event)
  "Activate the notification under mouse EVENT, otherwise show Messages.
The inactive minibuffer's keymap takes precedence over echo text keymaps."
  (interactive "e")
  (let* ((position (event-start event))
         (string-position (posn-string position))
         (text (if string-position (car string-position) (current-message)))
         (index (if string-position (cdr string-position) 0))
         (notification (and text (< index (length text))
                            (get-text-property index 'helheim-ewm-notification text))))
    (if (and notification (not (active-minibuffer-window)))
        (helheim-ewm-notifications--activate notification)
      (view-echo-area-messages))))

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
                  (helheim-ewm-notifications--activate notification)))
    (propertize
     (truncate-string-to-width
      text (max 20 (- (window-body-width (minibuffer-window)) 2)) nil nil "…")
     'keymap map 'mouse-face 'highlight
     'helheim-ewm-notification notification
     'help-echo "mouse-1: Activate notification (or read its history)")))

(defun helheim-ewm-notifications--clear-preview (token)
  "Clear the preview identified by TOKEN, never another echo-area message."
  (setq helheim-ewm-notifications--clear-timer nil)
  (let ((text (current-message)))
    (when (and (not (active-minibuffer-window))
               text (> (length text) 0)
               (eq (get-text-property 0 'helheim-ewm-preview-token text) token))
      (let ((message-log-max nil))
        (message nil)))))

(defun helheim-ewm-notifications--flush ()
  "Show the latest queued preview without overwriting a minibuffer prompt."
  (setq helheim-ewm-notifications--timer nil)
  (when helheim-ewm-notifications--pending
    (if (active-minibuffer-window)
        (setq helheim-ewm-notifications--timer
              (run-at-time 0.5 nil #'helheim-ewm-notifications--flush))
      (let* ((notification helheim-ewm-notifications--pending)
             (token (list notification))
             (preview (propertize (helheim-ewm-notifications--preview notification)
                                  'helheim-ewm-preview-token token))
             (message-log-max nil))
        (when (timerp helheim-ewm-notifications--clear-timer)
          (cancel-timer helheim-ewm-notifications--clear-timer))
        (setq helheim-ewm-notifications--pending nil)
        (message "%s" preview)
        (setq helheim-ewm-notifications--clear-timer
              (run-at-time (max 0.1 helheim-ewm-notifications-preview-duration) nil
                           #'helheim-ewm-notifications--clear-preview token))))))

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
    (when (timerp helheim-ewm-notifications--clear-timer)
      (cancel-timer helheim-ewm-notifications--clear-timer))
    (setq helheim-ewm-notifications--timer nil
          helheim-ewm-notifications--clear-timer nil
          helheim-ewm-notifications--pending nil)
    (when helheim-ewm-notifications--started
      (ednc-mode -1)
      (setq helheim-ewm-notifications--started nil))))

;; EDNC's default lighter is unwanted even though it is a global minor mode.
(setf (alist-get 'ednc-mode minor-mode-alist) nil)
(define-key minibuffer-inactive-mode-map [remap view-echo-area-messages]
            #'helheim-ewm-notifications--echo-click)
(add-hook 'ednc-notification-presentation-functions
          #'helheim-ewm-notifications--present t)
(add-hook 'ewm-mode-hook #'helheim-ewm-notifications--sync)
(helheim-ewm-notifications--sync)

(provide 'helheim-ewm-notifications)
;;; helheim-ewm-notifications.el ends here
