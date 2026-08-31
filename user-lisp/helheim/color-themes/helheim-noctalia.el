;;; helheim-noctalia.el -*- lexical-binding: t; no-byte-compile: t -*-
;;; Commentary:
;;
;; Helheim UI integrations and persistent face overrides for the `noctalia' theme.
;; This file resides in user-lisp/ and will NOT be overwritten when Noctalia
;; updates or regenerates themes/noctalia-theme.el.
;;
;;; Code:

(declare-function helheim-theme-set-faces "helheim-lib")

;;; Face overrides for Noctalia theme
;; Using :inherit ensures these faces dynamically adapt whenever Noctalia
;; regenerates themes/noctalia-theme.el with updated color palettes.

(helheim-theme-set-faces 'noctalia
  ;; UI & Line highlighting
  '(hl-line :inherit highlight :extend t)
  '(mode-line-active :inherit mode-line)

  ;; Minibuffer & Vertico
  '(vertico-current :inherit highlight :weight bold)
  '(vertico-group-title :inherit font-lock-keyword-face :weight bold)
  '(vertico-group-separator :inherit shadow :strike-through t)

  ;; Marginalia
  '(marginalia-key :inherit font-lock-keyword-face :weight bold)
  '(marginalia-documentation :inherit font-lock-doc-face :slant italic)
  '(marginalia-value :inherit font-lock-constant-face)
  '(marginalia-type :inherit font-lock-type-face)
  '(marginalia-file-name :inherit default)
  '(marginalia-file-owner :inherit shadow)
  '(marginalia-file-priv-no :inherit shadow)
  '(marginalia-file-priv-read :inherit font-lock-string-face)
  '(marginalia-file-priv-write :inherit error)
  '(marginalia-file-priv-exec :inherit font-lock-keyword-face)
  '(marginalia-mode :inherit font-lock-keyword-face)
  '(marginalia-date :inherit font-lock-variable-name-face)
  '(marginalia-version :inherit font-lock-constant-face)
  '(marginalia-size :inherit shadow)

  ;; Orderless
  '(orderless-match-face-0 :inherit font-lock-function-name-face :weight bold)
  '(orderless-match-face-1 :inherit font-lock-keyword-face :weight bold)
  '(orderless-match-face-2 :inherit font-lock-constant-face :weight bold)
  '(orderless-match-face-3 :inherit font-lock-type-face :weight bold)

  ;; Consult
  '(consult-preview-line :inherit highlight)
  '(consult-preview-match :inherit match)
  '(consult-highlight-match :inherit isearch)
  '(consult-file :inherit default)
  '(consult-line-number :inherit shadow)

  ;; Diff-hl
  '(diff-hl-insert :inherit success)
  '(diff-hl-delete :inherit error)
  '(diff-hl-change :inherit warning)

  ;; Doom Modeline
  '(doom-modeline-bar :inherit cursor)
  '(doom-modeline-buffer-file :inherit bold)
  '(doom-modeline-buffer-path :inherit shadow)
  '(doom-modeline-buffer-project-root :inherit font-lock-constant-face)
  '(doom-modeline-buffer-modified :inherit error :weight bold)
  '(doom-modeline-buffer-major-mode :inherit font-lock-function-name-face :weight bold)
  '(doom-modeline-project-dir :inherit font-lock-constant-face :weight bold)
  '(doom-modeline-project-parent-dir :inherit shadow)
  '(doom-modeline-info :inherit font-lock-constant-face)
  '(doom-modeline-warning :inherit warning :weight bold)
  '(doom-modeline-urgent :inherit error :weight bold)

  ;; Flymake
  '(flymake-error :inherit error :underline t)
  '(flymake-warning :inherit warning :underline t)
  '(flymake-note :inherit shadow :underline t))

(provide 'helheim-noctalia)
;;; helheim-noctalia.el ends here
