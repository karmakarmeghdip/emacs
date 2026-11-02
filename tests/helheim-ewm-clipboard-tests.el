;;; helheim-ewm-clipboard-tests.el --- Tests for EWM clipboard manager -*- lexical-binding: t -*-

;;; Commentary:

;; Unit tests for EWM clipboard history management and selection synchronization.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'helheim-ewm-clipboard)

(defvar ewm-mode nil)

(ert-deftest helheim-ewm-clipboard-sync-promotes-to-head ()
  "Selected item is promoted to the head of kill-ring and synced."
  (let ((kill-ring (list "item-1" "item-2" "item-3"))
        (ewm-mode t)
        cut-called)
    (cl-letf (((symbol-function 'ewm--interprogram-cut-function)
               (lambda (text) (setq cut-called text))))
      (helheim-ewm-clipboard--sync-selection "item-2")
      (should (equal (car kill-ring) "item-2"))
      (should (equal kill-ring '("item-2" "item-1" "item-3"))))))

(ert-deftest helheim-ewm-clipboard-copy-only-does-not-insert ()
  "Prefix argument only updates active clipboard without inserting."
  (let ((kill-ring (list "first" "second"))
        (ewm-mode t)
        inserted)
    (cl-letf (((symbol-function 'consult--read-from-kill-ring)
               (lambda () "second"))
              ((symbol-function 'insert-for-yank)
               (lambda (str) (setq inserted str))))
      (helheim-ewm-clipboard t)
      (should-not inserted)
      (should (equal (car kill-ring) "second")))))

(ert-deftest helheim-ewm-clipboard-inserts-and-syncs ()
  "Default call inserts text and syncs to active clipboard."
  (let ((kill-ring (list "first" "second"))
        (ewm-mode t)
        inserted)
    (with-temp-buffer
      (cl-letf (((symbol-function 'consult--read-from-kill-ring)
                 (lambda () "second"))
                ((symbol-function 'insert-for-yank)
                 (lambda (str) (setq inserted str) (insert str))))
        (helheim-ewm-clipboard nil)
        (should (equal inserted "second"))
        (should (equal (buffer-string) "second"))
        (should (equal (car kill-ring) "second"))))))

(ert-deftest helheim-ewm-clipboard-read-only-graceful ()
  "In a read-only buffer, clipboard is updated without raising an unhandled error."
  (let ((kill-ring (list "a" "b"))
        (ewm-mode t))
    (with-temp-buffer
      (setq buffer-read-only t)
      (cl-letf (((symbol-function 'consult--read-from-kill-ring)
                 (lambda () "b")))
        (helheim-ewm-clipboard nil)
        (should (equal (car kill-ring) "b"))))))

(provide 'helheim-ewm-clipboard-tests)

;;; helheim-ewm-clipboard-tests.el ends here
