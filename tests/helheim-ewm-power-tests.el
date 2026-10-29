;;; helheim-ewm-power-tests.el --- Power policy tests -*- lexical-binding: t -*-

;;; Commentary:
;; Run: emacs -Q --batch -L user-lisp/helheim/ewm \
;;   -l tests/helheim-ewm-power-tests.el -f ert-run-tests-batch-and-exit
;; All power, locker and suspend operations are mocked.

;;; Code:

(require 'ert)
(require 'cl-lib)
(let ((load-prefer-newer t))
  (require 'helheim-ewm-power))

;; In tests no compositor is loaded and setting its idle option has no effects.
(defcustom ewm-idle nil "Mock EWM idle policy." :type 'sexp :group 'environment)
(defvar ewm-mode t)
(defvar ewm-insomnia-mode nil)
(defvar ewm-idle-hook nil)

(defmacro helheim-ewm-power-test--with-state (&rest body)
  "Run BODY with isolated policy state and no live D-Bus/power effects."
  (declare (indent 0) (debug t))
  `(let ((helheim-ewm-power--active t)
         (helheim-ewm-power--on-battery nil)
         (helheim-ewm-power--lock-state nil)
         (helheim-ewm-power--locker nil)
         (helheim-ewm-power--idle nil)
         (helheim-ewm-power--suspend-timer nil)
         (helheim-ewm-power--session-path nil)
         (helheim-ewm-power--signals nil)
         (helheim-ewm-power--sleep-fd nil)
         (helheim-ewm-power--sleeping nil)
         (helheim-ewm-power-lock-delay 300)
         (helheim-ewm-power-blank-delay 30)
         (helheim-ewm-power-suspend-delay 900)
         (ewm-mode t) (ewm-insomnia-mode nil) (ewm-idle nil)
         (power nil) (armed nil) (cancelled nil) (suspended nil)
         (lock-requests 0) (warnings nil))
     (cl-letf (((symbol-function 'helheim-ewm-power--read-power) (lambda () power))
               ((symbol-function 'run-at-time)
                (lambda (delay _repeat function &rest _)
                  (when (eq function #'helheim-ewm-power--suspend)
                    (setq armed (list delay function)) 'fake-timer)))
               ((symbol-function 'timerp) (lambda (timer) (eq timer 'fake-timer)))
               ((symbol-function 'cancel-timer) (lambda (_) (setq cancelled t)))
               ((symbol-function 'dbus-call-method-asynchronously)
                (lambda (&rest _) (setq suspended t)))
               ((symbol-function 'helheim-ewm-power--warn)
                (lambda (&rest message) (push message warnings))))
       ,@body)))

(ert-deftest helheim-ewm-power-unlocked-ac-and-battery ()
  (helheim-ewm-power-test--with-state
    (helheim-ewm-power--apply-idle)
    (should-not ewm-idle)
    (setq power t)
    (helheim-ewm-power--refresh-power)
    (should (equal ewm-idle '(300 . "true")))
    (setq power nil)
    (helheim-ewm-power--refresh-power)
    (should-not ewm-idle)))

(ert-deftest helheim-ewm-power-unknown-power-is-conservative ()
  (helheim-ewm-power-test--with-state
    (setq power 'unknown)
    (helheim-ewm-power--refresh-power)
    (should-not ewm-idle)
    (setq helheim-ewm-power--lock-state 'locked
          helheim-ewm-power--idle t)
    (helheim-ewm-power--arm-suspend 900)
    (should-not armed)))

(ert-deftest helheim-ewm-power-automatic-lock-rechecks-ac ()
  (helheim-ewm-power-test--with-state
    (cl-letf (((symbol-function 'helheim-ewm-lock)
               (lambda () (cl-incf lock-requests))))
      (setq power t helheim-ewm-power--on-battery t)
      (helheim-ewm-power--idle-changed t)
      (should (= lock-requests 1))
      (setq power nil)
      (helheim-ewm-power--idle-changed t)
      (should (= lock-requests 1)))))

(ert-deftest helheim-ewm-power-locked-ac-still-blanks ()
  (helheim-ewm-power-test--with-state
    (setq helheim-ewm-power--lock-state 'locked)
    (helheim-ewm-power--apply-idle)
    (should (= ewm-idle 30))
    (helheim-ewm-power--idle-changed t)
    (should-not armed)))

(ert-deftest helheim-ewm-power-locked-battery-countdown-and-input ()
  (helheim-ewm-power-test--with-state
    (setq power t helheim-ewm-power--on-battery t
          helheim-ewm-power--lock-state 'locked)
    (helheim-ewm-power--apply-idle)
    (helheim-ewm-power--idle-changed t)
    (should (= (car armed) 870))
    (helheim-ewm-power--idle-changed nil)
    (should cancelled)
    (should-not helheim-ewm-power--suspend-timer)
    (setq cancelled nil)
    (helheim-ewm-power--idle-changed t)
    (should (= (car armed) 870))))

(ert-deftest helheim-ewm-power-ac-cancels-and-unplug-starts-fresh ()
  (helheim-ewm-power-test--with-state
    (setq helheim-ewm-power--lock-state 'locked
          helheim-ewm-power--idle t ewm-idle 30)
    (setq power t)
    (helheim-ewm-power--refresh-power)
    (should (= (car armed) 900))
    (setq power nil)
    (helheim-ewm-power--refresh-power)
    (should cancelled)
    (should-not helheim-ewm-power--suspend-timer)
    (should (= ewm-idle 30))))

(ert-deftest helheim-ewm-power-suspend-guards ()
  (dolist (case '((locked t t nil nil t)
                  (locked t nil nil nil nil)
                  (locked t unknown nil nil nil)
                  (locked nil t nil nil nil)
                  (starting t t nil nil nil)
                  (failed t t nil nil nil)
                  (nil t t nil nil nil)
                  (locked t t t nil nil)
                  (locked t t nil t nil)))
    (helheim-ewm-power-test--with-state
      (pcase-let ((`(,state ,idle ,source ,insomnia ,sleeping ,expected) case))
        (setq helheim-ewm-power--lock-state state
              helheim-ewm-power--idle idle
              helheim-ewm-power--on-battery source
              power source ewm-idle 30
              ewm-insomnia-mode insomnia
              helheim-ewm-power--sleeping sleeping)
        (helheim-ewm-power--suspend)
        (should (eq suspended expected))))))

