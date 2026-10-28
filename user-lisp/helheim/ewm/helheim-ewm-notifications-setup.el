;;; helheim-ewm-notifications-setup.el --- Notification startup -*- lexical-binding: t; no-byte-compile: t -*-

;;; Commentary:
;; Queue EDNC during normal initialization, even when a daemon client loads
;; EWM later.  Helheim's user-lisp autoload scan installs the startup form.

;;; Code:

;;;###autoload (with-eval-after-load 'helheim-setup (require 'helheim-ewm-notifications-setup))

(setup ednc
  (:install t)
  (:require t)
  (with-eval-after-load 'ewm
    (require 'helheim-ewm-notifications)))

(provide 'helheim-ewm-notifications-setup)
;;; helheim-ewm-notifications-setup.el ends here
