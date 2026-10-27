;;; helheim-ewm-power.el --- EWM locking and power policy -*- lexical-binding: t -*-

;;; Commentary:
;; EWM observes input, Hyprlock authenticates, UPower reports the power source,
;; and logind suspends.  No external idle daemon is needed.  See README.org.

;;; Code:

(require 'dbus)
(require 'subr-x)

(defgroup helheim-ewm-power nil
  "Locking and power policy for EWM."
  :group 'environment)

(defcustom helheim-ewm-power-lock-delay 300
  "Seconds of inactivity before locking on battery."
  :type 'natnum)

(defcustom helheim-ewm-power-blank-delay 30
  "Seconds of inactivity before blanking while locked."
  :type 'natnum)

(defcustom helheim-ewm-power-suspend-delay 900
  "Total seconds of inactivity while locked on battery before suspend.
This should be greater than `helheim-ewm-power-blank-delay'."
  :type 'natnum)

(defcustom helheim-ewm-power-lock-config
  (expand-file-name "hyprlock-ewm.conf"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Hyprlock configuration used only by the EWM session."
  :type 'file)

(defvar ewm-idle)
(defvar ewm-mode)
(defvar ewm-insomnia-mode)
(declare-function ewm-power-on-monitors "ewm-commands" ())
(declare-function dbus--close-fd "dbusbind.c" (fd))

(defconst helheim-ewm-power--login-service "org.freedesktop.login1")
(defconst helheim-ewm-power--login-path "/org/freedesktop/login1")
(defconst helheim-ewm-power--login-manager "org.freedesktop.login1.Manager")
(defconst helheim-ewm-power--login-session "org.freedesktop.login1.Session")
(defconst helheim-ewm-power--upower "org.freedesktop.UPower")
(defconst helheim-ewm-power--upower-path "/org/freedesktop/UPower")

(defvar helheim-ewm-power--active nil)
(defvar helheim-ewm-power--on-battery 'unknown)
(defvar helheim-ewm-power--lock-state nil
  "Nil, `starting', `locked', or `failed'.  Failed is not an unlock.")
(defvar helheim-ewm-power--locker nil)
(defvar helheim-ewm-power--idle nil)
(defvar helheim-ewm-power--suspend-timer nil)
(defvar helheim-ewm-power--signals nil)
(defvar helheim-ewm-power--session-path nil)
(defvar helheim-ewm-power--sleep-fd nil)
(defvar helheim-ewm-power--sleeping nil)
(defvar helheim-ewm-power--saved-idle nil)

(defun helheim-ewm-power--warn (format-string &rest args)
  "Report a power-policy problem using FORMAT-STRING and ARGS."
  (display-warning 'helheim-ewm-power (apply #'format format-string args) :warning))

(defun helheim-ewm-power--cancel-suspend ()
  "Cancel the pending automatic suspend."
  (when (timerp helheim-ewm-power--suspend-timer)
    (cancel-timer helheim-ewm-power--suspend-timer))
  (setq helheim-ewm-power--suspend-timer nil))

(defun helheim-ewm-power--arm-suspend (delay)
  "Arm suspension after DELAY seconds, if eligible."
  (helheim-ewm-power--cancel-suspend)
  (when (and helheim-ewm-power--active
             (eq helheim-ewm-power--lock-state 'locked)
             helheim-ewm-power--idle
             (eq helheim-ewm-power--on-battery t)
             (not helheim-ewm-power--sleeping))
    (setq helheim-ewm-power--suspend-timer
          (run-at-time (max 1 delay) nil #'helheim-ewm-power--suspend))))

(defun helheim-ewm-power--read-power ()
  "Return t on battery, nil on AC, or `unknown' if UPower is unavailable."
  (condition-case nil
      (dbus-get-property :system helheim-ewm-power--upower
                         helheim-ewm-power--upower-path
                         helheim-ewm-power--upower "OnBattery")
    (error 'unknown)))

(defun helheim-ewm-power--apply-idle ()
  "Apply the current lock/power policy without needless timer resets."
  (let ((policy
         (cond
          (helheim-ewm-power--lock-state
           (max 1 helheim-ewm-power-blank-delay))
          ((eq helheim-ewm-power--on-battery t)
           ;; The hook launches Hyprlock inside Emacs.  A no-op shell action
           ;; prevents EWM from blanking the unlocked desktop first.
           (cons (max 1 helheim-ewm-power-lock-delay) "true")))))
    (unless (equal ewm-idle policy)
      (helheim-ewm-power--cancel-suspend)
      (setq helheim-ewm-power--idle nil)
      (setopt ewm-idle policy))))

(defun helheim-ewm-power--refresh-power (&rest _)
  "Refresh power state; AC cancels sleep, unplugging starts a fresh deadline."
  (let ((power (helheim-ewm-power--read-power)))
    (unless (eq power helheim-ewm-power--on-battery)
      (setq helheim-ewm-power--on-battery power)
      (helheim-ewm-power--cancel-suspend)
      (helheim-ewm-power--apply-idle)
      (when (eq power t)
        (helheim-ewm-power--arm-suspend helheim-ewm-power-suspend-delay)))))

(defun helheim-ewm-power--idle-changed (idle)
  "Handle compositor IDLE transitions, including input on the lock screen."
  (setq helheim-ewm-power--idle idle)
  (helheim-ewm-power--cancel-suspend)
  (cond
   ((and idle (null helheim-ewm-power--lock-state))
    ;; Re-read at the boundary in case a power notification is still queued.
    (helheim-ewm-power--refresh-power)
    (when (eq helheim-ewm-power--on-battery t)
      (condition-case err
          (helheim-ewm-lock)
        (error
         (ewm-power-on-monitors)
         (helheim-ewm-power--warn "Automatic lock failed: %s" err)))))
   (idle
    (helheim-ewm-power--arm-suspend
     (- helheim-ewm-power-suspend-delay helheim-ewm-power-blank-delay)))))

(defun helheim-ewm-power--suspend ()
  "Suspend only if still locked, idle, on battery and not in insomnia mode."
  (setq helheim-ewm-power--suspend-timer nil)
  (helheim-ewm-power--refresh-power)
  (when (and helheim-ewm-power--active
             (eq helheim-ewm-power--lock-state 'locked)
             helheim-ewm-power--idle
             (eq helheim-ewm-power--on-battery t)
             (not (bound-and-true-p ewm-insomnia-mode))
             (not helheim-ewm-power--sleeping))
    (condition-case err
        (dbus-call-method-asynchronously
         :system helheim-ewm-power--login-service
         helheim-ewm-power--login-path helheim-ewm-power--login-manager
         "Suspend" #'ignore :boolean nil)
      (error (helheim-ewm-power--warn "Suspend request failed: %s" err)))))

(defun helheim-ewm-power--set-locked-hint (locked)
  "Tell logind whether this session is LOCKED."
  (when helheim-ewm-power--session-path
    (condition-case err
        (dbus-call-method
         :system helheim-ewm-power--login-service
         helheim-ewm-power--session-path helheim-ewm-power--login-session
         "SetLockedHint" :timeout 1000 :boolean locked)
      (error (helheim-ewm-power--warn "Cannot update LockedHint: %s" err)))))

(defun helheim-ewm-power--release-sleep-delay ()
  "Release logind's sleep-delay inhibitor."
  (when helheim-ewm-power--sleep-fd
    (dbus--close-fd helheim-ewm-power--sleep-fd)
    (setq helheim-ewm-power--sleep-fd nil)))

(defun helheim-ewm-power--inhibit-sleep ()
  "Hold a delay inhibitor so Hyprlock can lock before external sleep."
  (unless helheim-ewm-power--sleep-fd
    (condition-case err
        (setq helheim-ewm-power--sleep-fd
              (dbus-call-method
               :system helheim-ewm-power--login-service
               helheim-ewm-power--login-path helheim-ewm-power--login-manager
               ;; :keep-fd is a flag, not a keyword/value pair.  A following
               ;; t would be sent to logind as an extra boolean argument.
               "Inhibit" :timeout 1000 :keep-fd
               "sleep" "EWM" "Lock the session before sleep" "delay"))
      (error (helheim-ewm-power--warn "Cannot delay sleep for locking: %s" err)))))

(defun helheim-ewm-power--prepare-for-sleep (sleeping)
  "Handle logind's PrepareForSleep SLEEPING flag."
  (setq helheim-ewm-power--sleeping sleeping)
  (helheim-ewm-power--cancel-suspend)
  (if sleeping
      (if (eq helheim-ewm-power--lock-state 'locked)
          (helheim-ewm-power--release-sleep-delay)
        (helheim-ewm-power--logind-lock))
    (setq helheim-ewm-power--idle nil)
    (helheim-ewm-power--inhibit-sleep)
    (helheim-ewm-power--refresh-power)))

(defun helheim-ewm-power--logind-lock ()
  "Handle an external lock request without unwinding D-Bus dispatch."
  (condition-case err
      (helheim-ewm-lock)
    (error (helheim-ewm-power--warn "Cannot lock session: %s" err))))

(defun helheim-ewm-power--locker-filter (process output)
  "Record Hyprlock OUTPUT from PROCESS and observe its lifecycle messages.
Hyprlock has no public readiness/unlock FD.  Match only its explicit
confirmation messages; an unknown message format cannot enable suspend or
mark a crashed locker as unlocked.  Keep a bounded diagnostic log."
  (when (buffer-live-p (process-buffer process))
    (with-current-buffer (process-buffer process)
      (buffer-disable-undo)
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert output)
        (when (> (buffer-size) 32768)
          (delete-region (point-min) (- (point-max) 16384))))))
  (let* ((text (concat (process-get process 'pending-line) output))
         (end (string-match "[^\n]*\\'" text))
         (complete (substring text 0 end)))
    (process-put process 'pending-line (substring text end))
    (when (eq process helheim-ewm-power--locker)
      (when (and (not (process-get process 'confirmed))
                 (string-match-p "onLockLocked called" complete))
        (process-put process 'confirmed t)
        (setq helheim-ewm-power--lock-state 'locked)
        (helheim-ewm-power--set-locked-hint t)
        (when helheim-ewm-power--sleeping
          (helheim-ewm-power--release-sleep-delay))
        ;; If startup took longer than the blank delay, use a conservative
        ;; fresh 15 minutes rather than count time before lock confirmation.
        (helheim-ewm-power--arm-suspend helheim-ewm-power-suspend-delay))
      (when (and (process-get process 'confirmed)
                 (string-match-p "Unlocked, exiting!" complete))
        (process-put process 'unlocked t)))))

(defun helheim-ewm-power--locker-sentinel (process _event)
  "Restore policy on authenticated unlock, never merely on PROCESS exit."
  (when (and (eq process helheim-ewm-power--locker)
             (memq (process-status process) '(exit signal)))
    (helheim-ewm-power--cancel-suspend)
    (setq helheim-ewm-power--locker nil
          helheim-ewm-power--idle nil)
    (if (and (zerop (process-exit-status process))
             (process-get process 'unlocked))
        (progn
          (setq helheim-ewm-power--lock-state nil)
          (helheim-ewm-power--set-locked-hint nil))
      ;; A lock client dying leaves EWM securely locked.  Launch a replacement
      ;; through emacsclient from another VT; locked input cannot reach Emacs.
      (setq helheim-ewm-power--lock-state 'failed)
      (helheim-ewm-power--warn
       "Hyprlock exited without confirmed unlock. Retry with emacsclient from another VT; see EWM README.org and *EWM Hyprlock*."))
    (when helheim-ewm-power--active
      (helheim-ewm-power--refresh-power)
      (helheim-ewm-power--apply-idle))))

(defun helheim-ewm-lock ()
  "Lock EWM using the single supervised Hyprlock instance."
  (interactive)
  (unless (and helheim-ewm-power--active (bound-and-true-p ewm-mode))
    (user-error "EWM power policy is not active"))
  (unless (process-live-p helheim-ewm-power--locker)
    (unless (and (executable-find "hyprlock") (executable-find "stdbuf"))
      (user-error "Install hyprlock and coreutils (stdbuf) first"))
    (unless (file-readable-p helheim-ewm-power-lock-config)
      (user-error "Missing Hyprlock config: %s" helheim-ewm-power-lock-config))
    (helheim-ewm-power--cancel-suspend)
    (setq helheim-ewm-power--locker
          (make-process
           :name "ewm-hyprlock" :buffer (get-buffer-create "*EWM Hyprlock*")
           ;; Line buffering makes lifecycle messages observable over a pipe.
           :command (list "stdbuf" "-oL" "-eL" "hyprlock"
                          "--config" helheim-ewm-power-lock-config "--grace" "0")
           :connection-type 'pipe :noquery t
           :filter #'helheim-ewm-power--locker-filter
           :sentinel #'helheim-ewm-power--locker-sentinel)
          helheim-ewm-power--lock-state 'starting)
    (helheim-ewm-power--apply-idle)))

(defun helheim-ewm-power--start ()
  "Start power policy once, after EWM is ready."
  (when (and (bound-and-true-p ewm-mode) (not helheim-ewm-power--active))
    (setq helheim-ewm-power--active t
          helheim-ewm-power--saved-idle ewm-idle
          helheim-ewm-power--on-battery (helheim-ewm-power--read-power))
    (add-hook 'ewm-idle-hook #'helheim-ewm-power--idle-changed)
    (add-hook 'kill-emacs-hook #'helheim-ewm-power--stop)
    (helheim-ewm-power--apply-idle)
    (condition-case err
        (push (dbus-register-signal
               :system helheim-ewm-power--upower helheim-ewm-power--upower-path
               "org.freedesktop.DBus.Properties" "PropertiesChanged"
               #'helheim-ewm-power--refresh-power)
              helheim-ewm-power--signals)
      (error (helheim-ewm-power--warn "Cannot watch power changes: %s" err)))
    ;; Sleep handling does not depend on resolving this process's session
    ;; (an Emacs started by a user service may not belong to one).
    (condition-case err
        (progn
          (push (dbus-register-signal
                 :system helheim-ewm-power--login-service
                 helheim-ewm-power--login-path helheim-ewm-power--login-manager
                 "PrepareForSleep" #'helheim-ewm-power--prepare-for-sleep)
                helheim-ewm-power--signals)
          (helheim-ewm-power--inhibit-sleep))
      (error (helheim-ewm-power--warn "Cannot watch sleep requests: %s" err)))
    (condition-case err
        (progn
          (setq helheim-ewm-power--session-path
                (if-let* ((id (getenv "XDG_SESSION_ID")))
                    (dbus-call-method
                     :system helheim-ewm-power--login-service
                     helheim-ewm-power--login-path helheim-ewm-power--login-manager
                     "GetSession" :timeout 1000 id)
                  (dbus-call-method
                   :system helheim-ewm-power--login-service
                   helheim-ewm-power--login-path helheim-ewm-power--login-manager
                   "GetSessionByPID" :timeout 1000 :uint32 (emacs-pid))))
          (push (dbus-register-signal
                 :system helheim-ewm-power--login-service
                 helheim-ewm-power--session-path helheim-ewm-power--login-session
                 "Lock" #'helheim-ewm-power--logind-lock)
                helheim-ewm-power--signals))
      (error (helheim-ewm-power--warn "Cannot watch this logind session: %s" err)))
    (when (eq helheim-ewm-power--on-battery 'unknown)
      (helheim-ewm-power--warn "UPower unavailable; automatic lock/suspend disabled"))))

(defun helheim-ewm-power--stop ()
  "Remove policy resources without terminating the locker or unlocking."
  (when helheim-ewm-power--active
    (setq helheim-ewm-power--active nil)
    (helheim-ewm-power--cancel-suspend)
    (remove-hook 'ewm-idle-hook #'helheim-ewm-power--idle-changed)
    (remove-hook 'kill-emacs-hook #'helheim-ewm-power--stop)
    (dolist (signal helheim-ewm-power--signals)
      (ignore-errors (dbus-unregister-object signal)))
    (setq helheim-ewm-power--signals nil)
    (helheim-ewm-power--release-sleep-delay)
    (setopt ewm-idle helheim-ewm-power--saved-idle)))

(provide 'helheim-ewm-power)
;;; helheim-ewm-power.el ends here
