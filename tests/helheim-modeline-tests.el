;;; helheim-modeline-tests.el --- Tests for Starship Doom Modeline -*- lexical-binding: t -*-

(require 'ert)
(require 'cl-lib)

(defconst helheim-modeline-test--root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))

(add-to-list 'load-path (expand-file-name "user-lisp/helheim/modeline" helheim-modeline-test--root))

(unless (featurep 'doom-modeline)
  ;; Load from Elpaca build directory during headless batch runs.
  (let ((elpaca-builds (expand-file-name "var/elpaca/builds" helheim-modeline-test--root)))
    (when (file-directory-p elpaca-builds)
      (dolist (dir (directory-files elpaca-builds t "\\`[^.]"))
        (when (file-directory-p dir)
          (add-to-list 'load-path dir))))))

(unless (fboundp 'setup)
  (defmacro setup (_name &rest _body) nil))

(defvar hel-local-mode nil)
(defvar hel-state nil)
(defvar flymake-mode nil)

(require 'doom-modeline)
(require 'helheim-modeline)
(require 'helheim-desktop-modeline)

;; Register Starship segments when `setup' was stubbed in batch mode.
(unless (alist-get 'starship-left doom-modeline--fn-alist)
  (helheim-modeline--install-starship-modelines)
  (doom-modeline-mode 1))

(ert-deftest helheim-modeline-render-pills-skips-empty-and-caps-ends ()
  (let ((rendered (helheim-modeline--render-pills
                   '((" NORMAL " red :weight bold)
                     ("" yellow)
                     (" init.el " peach :weight bold))
                   'left 'force)))
    (should (string-prefix-p "\xe0b6" rendered))
    (should (string-suffix-p "\xe0b4" rendered))
    (should (string-match-p "NORMAL" rendered))
    (should (string-match-p "init.el" rendered))
    ;; Only one internal separator since empty yellow pill was skipped.
    (should (= 1 (cl-count ?\xe0b0 rendered)))
    (let ((sep-pos (cl-position ?\xe0b0 rendered)))
      (should (equal (get-text-property sep-pos 'face rendered)
                     '(:foreground "#f38ba8" :background "#fab387"))))))

(ert-deftest helheim-modeline-render-pills-right-uses-left-chevrons ()
  (let ((rendered (helheim-modeline--render-pills
                   '((" Emacs-Lisp " green)
                     (" 100% " blue))
                   'right 'force)))
    (should (string-prefix-p "\xe0b6" rendered))
    (should (string-suffix-p "\xe0b4" rendered))
    (should (= 1 (cl-count ?\xe0b2 rendered)))
    (let ((sep-pos (cl-position ?\xe0b2 rendered)))
      (should (equal (get-text-property sep-pos 'face rendered)
                     '(:foreground "#89b4fa" :background "#a6e3a1"))))))

(ert-deftest helheim-modeline-truncate-pills-preserves-closing-cap ()
  (let* ((full (helheim-modeline--render-pills
                '((" NORMAL " red)
                  (" very/long/nested/project/filename.el " peach))
                'left 'force))
         (truncated (helheim-modeline--truncate-pills full 24 t)))
    (should (<= (string-width truncated) 24))
    (should (string-suffix-p "…\xe0b4" truncated))
    (let ((cap-pos (1- (length truncated))))
      (should (equal (get-text-property cap-pos 'face truncated)
                     '(:foreground "#fab387" :background "#181825"))))))

(ert-deftest helheim-modeline-desktop-layout-escapes-percent-and-centers-clock ()
  (let* ((display-time-mode t)
         (doom-modeline-time t)
         (display-time-string "12:34:56")
         (helheim-desktop-modeline--status " BT  WF ")
         (doom-modeline--battery-status '("BAT" . "100%%"))
         (doom-modeline-battery t)
         (display-battery-mode t))
    (cl-letf (((symbol-function 'doom-modeline--active) (lambda () t))
              ((symbol-function 'doom-modeline-face) (lambda (&rest _) 'mode-line))
              ((symbol-function 'window-body-width) (lambda (&rest _) 120))
              ((symbol-function 'format-mode-line)
               (lambda (arg &rest _)
                 (string-replace "%%" "%" (if (stringp arg) arg (car arg))))))
      (let* ((left-str (helheim-modeline--render-pills
                        '((" 100% " red) (" file%20.el " peach)) 'left 'force))
             ;; Simulate `doom-modeline-def-modeline' having already run `format-mode-line' on RHS.
             (right-str (concat
                         (propertize "\xe0b6" 'face '(:foreground "#89b4fa"))
                         (propertize " 100% " 'face '(:background "#89b4fa" :foreground "#11111b"))
                         (propertize "\xe0b4" 'face '(:foreground "#89b4fa"))))
             (layout (helheim-desktop-modeline--layout
                      (list left-str " " right-str))))
        (should (string-match-p "100%%" (nth 0 layout)))
        (should (string-match-p "file%%20\\.el" (nth 0 layout)))
        (should (string-match-p "12:34:56" (nth 2 layout)))
        (should (string-match-p "100%%" (nth 4 layout)))
        (let* ((rhs (nth 4 layout))
               (pct-pos (string-search "%" rhs)))
          (should pct-pos)
          (should (equal (plist-get (get-text-property pct-pos 'face rhs) :background)
                         "#89b4fa"))
          (should (equal (plist-get (get-text-property (1+ pct-pos) 'face rhs) :background)
                         "#89b4fa")))))
    ;; Narrow window omits centered clock and preserves closing cap on truncated left.
    (cl-letf (((symbol-function 'doom-modeline--active) (lambda () t))
              ((symbol-function 'doom-modeline-face) (lambda (&rest _) 'mode-line))
              ((symbol-function 'window-body-width) (lambda (&rest _) 28))
              ((symbol-function 'format-mode-line)
               (lambda (arg &rest _)
                 (string-replace "%%" "%" (if (stringp arg) arg (car arg))))))
      (let* ((left-str (helheim-modeline--render-pills
                        '((" NORMAL " red) (" very/long/buffer/name.el " peach)) 'left 'force))
             (right-str "  100%  ")
             (layout (helheim-desktop-modeline--layout (list left-str " " right-str))))
        (should (= (length layout) 3))
        (should (string-suffix-p "…\xe0b4" (nth 0 layout)))))))

(ert-deftest helheim-modeline-hel-states-and-diagnostics ()
  (with-temp-buffer
    (let ((hel-local-mode t)
          (hel-state 'insert)
          (flymake-mode t)
          (doom-modeline--flymake "err")
          (doom-modeline--flymake-counts '((error . 2) (warning . 1) (note . 0))))
      (cl-letf (((symbol-function 'doom-modeline--active) (lambda () t)))
        (let ((state-pill (helheim-modeline--pill-state))
              (diag-pill (helheim-modeline--pill-mode-and-checks)))
          (should (string-match-p "\xf448" (car state-pill)))
          (should (eq (cadr state-pill) 'green))
          (should (eq (cadr diag-pill) 'red))
          (should (string-match-p "2" (car diag-pill))))
        (let ((hel-state 'normal))
          (let ((normal-pill (helheim-modeline--pill-state)))
            (should (string-match-p "\xf09a8" (car normal-pill)))
            (should (eq (cadr normal-pill) 'red)))
          (cl-letf (((symbol-function 'region-active-p) (lambda () t)))
            (let ((select-pill (helheim-modeline--pill-state)))
              (should (string-match-p "\xf246" (car select-pill)))
              (should (eq (cadr select-pill) 'blue)))))))))

;;; helheim-modeline-tests.el ends here
