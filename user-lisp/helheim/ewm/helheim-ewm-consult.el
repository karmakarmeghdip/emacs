;;; helheim-ewm-consult.el --- EWM apps in Consult -*- lexical-binding: t -*-

;;; Commentary:
;; Extend the existing buffer sources without replacing their configuration.

;;; Code:

(require 'consult)

(defvar ewm-mode)
(declare-function ewm-list-xdg-apps "ewm-core" ())
(declare-function ewm-launch-xdg-command "ewm-commands" (name))

(defvar helheim-ewm-consult-source-apps
  `(:name "Apps"
    :narrow ?a
    :category app
    :enabled ,(lambda () (bound-and-true-p ewm-mode))
    :items ,(lambda () (mapcar #'car (ewm-list-xdg-apps)))
    :action ,#'ewm-launch-xdg-command)
  "XDG desktop applications for `consult-buffer' while EWM is active.")

(add-to-list 'consult-buffer-sources 'helheim-ewm-consult-source-apps t)

(provide 'helheim-ewm-consult)
;;; helheim-ewm-consult.el ends here
