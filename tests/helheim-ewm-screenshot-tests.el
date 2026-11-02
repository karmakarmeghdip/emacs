;;; helheim-ewm-screenshot-tests.el --- Tests for screenshot capture -*- lexical-binding: t -*-

;;; Commentary:

;; Unit tests for EWM screenshot capture.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'helheim-ewm-screenshot)

(ert-deftest helheim-ewm-screenshot-command-region ()
  "Command string for region screenshot contains slurp, grim, wl-copy, and notify."
  (let ((helheim-ewm-screenshot-directory "/tmp/screenshots")
        (helheim-ewm-screenshot-copy-to-clipboard t)
        (helheim-ewm-screenshot-notify t))
    (let ((cmd (helheim-ewm-screenshot--build-command t)))
      (should (string-match-p "dir=/tmp/screenshots" cmd))
      (should (string-match-p "mkdir -p \"\\$dir\"" cmd))
      (should (string-match-p "geom=\\$(slurp)" cmd))
      (should (string-match-p "grim -g \"\\$geom\" \"\\$file\"" cmd))
      (should (string-match-p "wl-copy --type image/png" cmd))
      (should (string-match-p "notify-send" cmd)))))

(ert-deftest helheim-ewm-screenshot-command-fullscreen ()
  "Command string for full-screen screenshot skips slurp."
  (let ((helheim-ewm-screenshot-directory "/tmp/screenshots")
        (helheim-ewm-screenshot-copy-to-clipboard t)
        (helheim-ewm-screenshot-notify t))
    (let ((cmd (helheim-ewm-screenshot--build-command nil)))
      (should (string-match-p "dir=/tmp/screenshots" cmd))
      (should-not (string-match-p "slurp" cmd))
      (should (string-match-p "grim \"\\$file\"" cmd))
      (should (string-match-p "wl-copy --type image/png" cmd))
      (should (string-match-p "notify-send" cmd)))))

(ert-deftest helheim-ewm-screenshot-custom-options ()
  "Configurable options correctly alter the generated shell script."
  (let ((helheim-ewm-screenshot-directory "/custom/path")
        (helheim-ewm-screenshot-copy-to-clipboard nil)
        (helheim-ewm-screenshot-notify nil))
    (let ((cmd (helheim-ewm-screenshot--build-command t)))
      (should (string-match-p "dir=/custom/path" cmd))
      (should-not (string-match-p "wl-copy" cmd))
      (should-not (string-match-p "notify-send" cmd)))))

(ert-deftest helheim-ewm-screenshot-missing-grim-errors ()
  "Missing `grim' signals user-error."
  (cl-letf (((symbol-function 'executable-find)
             (lambda (name)
               (unless (equal name "grim") "/usr/bin/slurp"))))
    (should-error (helheim-ewm-screenshot--check-executables t) :type 'user-error)
    (should-error (helheim-ewm-screenshot--check-executables nil) :type 'user-error)))

(ert-deftest helheim-ewm-screenshot-missing-slurp-errors-only-for-region ()
  "Missing `slurp' signals user-error for region but not for full-screen."
  (cl-letf (((symbol-function 'executable-find)
             (lambda (name)
               (unless (equal name "slurp") "/usr/bin/grim"))))
    (should-error (helheim-ewm-screenshot--check-executables t) :type 'user-error)
    (should-not (helheim-ewm-screenshot--check-executables nil))))

(ert-deftest helheim-ewm-screenshot-runs-make-process ()
  "Execution calls `make-process' with non-blocking arguments."
  (let (spawned-args)
    (cl-letf (((symbol-function 'executable-find) (lambda (_) "/usr/bin/mock"))
              ((symbol-function 'make-process)
               (lambda (&rest args) (setq spawned-args args) nil)))
      (setq helheim-ewm-screenshot--process nil)
      (helheim-ewm-screenshot-region)
      (should (equal (plist-get spawned-args :name) "helheim-ewm-screenshot"))
      (should (plist-get spawned-args :noquery))
      (should (equal (car (plist-get spawned-args :command)) "sh")))))

(ert-deftest helheim-ewm-screenshot-prevents-overlay-stacking ()
  "Triggering region screenshot terminates any previous process and kills running slurp."
  (let ((fake-proc (make-pipe-process :name "fake-screenshot" :noquery t))
        pkill-called)
    (setq helheim-ewm-screenshot--process fake-proc)
    (cl-letf (((symbol-function 'executable-find) (lambda (_) "/usr/bin/mock"))
              ((symbol-function 'call-process)
               (lambda (prog &rest args)
                 (when (and (equal prog "pkill") (member "-x" args) (member "slurp" args))
                   (setq pkill-called t))
                 0))
              ((symbol-function 'make-process)
               (lambda (&rest _) 'new-proc)))
      (helheim-ewm-screenshot-region)
      (should-not (process-live-p fake-proc))
      (should pkill-called)
      (should (eq helheim-ewm-screenshot--process 'new-proc)))))

(ert-deftest helheim-ewm-screenshot-cancel-cleans-up ()
  "Cancelling screenshot terminates running process and slurp."
  (let ((fake-proc (make-pipe-process :name "fake-screenshot" :noquery t))
        pkill-called)
    (setq helheim-ewm-screenshot--process fake-proc)
    (cl-letf (((symbol-function 'call-process)
               (lambda (prog &rest args)
                 (when (and (equal prog "pkill") (member "-x" args) (member "slurp" args))
                   (setq pkill-called t))
                 0)))
      (helheim-ewm-screenshot-cancel)
      (should-not (process-live-p fake-proc))
      (should pkill-called)
      (should-not helheim-ewm-screenshot--process))))

(provide 'helheim-ewm-screenshot-tests)

;;; helheim-ewm-screenshot-tests.el ends here