(ert-deftest helheim-ewm-power-late-ac-change-prevents-suspend ()
  (helheim-ewm-power-test--with-state
    (setq helheim-ewm-power--lock-state 'locked
          helheim-ewm-power--idle t
          helheim-ewm-power--on-battery t ewm-idle 30 power nil)
    (helheim-ewm-power--suspend)
    (should-not suspended)))

(ert-deftest helheim-ewm-power-no-needless-idle-reset ()
  (helheim-ewm-power-test--with-state
    (setq helheim-ewm-power--lock-state 'locked
          helheim-ewm-power--idle t ewm-idle 30
          helheim-ewm-power--suspend-timer 'fake-timer)
    (helheim-ewm-power--apply-idle)
    (should helheim-ewm-power--idle)
    (should-not cancelled)))

(ert-deftest helheim-ewm-power-locker-lifecycle-and-split-lines ()
  (helheim-ewm-power-test--with-state
    (let ((process (make-pipe-process :name "ewm-test-locker" :noquery t)))
      (unwind-protect
          (progn
            (setq helheim-ewm-power--locker process
                  helheim-ewm-power--lock-state 'starting)
            (helheim-ewm-power--locker-filter process "[LOG] onLockLo")
            (should (eq helheim-ewm-power--lock-state 'starting))
            (helheim-ewm-power--locker-filter process "cked called\n")
            (should (eq helheim-ewm-power--lock-state 'locked))
            (helheim-ewm-power--locker-filter process "[LOG] Unlocked, exiting!\n")
            (should (process-get process 'unlocked)))
        (delete-process process)))))

(ert-deftest helheim-ewm-power-rejected-lock-is-not-unlock ()
  (helheim-ewm-power-test--with-state
    (let ((process (make-pipe-process :name "ewm-test-rejected" :noquery t)))
      (unwind-protect
          (progn
            (setq helheim-ewm-power--locker process
                  helheim-ewm-power--lock-state 'starting)
            (helheim-ewm-power--locker-filter
             process "onLockFinished called\nUnlocked, exiting!\n")
            (should-not (process-get process 'unlocked)))
        (delete-process process)))))

(ert-deftest helheim-ewm-power-crash-does-not-restore-unlocked-policy ()
  (helheim-ewm-power-test--with-state
    (setq helheim-ewm-power--locker 'fake-process
          helheim-ewm-power--lock-state 'locked)
    (cl-letf (((symbol-function 'process-status) (lambda (_) 'signal))
              ((symbol-function 'process-exit-status) (lambda (_) 9)))
      (helheim-ewm-power--locker-sentinel 'fake-process "killed"))
    (should (eq helheim-ewm-power--lock-state 'failed))
    (should (= ewm-idle 30))
    (should warnings)))

(ert-deftest helheim-ewm-power-normal-exit-without-unlock-is-failure ()
  (helheim-ewm-power-test--with-state
    (setq helheim-ewm-power--locker 'fake-process)
    (cl-letf (((symbol-function 'process-status) (lambda (_) 'exit))
              ((symbol-function 'process-exit-status) (lambda (_) 0))
              ((symbol-function 'process-get) (lambda (&rest _) nil)))
      (helheim-ewm-power--locker-sentinel 'fake-process "finished"))
    (should (eq helheim-ewm-power--lock-state 'failed))))

(ert-deftest helheim-ewm-power-successful-unlock-restores-battery-policy ()
  (helheim-ewm-power-test--with-state
    (setq power t helheim-ewm-power--on-battery t
          helheim-ewm-power--locker 'fake-process
          helheim-ewm-power--lock-state 'locked ewm-idle 30)
    (cl-letf (((symbol-function 'process-status) (lambda (_) 'exit))
              ((symbol-function 'process-exit-status) (lambda (_) 0))
              ((symbol-function 'process-get) (lambda (&rest _) t)))
      (helheim-ewm-power--locker-sentinel 'fake-process "finished"))
    (should-not helheim-ewm-power--lock-state)
    (should (equal ewm-idle '(300 . "true")))))

(ert-deftest helheim-ewm-power-duplicate-lock-request-is-no-op ()
  (helheim-ewm-power-test--with-state
    (setq helheim-ewm-power--locker 'fake-process)
    (cl-letf (((symbol-function 'process-live-p) (lambda (_) t))
              ((symbol-function 'make-process) (lambda (&rest _) (ert-fail "Duplicate locker"))))
      (helheim-ewm-lock))))

(ert-deftest helheim-ewm-power-before-sleep-releases-delay-after-confirmation ()
  (helheim-ewm-power-test--with-state
    (let ((released nil))
      (cl-letf (((symbol-function 'helheim-ewm-power--release-sleep-delay)
                 (lambda () (setq released t)))
                ((symbol-function 'helheim-ewm-power--logind-lock)
                 (lambda () (cl-incf lock-requests))))
        (helheim-ewm-power--prepare-for-sleep t)
        (should (= lock-requests 1))
        (should-not released)
        (setq helheim-ewm-power--lock-state 'locked)
        (helheim-ewm-power--prepare-for-sleep t)
        (should released)))))

(ert-deftest helheim-ewm-power-resume-cancels-old-deadline ()
  (helheim-ewm-power-test--with-state
    (setq helheim-ewm-power--idle t
          helheim-ewm-power--suspend-timer 'fake-timer)
    (cl-letf (((symbol-function 'helheim-ewm-power--inhibit-sleep) #'ignore))
      (helheim-ewm-power--prepare-for-sleep nil))
    (should cancelled)
    (should-not helheim-ewm-power--idle)
    (should-not helheim-ewm-power--suspend-timer)))

(ert-deftest helheim-ewm-power-confirmation-releases-external-sleep-delay ()
  (helheim-ewm-power-test--with-state
    (let ((process (make-pipe-process :name "ewm-test-sleep-locker" :noquery t))
          (released nil))
      (unwind-protect
          (cl-letf (((symbol-function 'helheim-ewm-power--release-sleep-delay)
                     (lambda () (setq released t))))
            (setq helheim-ewm-power--locker process
                  helheim-ewm-power--lock-state 'starting
                  helheim-ewm-power--sleeping t)
            (helheim-ewm-power--locker-filter process "onLockLocked called\n")
            (should released)
            (should (eq helheim-ewm-power--lock-state 'locked))
            (should-not armed))
        (delete-process process)))))

(ert-deftest helheim-ewm-power-start-is-idempotent-and-stop-cleans-up ()
  (helheim-ewm-power-test--with-state
    (let ((ewm-idle-hook nil) (kill-emacs-hook nil)
          (registrations 0) (unregistered 0) (closed nil))
      (setq helheim-ewm-power--active nil ewm-idle 123)
      (cl-letf (((symbol-function 'dbus-call-method)
                 (lambda (&rest args)
                   (pcase (nth 4 args)
                     ("GetSession" "/session/test")
                     ("GetSessionByPID" "/session/test")
                      ("Inhibit"
                       (should (equal (nthcdr 5 args)
                                      '(:timeout 1000 :keep-fd
                                        "sleep" "EWM"
                                        "Lock the session before sleep" "delay")))
                      42))))
                ((symbol-function 'dbus-register-signal)
                 (lambda (&rest _) (cl-incf registrations)))
                ((symbol-function 'dbus-unregister-object)
                 (lambda (_) (cl-incf unregistered)))
                ((symbol-function 'dbus--fd-close)
                 (lambda (fd) (setq closed fd))))
        (helheim-ewm-power--start)
        (helheim-ewm-power--start)
        (should (= registrations 3))
        (should helheim-ewm-power--active)
        (should-not ewm-idle)
        (should (= helheim-ewm-power--sleep-fd 42))
        (should (memq #'helheim-ewm-power--idle-changed ewm-idle-hook))
        (helheim-ewm-power--stop)
        (should (= ewm-idle 123))
        (should (= unregistered 3))
        (should (= closed 42))
        (should-not helheim-ewm-power--active)
        (should-not ewm-idle-hook)
        (should-not kill-emacs-hook)
        (should-not warnings)))))

;;; helheim-ewm-power-tests.el ends here
