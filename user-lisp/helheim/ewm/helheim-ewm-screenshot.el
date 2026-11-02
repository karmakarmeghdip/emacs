;;; helheim-ewm-screenshot.el --- Screenshot capture for EWM -*- lexical-binding: t -*-

;;; Commentary:
;;
;; Screenshot support for EWM using `grim', `slurp', and `wl-copy'.
;; Supports region selection (default) and full-screen captures.
;; Captures run asynchronously via `make-process' so Emacs never blocks
;; while waiting for interactive region selection.
;; Overlays are protected from stacking: triggering a new region capture
;; terminates any existing selection first.

;;; Code:

(require 'subr-x)

(defgroup helheim-ewm-screenshot nil
  "Screenshot capture integration for EWM."
  :group 'environment)

(defcustom helheim-ewm-screenshot-directory "~/Pictures/Screenshots"
  "Directory where captured screenshots are saved."
  :type 'directory
  :group 'helheim-ewm-screenshot)

(defcustom helheim-ewm-screenshot-copy-to-clipboard t
  "Whether to copy captured screenshots to the Wayland clipboard."
  :type 'boolean
  :group 'helheim-ewm-screenshot)

(defcustom helheim-ewm-screenshot-notify t
  "Whether to send a desktop notification after taking a screenshot."
  :type 'boolean
  :group 'helheim-ewm-screenshot)

(defvar helheim-ewm-screenshot--process nil
  "Current running screenshot process, if any.")

(defun helheim-ewm-screenshot--check-executables (region)
  "Verify required screenshot binaries are available.
When REGION is non-nil, also require `slurp'."
  (unless (executable-find "grim")
    (user-error "Screenshot failed: `grim' is not installed or not in PATH"))
  (when (and region (not (executable-find "slurp")))
    (user-error "Region screenshot failed: `slurp' is not installed or not in PATH")))

(defun helheim-ewm-screenshot--build-command (&optional region)
  "Return the shell command string for capturing a screenshot.
If REGION is non-nil, use `slurp' to select a region; otherwise capture
the full screen."
  (let* ((dir (expand-file-name helheim-ewm-screenshot-directory))
         (filename-expr "screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png"))
    (concat
     (format "dir=%s; " (shell-quote-argument dir))
     "mkdir -p \"$dir\" || exit 1; "
     (format "file=\"$dir/%s\"; " filename-expr)
     (if region
         "geom=$(slurp) || exit 0; [ -n \"$geom\" ] || exit 0; grim -g \"$geom\" \"$file\" || exit 1; "
       "grim \"$file\" || exit 1; ")
     (when helheim-ewm-screenshot-copy-to-clipboard
       "wl-copy --type image/png < \"$file\"; ")
     (when helheim-ewm-screenshot-notify
       "notify-send -i \"$file\" 'Screenshot' \"Captured $file\" 2>/dev/null || true; "))))

(defun helheim-ewm-screenshot--run (&optional region)
  "Run the screenshot process asynchronously.
When REGION is non-nil, prompt for region selection with `slurp'.
Any existing selection process is terminated so overlays never stack."
  (helheim-ewm-screenshot--check-executables region)
  ;; Terminate any active screenshot process and slurp overlay to prevent stacking.
  (when (process-live-p helheim-ewm-screenshot--process)
    (delete-process helheim-ewm-screenshot--process)
    (setq helheim-ewm-screenshot--process nil))
  (when region
    (call-process "pkill" nil nil nil "-x" "slurp"))
  (let ((cmd (helheim-ewm-screenshot--build-command region)))
    (setq helheim-ewm-screenshot--process
          (make-process
           :name "helheim-ewm-screenshot"
           :buffer (get-buffer-create "*helheim-ewm-screenshot*")
           :command (list "sh" "-c" cmd)
           :noquery t
           :sentinel
           (lambda (proc event)
             (when (eq proc helheim-ewm-screenshot--process)
               (setq helheim-ewm-screenshot--process nil))
             (when (and (eq (process-status proc) 'exit)
                        (/= (process-exit-status proc) 0))
               (message "Screenshot failed (%s)" (string-trim event))))))))

;;;###autoload
(defun helheim-ewm-screenshot-cancel ()
  "Cancel any in-progress screenshot capture and close active overlay."
  (interactive)
  (when (process-live-p helheim-ewm-screenshot--process)
    (delete-process helheim-ewm-screenshot--process)
    (setq helheim-ewm-screenshot--process nil))
  (call-process "pkill" nil nil nil "-x" "slurp"))

;;;###autoload
(defun helheim-ewm-screenshot-region ()
  "Capture a screenshot of a selected screen region using `slurp' and `grim'.
Saves the image to `helheim-ewm-screenshot-directory', copies it to the
Wayland clipboard if `helheim-ewm-screenshot-copy-to-clipboard' is non-nil,
and sends a notification if `helheim-ewm-screenshot-notify' is non-nil."
  (interactive)
  (helheim-ewm-screenshot--run t))

;;;###autoload
(defun helheim-ewm-screenshot-screen ()
  "Capture a full-screen screenshot using `grim'.
Saves the image to `helheim-ewm-screenshot-directory', copies it to the
Wayland clipboard if `helheim-ewm-screenshot-copy-to-clipboard' is non-nil,
and sends a notification if `helheim-ewm-screenshot-notify' is non-nil."
  (interactive)
  (helheim-ewm-screenshot--run nil))

(provide 'helheim-ewm-screenshot)

;;; helheim-ewm-screenshot.el ends here
