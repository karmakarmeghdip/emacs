;;; helheim-catppuccin.el -*- lexical-binding: t; no-byte-compile: t -*-
;;; Commentary:
;;
;; Catppuccin theme configuration for Helheim.
;; https://github.com/catppuccin/emacs
;;
;; Flavors available: `latte', `frappe', `macchiato', `mocha'
;;
;;; Code:

(setup catppuccin-theme
  (:install catppuccin-theme :wait t)
  (:setopt catppuccin-flavor 'mocha
           catppuccin-highlight-matches t))

;; Optional: Customize faces specifically for Catppuccin
;; (helheim-theme-set-faces 'catppuccin
;;   '(cursor :background "#cdd6f4")
;;   '(hel-normal-state-fake-cursor :background "#89b4fa")
;;   '(hel-insert-state-fake-cursor :background "#a6e3a1"))

(provide 'helheim-catppuccin)
;;; helheim-catppuccin.el ends here
