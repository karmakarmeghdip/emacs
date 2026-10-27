;;; helheim-ewm-consult-tests.el --- Launcher tests -*- lexical-binding: t -*-

(require 'ert)
(require 'cl-lib)
(require 'helheim-ewm-consult)

(defvar ewm-mode nil)

(ert-deftest helheim-ewm-consult-preserves-sources ()
  (let ((consult-buffer-sources '(consult-source-buffer consult-source-bookmark)))
    (load "helheim-ewm-consult" nil t)
    (load "helheim-ewm-consult" nil t)
    (should (equal consult-buffer-sources
                   '(consult-source-buffer consult-source-bookmark
                     helheim-ewm-consult-source-apps)))))

(ert-deftest helheim-ewm-consult-only-enabled-in-ewm ()
  (let ((enabled (plist-get helheim-ewm-consult-source-apps :enabled)))
    (let ((ewm-mode nil))
      (should-not (funcall enabled)))
    (let ((ewm-mode t))
      (should (funcall enabled)))))

(ert-deftest helheim-ewm-consult-reads-current-apps ()
  (let ((apps '(("Browser" . "browser %u") ("Terminal" . "terminal"))))
    (cl-letf (((symbol-function 'ewm-list-xdg-apps) (lambda () apps)))
      (let ((items (plist-get helheim-ewm-consult-source-apps :items)))
        (should (equal (funcall items) '("Browser" "Terminal")))
        (setq apps '(("Editor" . "editor %f")))
        (should (equal (funcall items) '("Editor")))))))

(ert-deftest helheim-ewm-consult-launches-via-ewm ()
  (let (launched)
    (cl-letf (((symbol-function 'ewm-launch-xdg-command)
               (lambda (name) (setq launched name))))
      (funcall (plist-get helheim-ewm-consult-source-apps :action) "Browser")
      (should (equal launched "Browser"))))
  (should (eq (plist-get helheim-ewm-consult-source-apps :narrow) ?a)))

;;; helheim-ewm-consult-tests.el ends here
