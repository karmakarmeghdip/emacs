;;; helheim-typescript.el -*- lexical-binding: t; no-byte-compile: t -*-
;;; Commentary:
;;
;; TypeScript, TSX, and JavaScript configuration using tree-sitter modes
;; and Eglot LSP.
;;
;;; Code:

(setup typescript-ts-mode
  (:when (treesit-available-p))
  (add-to-list 'major-mode-remap-defaults '(typescript-mode . typescript-ts-mode))
  (:hook (typescript-ts-mode-hook tsx-ts-mode-hook) helheim-lsp)
  (:setopt typescript-ts-mode-indent-offset 2))

(setup tsx-ts-mode
  (:when (treesit-available-p))
  (:setopt typescript-ts-mode-indent-offset 2))

(setup typescript-mode
  (:install t)
  (:hook typescript-mode-hook helheim-lsp)
  (:setopt typescript-indent-level 2))

(setup js-ts-mode
  (:when (treesit-available-p))
  (add-to-list 'major-mode-remap-defaults '(js-mode . js-ts-mode))
  (:hook js-ts-mode-hook helheim-lsp)
  (:setopt js-indent-level 2))

;;; .
(provide 'helheim-typescript)
;;; helheim-typescript.el ends here
