;;; helheim-ewm-notifications-tests.el --- EDNC tests -*- lexical-binding: t -*-

(require 'ert)
(require 'cl-lib)
(require 'helheim-ewm-notifications)

(defvar ewm-mode nil)

(defun helheim-ewm-notifications-test--notification ()
  (ednc--notification-create :id 1 :app-name "Chat" :summary "New message"
                             :body "Hello\nworld" :actions '("default" "Open")))

(ert-deftest helheim-ewm-notifications-single-line-clickable-preview ()
  (let* ((notification (helheim-ewm-notifications-test--notification))
         (preview (helheim-ewm-notifications--preview notification))
         (command (lookup-key (get-text-property 0 'keymap preview) [mouse-1]))
         opened)
    (should (string-match-p "Chat — New message — Hello world" preview))
    (should-not (string-match-p "\n" preview))
    (cl-letf (((symbol-function 'helheim-ewm-notifications--open)
               (lambda (value) (setq opened value))))
      (funcall command nil))
    (should (eq opened notification))))

(ert-deftest helheim-ewm-notifications-defers-during-prompts ()
  (let* ((notification (helheim-ewm-notifications-test--notification))
         (helheim-ewm-notifications--pending notification)
         (helheim-ewm-notifications--timer nil)
         scheduled)
    (cl-letf (((symbol-function 'active-minibuffer-window) (lambda () t))
              ((symbol-function 'run-at-time)
               (lambda (&rest args) (setq scheduled args)))
              ((symbol-function 'message) (lambda (&rest _) (ert-fail "Prompt overwritten"))))
      (helheim-ewm-notifications--flush))
    (should scheduled)
    (should (eq helheim-ewm-notifications--pending notification))))

(ert-deftest helheim-ewm-notifications-flushes-without-messages-log ()
  (let ((helheim-ewm-notifications--pending
         (helheim-ewm-notifications-test--notification))
        (helheim-ewm-notifications--timer nil)
        shown)
    (cl-letf (((symbol-function 'active-minibuffer-window) (lambda () nil))
              ((symbol-function 'message)
               (lambda (_format text)
                 (should-not message-log-max)
                 (setq shown text))))
      (helheim-ewm-notifications--flush))
    (should shown)
    (should-not helheim-ewm-notifications--pending)))

(ert-deftest helheim-ewm-notifications-retains-history-and-actions ()
  (let ((ednc-log-name " *helheim-ednc-test*"))
    (unwind-protect
        (let ((notification (helheim-ewm-notifications-test--notification)))
          (ednc--update-log-buffer nil notification)
          (with-current-buffer ednc-log-name
            (should (derived-mode-p 'ednc-view-mode))
            (should (string-match-p "Hello\nworld" (buffer-string)))
            (should (eq (get-text-property (point-min) 'ednc-notification)
                        notification)))
          (should (equal (ednc-notification-actions notification) '("default" "Open"))))
      (when (get-buffer ednc-log-name) (kill-buffer ednc-log-name)))))

(ert-deftest helheim-ewm-notifications-does-not-replace-server ()
  (let ((ewm-mode t)
        (ednc-mode nil)
        (helheim-ewm-notifications--started nil)
        warned)
    (cl-letf (((symbol-function 'dbus-list-names)
               (lambda (_) '("org.freedesktop.Notifications")))
              ((symbol-function 'display-warning) (lambda (&rest _) (setq warned t)))
              ((symbol-function 'ednc-mode) (lambda (&rest _) (ert-fail "Server replaced"))))
      (helheim-ewm-notifications--sync))
    (should warned)
    (should-not helheim-ewm-notifications--started)))

(ert-deftest helheim-ewm-notifications-keeps-modeline-clean ()
  (should-not (alist-get 'ednc-mode minor-mode-alist))
  (should (memq #'ednc--update-log-buffer
                (ensure-list ednc-notification-presentation-functions))))

;;; helheim-ewm-notifications-tests.el ends here
