;;; helheim-desktop-modeline.el --- Desktop additions to Doom Modeline -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Commentary:
;; Keep the distribution's editing layouts, with a clock and battery, and
;; use a clean title/status layout for EWM.  No I/O happens during redisplay.

;;; Code:
(require 'subr-x)
(require 'seq)

(defvar ewm-surface-title)
(defvar ewm-surface-app)
(defvar helheim-desktop-modeline--status "")
(defvar helheim-desktop-modeline--process nil)
(defvar helheim-desktop-modeline--timer nil)
(defvar helheim-desktop-modeline--subscriptions nil)

(defun helheim-desktop-modeline--changed (&rest _)
  "Coalesce network events into one asynchronous status refresh."
  (when (timerp helheim-desktop-modeline--timer)
    (cancel-timer helheim-desktop-modeline--timer))
  (setq helheim-desktop-modeline--timer
        (run-at-time 0.3 nil #'helheim-desktop-modeline--refresh)))

(defun helheim-desktop-modeline--refresh ()
  "Refresh after an event, waiting for any previous query to finish."
  (if (process-live-p helheim-desktop-modeline--process)
      (helheim-desktop-modeline--changed)
    (helheim-desktop-modeline--collect)))

(defun helheim-desktop-modeline--properties (_interface changed invalidated)
  "Refresh only for relevant CHANGED or INVALIDATED D-Bus properties."
  (when (seq-intersection
         (append (mapcar #'car changed) invalidated)
         '("WirelessEnabled" "State" "ActiveAccessPoint" "Powered" "Connected")
         #'equal)
    (helheim-desktop-modeline--changed)))

(defun helheim-desktop-modeline--watch ()
  "Subscribe to NetworkManager and BlueZ instead of polling them."
  (require 'dbus)
  (mapc #'dbus-unregister-object helheim-desktop-modeline--subscriptions)
  (setq helheim-desktop-modeline--subscriptions nil)
  ;; Match paths, not unique owners, so daemon restarts do not stale the matches.
  (dolist (path '("/org/freedesktop/NetworkManager" "/org/bluez"))
    (push (dbus-register-signal
           :system nil nil "org.freedesktop.DBus.Properties" "PropertiesChanged"
           #'helheim-desktop-modeline--properties :path-namespace path)
          helheim-desktop-modeline--subscriptions))
  (dolist (signal '("InterfacesAdded" "InterfacesRemoved"))
    (push (dbus-register-signal
           :system nil nil "org.freedesktop.DBus.ObjectManager" signal
           #'helheim-desktop-modeline--changed :path0 "/org/bluez")
          helheim-desktop-modeline--subscriptions))
  (dolist (service '("org.bluez" "org.freedesktop.NetworkManager"))
    (push (dbus-register-signal
           :system "org.freedesktop.DBus" "/org/freedesktop/DBus"
           "org.freedesktop.DBus" "NameOwnerChanged"
           #'helheim-desktop-modeline--changed :arg0 service)
          helheim-desktop-modeline--subscriptions))
  (helheim-desktop-modeline--changed))

(defun helheim-desktop-modeline--collect ()
  "Collect local system status asynchronously while EWM is running."
  (when (and (bound-and-true-p ewm-mode)
             (featurep 'doom-modeline)
             (not (process-live-p helheim-desktop-modeline--process)))
    (let ((default-directory "/")
          (process-connection-type nil))
      (setq helheim-desktop-modeline--process
            (make-process
             :name "desktop-modeline" :buffer (generate-new-buffer " *desktop-status*")
             :noquery t :connection-type 'pipe
             :command
             '("sh" "-c"
               "export LC_ALL=C; timeout 2 nmcli -t -f WIFI general 2>/dev/null; timeout 2 nmcli -t -f TYPE,STATE device 2>/dev/null; timeout 2 bluetoothctl show 2>/dev/null; timeout 2 bluetoothctl devices Connected 2>/dev/null")
             :sentinel #'helheim-desktop-modeline--collected)))))

(defun helheim-desktop-modeline--icon (kind state)
  "Return a compact Nerd Icon for network KIND in STATE."
  (let ((suffix (pcase (cons kind state)
                  (`("bluetooth" . connected) "_connect")
                  (`("bluetooth" . disconnected) "")
                  (`("bluetooth" . ,_) "_off")
                  (`("wifi" . connected) "")
                  (`("wifi" . disconnected) "_strength_outline")
                  (`("wifi" . disabled) "_off")
                  (_ "_alert"))))
    (propertize (nerd-icons-mdicon (concat "nf-md-" kind suffix)
                                  :face 'mode-line)
                'help-echo (format "%s: %s" (capitalize kind) state))))

(defun helheim-desktop-modeline--collected (process _event)
  "Cache the completed status output from PROCESS."
  (when (memq (process-status process) '(exit signal))
    (unwind-protect
        (when (buffer-live-p (process-buffer process))
          (with-current-buffer (process-buffer process)
            (let* ((text (buffer-string))
                   (wifi (cond ((string-match-p "^disabled$" text) 'disabled)
                               ((string-match-p "^wifi:connected$" text) 'connected)
                               ((string-match-p "^enabled$" text) 'disconnected)
                               (t 'unavailable)))
                   (bluetooth (cond ((string-match-p "Powered: no" text) 'disabled)
                                    ((string-match-p "Powered: yes" text)
                                     (if (string-match-p "^Device " text)
                                         'connected 'disconnected))
                                    (t 'unavailable))))
              (setq helheim-desktop-modeline--status
                    (concat " " (helheim-desktop-modeline--icon "bluetooth" bluetooth)
                            "  " (helheim-desktop-modeline--icon "wifi" wifi) " "))
              (force-mode-line-update t))))
      (when (buffer-live-p (process-buffer process))
        (kill-buffer (process-buffer process))))))

(defun helheim-desktop-modeline--layout (layout)
  "Insert a centered clock into Doom Modeline's rendered LAYOUT.
Keep its existing left/right segments and right-alignment spacer.  On
narrow windows omit the clock rather than overlap the right-hand status."
  (let* ((left (format-mode-line (car layout)))
         (right (format-mode-line (nth 2 layout)))
         (clock (let ((doom-modeline--limited-width-p nil))
                  (or (doom-modeline-segment--time) "")))
         (width (window-body-width))
         (start (/ (- width (string-width clock)) 2))
         (room (- width start (string-width clock) 1)))
    (if (or (string-empty-p clock) (< start 8) (> (string-width right) room))
        (list (string-replace
               "%" "%%"
               (truncate-string-to-width left (max 0 (- width (string-width right) 1))
                                         nil nil "…"))
              (nth 1 layout) (nth 2 layout))
      (list (string-replace "%" "%%"
                            (truncate-string-to-width left (max 0 (1- start)) nil nil "…"))
            (propertize " " 'display `(space :align-to ,start))
            clock (nth 1 layout) (nth 2 layout)))))

(with-eval-after-load 'doom-modeline
  (setq doom-modeline-minor-modes nil
        doom-modeline-time-icon nil
        display-time-format "%H:%M:%S"
        display-time-interval 1
        display-time-default-load-average nil
        display-time-mail-function #'ignore)
  (display-time-mode 1)
  (display-battery-mode 1)
  ;; Keep the clock and battery visible in inactive windows too.
  (dolist (segment '(time battery))
    (add-to-list 'doom-modeline-always-visible-segments segment))
  (dolist (segment '(minor-modes major-mode buffer-position time battery desktop-status))
    (doom-modeline-remove-segment segment 'all))

  (doom-modeline-def-segment desktop-title
    "Display the window title without EWM's buffer-name wrapper."
    (concat " " (propertize
                 (string-replace "%" "%%"
                                 (or (and (boundp 'ewm-surface-title)
                                          (not (string-empty-p (or ewm-surface-title "")))
                                          ewm-surface-title)
                                     (and (boundp 'ewm-surface-app) ewm-surface-app)
                                     "Application"))
                 'face 'mode-line-buffer-id) " "))
  (doom-modeline-def-segment desktop-status
    (identity helheim-desktop-modeline--status))
  (doom-modeline-def-modeline 'desktop '(desktop-title))
  (add-to-list 'doom-modeline-mode-alist '(ewm-surface-mode . desktop))
  ;; Extend each installed layout instead of copying upstream definitions.
  (dolist (definition doom-modeline--modelines)
    (pcase-let ((`(,name ,left ,right) definition))
      (doom-modeline-def-modeline name left (append right '(desktop-status battery)))
      (advice-add (intern (format "doom-modeline-format--%s" name))
                  :filter-return #'helheim-desktop-modeline--layout)))
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'ewm-surface-mode)
        (doom-modeline-set-modeline 'desktop)))))

(with-eval-after-load 'ewm
  ;; The initial D-Bus refresh can fire before EWM finishes enabling.
  (add-hook 'ewm-mode-hook #'helheim-desktop-modeline--refresh)
  (helheim-desktop-modeline--watch))

(provide 'helheim-desktop-modeline)
;;; helheim-desktop-modeline.el ends here
