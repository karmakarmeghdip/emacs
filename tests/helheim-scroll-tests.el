;;; helheim-scroll-tests.el --- Tests for horizontal scroll guard and fill column indicator -*- lexical-binding: t -*-

;;; Commentary:

;; Unit tests for horizontal scrolling protection and fill column indicator.

;;; Code:

(require 'ert)

;; Provide definitions if running standalone in emacs -Q
(unless (fboundp 'helheim-window-text-overflows-p)
  (defun helheim-window-text-overflows-p (&optional window)
    "Return non-nil if any visible line in WINDOW extends past the right edge."
    (let ((win (or window (selected-window))))
      (with-selected-window win
        (and truncate-lines
             (not (bound-and-true-p visual-line-mode))
             (let* ((w-width (window-body-width win))
                    (w-start (window-start win))
                    (w-end (or (window-end win t) (point-max)))
                    (hscroll (window-hscroll win))
                    (overflow nil))
               (save-excursion
                 (goto-char w-start)
                 (while (and (not overflow) (< (point) w-end) (not (eobp)))
                   (end-of-line)
                   (if (> (current-column) (+ w-width hscroll))
                       (setq overflow t)
                     (forward-line 1))))
               overflow)))))

  (defun helheim-scroll-left--guard (orig-fun &optional arg set-minimum)
    (interactive "P")
    (let ((win (selected-window)))
      (with-selected-window win
        (if (or (not truncate-lines) (bound-and-true-p visual-line-mode))
            (when (> (window-hscroll win) 0)
              (set-window-hscroll win 0))
          (when (helheim-window-text-overflows-p win)
            (funcall orig-fun arg set-minimum))))))

  (defun helheim-scroll-right--guard (orig-fun &optional arg set-minimum)
    (interactive "P")
    (let ((win (selected-window)))
      (with-selected-window win
        (if (or (not truncate-lines) (bound-and-true-p visual-line-mode))
            (when (> (window-hscroll win) 0)
              (set-window-hscroll win 0))
          (when (> (window-hscroll win) 0)
            (funcall orig-fun arg set-minimum))))))

  (advice-add 'scroll-left :around #'helheim-scroll-left--guard)
  (advice-add 'scroll-right :around #'helheim-scroll-right--guard))

(ert-deftest helheim-scroll-fill-column-indicator-disabled ()
  "Verify display-fill-column-indicator is nil and not in prog-mode-hook."
  (should-not (default-value 'display-fill-column-indicator))
  (should-not (memq 'helheim-show-fill-column-indicator prog-mode-hook)))

(ert-deftest helheim-scroll-wrapped-buffer-ignores-scroll-left ()
  "In a buffer with truncate-lines nil, scroll-left is ignored and hscroll stays 0."
  (let ((win (selected-window)))
    (with-temp-buffer
      (set-window-buffer win (current-buffer))
      (setq truncate-lines nil)
      (insert "Sample text for word wrapped buffer.\nAnother line of text.")
      (set-window-hscroll win 0)
      (scroll-left 5)
      (should (= (window-hscroll win) 0)))))

(ert-deftest helheim-scroll-wrapped-buffer-resets-positive-hscroll ()
  "In a buffer with truncate-lines nil and hscroll > 0, scroll-left resets hscroll to 0."
  (let ((win (selected-window)))
    (with-temp-buffer
      (set-window-buffer win (current-buffer))
      (setq truncate-lines nil)
      (insert "Sample wrapped text.")
      (set-window-hscroll win 10)
      (should (= (window-hscroll win) 10))
      (scroll-left 2)
      (should (= (window-hscroll win) 0)))))

(ert-deftest helheim-scroll-visual-line-mode-ignores-scroll ()
  "In visual-line-mode, horizontal scrolling is prevented."
  (let ((win (selected-window)))
    (with-temp-buffer
      (set-window-buffer win (current-buffer))
      (visual-line-mode 1)
      (insert "Sample visual-line text.")
      (set-window-hscroll win 0)
      (scroll-left 5)
      (should (= (window-hscroll win) 0)))))

(ert-deftest helheim-scroll-truncated-buffer-short-lines-no-overflow ()
  "In a truncated buffer with short lines, scroll-left is prevented."
  (let ((win (selected-window)))
    (with-temp-buffer
      (set-window-buffer win (current-buffer))
      (setq truncate-lines t)
      (insert "Short line 1\nShort line 2\n")
      (goto-char (point-min))
      (set-window-hscroll win 0)
      (redisplay)
      (scroll-left 5)
      (should (= (window-hscroll win) 0)))))

(ert-deftest helheim-scroll-truncated-buffer-overflow-scrolls ()
  "In a truncated buffer with overflowing lines, scroll-left and scroll-right operate."
  (let ((win (selected-window)))
    (with-temp-buffer
      (set-window-buffer win (current-buffer))
      (setq truncate-lines t)
      ;; Insert a line significantly longer than typical window width (500 chars)
      (insert (make-string 500 ?x))
      (goto-char (point-min))
      (set-window-hscroll win 0)
      (redisplay)
      (should (helheim-window-text-overflows-p win))
      (scroll-left 10)
      (should (= (window-hscroll win) 10))
      (scroll-right 4)
      (should (= (window-hscroll win) 6))
      (scroll-right 10)
      (should (= (window-hscroll win) 0)))))

(provide 'helheim-scroll-tests)

;;; helheim-scroll-tests.el ends here
