;;; helheim-desktop-modeline.el --- Desktop additions to Doom Modeline -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Commentary:
;; Keep the Starship Catppuccin Mocha Powerline editing layouts with a centered
;; lavender clock and right-hand connectivity/battery pills, and use a clean
;; title/status layout for EWM, Ghostel, and Eshell.  No I/O happens during
;; redisplay.

;;; Code:
(require 'subr-x)
(require 'seq)
(require 'helheim-modeline)

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
  (dolist (sub helheim-desktop-modeline--subscriptions)
    (ignore-errors (dbus-unregister-object sub)))
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
    (propertize (nerd-icons-mdicon (concat "nf-md-" kind suffix))
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

(defun helheim-desktop-modeline--display-cols (str)
  "Return approximate column width of STR accounting for Nerd Font pixel widths."
  (if (or (null str) (string-empty-p str))
      0
    (if (and (display-graphic-p) (fboundp 'doom-modeline-string-pixel-width))
        (ceiling (/ (float (doom-modeline-string-pixel-width str))
                    (max 1 (window-font-width nil 'mode-line))))
      (string-width str))))

(defun helheim-desktop-modeline--escape-pct (str)
  "Escape literal `%' in already-formatted STR while preserving text properties."
  (if (stringp str)
      (helheim-modeline--escape-pct str)
    ""))

(defun helheim-desktop-modeline--layout (layout)
  "Insert a centered Starship lavender clock into Doom Modeline's LAYOUT.
Keep its existing left/right pill chains and right-alignment spacer.
Truncates left pill chains cleanly with a preserved `' cap, and omits
the clock on narrow windows rather than overlapping the right-hand pills."
  (let* ((left (format-mode-line (car layout)))
         (right (or (nth 2 layout) ""))
         (clock (let ((doom-modeline--limited-width-p nil))
                  (or (helheim-modeline--pill-time) "")))
         (clock-cols (helheim-desktop-modeline--display-cols clock))
         (right-cols (helheim-desktop-modeline--display-cols right))
         (width (window-body-width))
         (start (/ (- width clock-cols) 2))
         (room (- width start clock-cols 1))
         (active (doom-modeline--active))
         (right-escaped (helheim-desktop-modeline--escape-pct right)))
    (if (or (string-empty-p clock) (< start 8) (> right-cols room))
        (let ((max-left (max 0 (- width right-cols 1))))
          (list (helheim-desktop-modeline--escape-pct
                 (helheim-modeline--truncate-pills left max-left active))
                (nth 1 layout)
                right-escaped))
      (list (helheim-desktop-modeline--escape-pct
             (helheim-modeline--truncate-pills left (max 0 (1- start)) active))
            (propertize " "
                        'face (doom-modeline-face)
                        'display `(space :align-to ,start))
            clock
            (nth 1 layout)
            right-escaped))))

(defun helheim-desktop-modeline--badge ()
  "Return compact badge label for the current desktop/terminal buffer."
  (cond
   ((derived-mode-p 'eshell-mode) " \xe795 ")
   ((derived-mode-p 'ghostel-mode) " \xe795 ")
   ((and (boundp 'ewm-surface-app)
         (stringp ewm-surface-app)
         (not (string-empty-p ewm-surface-app)))
    (format " \xf2d0 %s " ewm-surface-app))
   (t " \xf2d0 ")))

(defun helheim-desktop-modeline--title ()
  "Return clean window or terminal title without `*...*' buffer wrappers."
  (or (and (derived-mode-p 'ghostel-mode)
           (bound-and-true-p ghostel-title))
      (and (derived-mode-p 'eshell-mode)
           (or (bound-and-true-p user-eshell-title)
               (buffer-name)))
      (and (boundp 'ewm-surface-title)
           (not (string-empty-p (or ewm-surface-title "")))
           ewm-surface-title)
      (and (boundp 'ewm-surface-app) ewm-surface-app)
      (and (derived-mode-p 'ghostel-mode) "Terminal")
      (and (derived-mode-p 'eshell-mode) "Eshell")
      "Application"))

(with-eval-after-load 'doom-modeline
  (setq doom-modeline-minor-modes nil
        doom-modeline-time-icon nil
        display-time-format "%H:%M:%S"
        display-time-interval 1
        display-time-default-load-average nil
        display-time-mail-function #'ignore
        helheim-modeline--desktop-enabled t)
  (display-time-mode 1)
  (display-battery-mode 1)
  ;; Keep the clock and battery visible in inactive windows too.
  (dolist (segment '(time battery))
    (add-to-list 'doom-modeline-always-visible-segments segment))

  (doom-modeline-def-segment desktop-title
    "Display the window or terminal title without its buffer-name wrapper."
    (concat " " (helheim-desktop-modeline--title) " "))

  (doom-modeline-def-segment desktop-status
    (identity helheim-desktop-modeline--status))

  (doom-modeline-def-segment starship-desktop-left
    "Starship pill chain for desktop apps, Ghostel, and Eshell."
    (helheim-modeline--render-pills
     (list (list (helheim-desktop-modeline--badge) 'red :inactive-bg 'surface1 :weight 'bold)
           (list (concat " " (helheim-desktop-modeline--title) " ")
                 'peach :inactive-bg 'surface0 :weight 'bold))
     'left))

  (doom-modeline-def-segment starship-desktop-right
    "Starship right pill chain for desktop apps, Ghostel, and Eshell."
    (helheim-modeline--render-pills
     (list (helheim-modeline--pill-desktop-status)
           (helheim-modeline--pill-battery))
     'right))

  (doom-modeline-def-modeline 'desktop '(starship-desktop-left) '(starship-desktop-right))
  (add-to-list 'doom-modeline-mode-alist '(ewm-surface-mode . desktop))
  (setf (alist-get 'ghostel-mode doom-modeline-mode-alist) 'desktop)
  (setf (alist-get 'eshell-mode doom-modeline-mode-alist) 'desktop)

  (dolist (definition doom-modeline--modelines)
    (let ((name (car definition)))
      (advice-add (intern (format "doom-modeline-format--%s" name))
                  :filter-return #'helheim-desktop-modeline--layout)))

  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'ewm-surface-mode 'ghostel-mode 'eshell-mode)
        (doom-modeline-set-modeline 'desktop)))))

(with-eval-after-load 'ewm
  ;; The initial D-Bus refresh can fire before EWM finishes enabling.
  (add-hook 'ewm-mode-hook #'helheim-desktop-modeline--refresh)
  (helheim-desktop-modeline--watch))

(provide 'helheim-desktop-modeline)
;;; helheim-desktop-modeline.el ends here
