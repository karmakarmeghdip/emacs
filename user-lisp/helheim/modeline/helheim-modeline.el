;;; helheim-modeline              -*- lexical-binding: t; no-byte-compile: t -*-

;;; Commentary:
;;
;; Doom Modeline styled as a Starship Catppuccin Mocha Powerline pill bar,
;; matching `~/.config/starship.toml' and `user-eshell'.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar doom-modeline--modelines)
(defvar doom-modeline--limited-width-p)
(defvar doom-modeline--buffer-file-name)
(defvar doom-modeline--vcs)
(defvar doom-modeline--flymake)
(defvar doom-modeline--flymake-counts)
(defvar doom-modeline--flycheck)
(defvar doom-modeline--flycheck-counts)
(defvar doom-modeline--eglot)
(defvar doom-modeline--lsp)
(defvar doom-modeline--battery-status)
(defvar doom-modeline-buffer-file-name-style)
(defvar doom-modeline-continuous-word-count-modes)
(defvar doom-modeline-buffer-encoding)
(defvar doom-modeline-enable-word-count)
(defvar doom-modeline-lsp)
(defvar doom-modeline-battery)
(defvar hel-local-mode)
(defvar hel-state)

(defvar helheim-modeline--desktop-enabled nil
  "Non-nil when `helheim-desktop-modeline' manages clock, connectivity, and battery.")

(defvar helheim-modeline--desktop-status-var 'helheim-desktop-modeline--status
  "Symbol holding the cached desktop connectivity status string.")

;;; ---------------------------------------------------------------------------
;;; Catppuccin Mocha Palette & Powerline Pill Primitives
;;; ---------------------------------------------------------------------------

(defconst helheim-modeline--palette
  '((rosewater . "#f5e0dc")
    (flamingo  . "#f2cdcd")
    (pink      . "#f5c2e7")
    (mauve     . "#cba6f7")
    (red       . "#f38ba8")
    (maroon    . "#eba0ac")
    (peach     . "#fab387")
    (yellow    . "#f9e2af")
    (green     . "#a6e3a1")
    (teal      . "#94e2d5")
    (sky       . "#89dceb")
    (sapphire  . "#74c7ec")
    (blue      . "#89b4fa")
    (lavender  . "#b4befe")
    (text      . "#cdd6f4")
    (subtext1  . "#bac2de")
    (subtext0  . "#a6adc8")
    (overlay2  . "#9399b2")
    (overlay1  . "#7f849c")
    (overlay0  . "#6c7086")
    (surface2  . "#585b70")
    (surface1  . "#45475a")
    (surface0  . "#313244")
    (base      . "#1e1e2e")
    (mantle    . "#181825")
    (crust     . "#11111b"))
  "Catppuccin Mocha hex palette matching `~/.config/starship.toml'.")

(defconst helheim-modeline--os-symbol
  (cond
   ((eq system-type 'darwin) "\xf0035")
   ((eq system-type 'windows-nt) "\xe70f")
   ((file-readable-p "/etc/os-release")
    (with-temp-buffer
      (insert-file-contents "/etc/os-release")
      (let ((id (when (re-search-forward "^ID=\\(.+\\)$" nil t)
                  (string-trim (match-string 1) "\"" "\""))))
        (pcase id
          ("cachyos" "\xf385")
          ((or "arch" "artix") "\xf08c7")
          ("ubuntu" "\xf0548")
          ("debian" "\xf08da")
          ("fedora" "\xf08db")
          ("gentoo" "\xf08e8")
          ("linuxmint" "\xf08ed")
          ("manjaro" "\xf312")
          ("alpine" "\xf300")
          ("void" "\xf32e")
          (_ "\xf033d")))))
   (t "\xf033d"))
  "OS icon matching `[os.symbols]' in `~/.config/starship.toml'.")

(defun helheim-modeline--color (color)
  "Return hex color string for Catppuccin COLOR symbol."
  (let ((fallback (or (cdr (assq color helheim-modeline--palette)) "#cdd6f4")))
    (if (and (memq 'catppuccin custom-enabled-themes)
             (fboundp 'catppuccin-color))
        (or (ignore-errors (catppuccin-color color)) fallback)
      fallback)))

(defun helheim-modeline--bar-bg (&optional active)
  "Return mode-line background color for ACTIVE state."
  (if active
      (helheim-modeline--color 'mantle)
    (helheim-modeline--color 'crust)))

(defun helheim-modeline--escape-pct (str)
  "Escape literal `%' as `%%' in STR while preserving text properties."
  (if (not (string-search "%" str))
      str
    (let ((parts nil)
          (start 0)
          (pos nil))
      (while (setq pos (string-search "%" str start))
        (when (> pos start)
          (push (substring str start pos) parts))
        (let ((pct (substring str pos (1+ pos))))
          (push pct parts)
          (push (copy-sequence pct) parts))
        (setq start (1+ pos)))
      (when (< start (length str))
        (push (substring str start) parts))
      (apply #'concat (nreverse parts)))))

(defun helheim-modeline--style-pill (text bg fg &optional weight preserve-face)
  "Return a copy of TEXT styled for a Powerline pill with BG and FG.
Preserves interactive properties (`help-echo', `local-map', `mouse-face')
while ensuring solid BG and crisp FG across the whole pill.
When PRESERVE-FACE is non-nil, keep per-span foreground/weight faces
already applied to TEXT and only supply BG/FG as defaults."
  (let* ((str (helheim-modeline--escape-pct (copy-sequence text)))
         (len (length str)))
    (when (> len 0)
      (if preserve-face
          (add-face-text-property 0 len `(:background ,bg :foreground ,fg) t str)
        (remove-text-properties 0 len '(face nil font-lock-face nil) str)
        (add-face-text-property
         0 len
         `(,@(when weight `(:weight ,weight))
           :background ,bg
           :foreground ,fg)
         nil str))
      (put-text-property 0 len 'helheim-modeline-pill (cons bg fg) str))
    str))

(defun helheim-modeline--resolve-color (spec)
  "Resolve SPEC (a Catppuccin color symbol or hex string) to a hex color, or nil."
  (when spec
    (if (symbolp spec)
        (helheim-modeline--color spec)
      spec)))

(defun helheim-modeline--render-pills (pills &optional direction active)
  "Render PILLS as a rounded Catppuccin Powerline pill chain.
PILLS is a list of specs: (TEXT ACTIVE-BG &key INACTIVE-BG FG INACTIVE-FG WEIGHT).
Empty or nil TEXT entries are omitted cleanly with no empty chevrons.
DIRECTION is `left' (using U+E0B0) or `right' (using U+E0B2).
ACTIVE defaults to `(doom-modeline--active)'."
  (let* ((is-active (if (eq active 'force) t
                      (or active (doom-modeline--active))))
         (bar-bg (helheim-modeline--bar-bg is-active))
         (default-fg (helheim-modeline--color 'crust))
         (inactive-fg-default (helheim-modeline--color 'subtext0))
         (dir (or direction 'left))
         (sep-char (if (eq dir 'right) "\xe0b2" "\xe0b0"))
         (idx 0)
         (visible nil))
    (dolist (pill pills)
      (let* ((text (car pill))
             (active-bg (cadr pill))
             (props (cddr pill)))
        (when (and (stringp text) (not (string-empty-p text)))
          (let* ((inactive-bg (or (plist-get props :inactive-bg)
                                  (if (cl-evenp idx) 'surface1 'surface0)))
                 (bg (helheim-modeline--resolve-color
                      (if is-active active-bg inactive-bg)))
                 (fg (if is-active
                         (or (helheim-modeline--resolve-color (plist-get props :fg))
                             default-fg)
                       (or (helheim-modeline--resolve-color (plist-get props :inactive-fg))
                           inactive-fg-default)))
                 (weight (plist-get props :weight))
                 (preserve (plist-get props :preserve-face)))
            (push (list (helheim-modeline--style-pill text bg fg weight preserve) bg fg)
                  visible)
            (cl-incf idx)))))
    (setq visible (nreverse visible))
    (if (null visible)
        ""
      (let* ((first-bg (nth 1 (car visible)))
             (last-bg (nth 1 (car (last visible))))
             (parts (list (propertize "\xe0b6" 'face `(:foreground ,first-bg :background ,bar-bg)))))
        (cl-loop for (styled bg fg) in visible
                 for rest on visible
                 do (push styled parts)
                 when (cdr rest)
                 do (let* ((next (cadr rest))
                           (next-bg (nth 1 next))
                           (next-fg (nth 2 next))
                           (sep-face (if (eq dir 'right)
                                         `(:foreground ,next-bg :background ,bg)
                                       `(:foreground ,bg :background ,next-bg)))
                           (pill-tag (if (eq dir 'right)
                                         (cons next-bg next-fg)
                                       (cons bg fg))))
                      (push (propertize sep-char
                                        'face sep-face
                                        'helheim-modeline-pill pill-tag)
                            parts)))
        (push (propertize "\xe0b4" 'face `(:foreground ,last-bg :background ,bar-bg)) parts)
        (apply #'concat (nreverse parts))))))

(defun helheim-modeline--truncate-pills (str max-width &optional active)
  "Truncate pill chain STR to MAX-WIDTH columns while keeping a closing `' cap."
  (cond
   ((or (null str) (string-empty-p str) (<= max-width 0)) "")
   ((<= (string-width str) max-width) str)
   ((<= max-width 2) (truncate-string-to-width str max-width))
   (t
    (let* ((is-active (or active (doom-modeline--active)))
           (bar-bg (helheim-modeline--bar-bg is-active))
           (body (truncate-string-to-width str (- max-width 2)))
           (len (length body))
           (pill (and (> len 0)
                      (get-text-property (1- len) 'helheim-modeline-pill body)))
           (bg (or (car-safe pill)
                   (helheim-modeline--color 'surface0)))
           (fg (or (cdr-safe pill)
                   (helheim-modeline--color (if is-active 'crust 'subtext0)))))
      (concat body
              (propertize "…" 'face `(:background ,bg :foreground ,fg))
              (propertize "\xe0b4" 'face `(:foreground ,bg :background ,bar-bg)))))))

;;; ---------------------------------------------------------------------------
;;; Starship Pill Segment Builders
;;; ---------------------------------------------------------------------------

(defun helheim-modeline--pill-state ()
  "Build the opening state/OS pill spec for editing buffers."
  (let* ((macro-p (or defining-kbd-macro executing-kbd-macro))
         (hel-p (and (bound-and-true-p hel-local-mode)
                     (bound-and-true-p hel-state)))
         (state-info
          (cond
           (macro-p (list "󰑋 REC" 'red "Recording keyboard macro"))
           (hel-p
            (pcase hel-state
              ('normal
               (if (region-active-p)
                   (list "\xf246" 'blue "Hel: Select")
                 (list "\xf09a8" 'red "Hel: Normal")))
              ('insert (list "\xf448" 'green "Hel: Insert"))
              ('emacs  (list "EMACS" 'mauve "Hel: Emacs"))
              (_       (list (upcase (symbol-name hel-state)) 'yellow
                             (format "Hel: %s" hel-state)))))
           ((derived-mode-p 'magit-mode 'vc-dir-mode)
            (list "\xf418 VCS" 'red "Version Control"))
           (t (list helheim-modeline--os-symbol 'red "System"))))
         (matches (when (fboundp 'doom-modeline-segment--matches)
                    (string-trim (or (format-mode-line (doom-modeline-segment--matches)) ""))))
         (dedicated (when (window-dedicated-p) "󰐃"))
         (parts (delq nil (list (nth 0 state-info)
                                (unless (string-empty-p (or matches "")) matches)
                                dedicated)))
         (label (propertize (format " %s " (string-join parts " "))
                            'help-echo (nth 2 state-info))))
    (list label
          (nth 1 state-info)
          :inactive-bg 'surface1
          :weight 'bold)))

(defun helheim-modeline--buffer-label ()
  "Return clean buffer/file name string with Doom Modeline keymap and help-echo."
  (cond
   ((and buffer-file-name (not doom-modeline--limited-width-p))
    (or doom-modeline--buffer-file-name
        (when (fboundp 'doom-modeline-update-buffer-file-name)
          (doom-modeline-update-buffer-file-name))
        (buffer-name)))
   ((derived-mode-p 'dashboard-mode 'dired-mode)
    (let ((dir (if (fboundp 'doom-modeline--default-directory-info)
                   (cdr (doom-modeline--default-directory-info))
                 (abbreviate-file-name default-directory))))
      (propertize dir
                  'help-echo default-directory
                  'mouse-face 'doom-modeline-highlight
                  'local-map mode-line-buffer-identification-keymap)))
   (t
    (propertize (buffer-name)
                'help-echo "Buffer name\nmouse-1: Previous buffer\nmouse-3: Next buffer"
                'mouse-face 'doom-modeline-highlight
                'local-map mode-line-buffer-identification-keymap))))

(defun helheim-modeline--pill-buffer ()
  "Build the peach buffer/file pill spec matching Starship's `$directory'."
  (let* ((is-active (doom-modeline--active))
         (fg-main (helheim-modeline--color (if is-active 'crust 'subtext0)))
         (fg-dir (helheim-modeline--color (if is-active 'surface0 'overlay0)))
         (bg (helheim-modeline--color (if is-active 'peach 'surface0)))
         (remote-host (and (stringp default-directory)
                           (file-remote-p default-directory 'host)))
         (ro-p buffer-read-only)
         (mod-p (and buffer-file-name (buffer-modified-p)))
         (narrow-p (buffer-narrowed-p))
         (prefix (concat
                  (when remote-host (format "󰌘 %s " remote-host))
                  (when ro-p "\xf023 ")
                  (when mod-p "● ")
                  (when narrow-p "↕ ")))
         (raw-label (or (helheim-modeline--buffer-label) (buffer-name)))
         (label (copy-sequence raw-label))
         (len (length label))
         (slash-pos (when (and buffer-file-name (> len 0))
                      (cl-position ?/ label :from-end t))))
    (when (> len 0)
      (remove-text-properties 0 len '(face nil font-lock-face nil) label)
      (if slash-pos
          (progn
            (add-face-text-property 0 (1+ slash-pos) `(:background ,bg :foreground ,fg-dir) nil label)
            (add-face-text-property (1+ slash-pos) len `(:background ,bg :foreground ,fg-main :weight bold) nil label))
        (add-face-text-property 0 len `(:background ,bg :foreground ,fg-main :weight bold) nil label)))
    (let* ((prefix-str (if (string-empty-p prefix) ""
                         (propertize prefix 'face `(:background ,bg :foreground ,fg-main :weight bold))))
           (extra (cond
                   ((derived-mode-p 'pdf-view-mode 'reader-mode)
                    (let ((pages (string-trim (or (format-mode-line (doom-modeline-segment--pdf-pages)) ""))))
                      (unless (string-empty-p pages) (concat " " pages))))
                   ((derived-mode-p 'Info-mode)
                    (let ((node (string-trim (or (format-mode-line (doom-modeline-segment--info-nodes)) ""))))
                      (unless (string-empty-p node) (concat " " node))))
                   (t nil)))
           (extra-str (if extra
                          (propertize extra 'face `(:background ,bg :foreground ,fg-dir))
                        ""))
           (pad (propertize " " 'face `(:background ,bg :foreground ,fg-main)))
           (content (concat pad prefix-str label extra-str pad)))
      (list content 'peach :inactive-bg 'surface0 :fg fg-main :inactive-fg fg-main
            :preserve-face t))))

(defun helheim-modeline--vcs-status-marker ()
  "Return a compact status marker from cached `doom-modeline--vcs' without I/O."
  (when doom-modeline--vcs
    (let* ((icon (alist-get 'icon doom-modeline--vcs))
           (text (alist-get 'text doom-modeline--vcs))
           (icon-face (and (stringp icon) (get-text-property 0 'face icon)))
           (text-face (and (stringp text) (get-text-property 0 'face text)))
           (icon-raw (and (stringp icon) (substring-no-properties icon))))
      (cond
       ((memq 'doom-modeline-urgent (ensure-list text-face)) " !")
       ((memq 'doom-modeline-warning (ensure-list text-face)) " ⬇")
       ((memq 'doom-modeline-urgent (ensure-list icon-face)) " !")
       ((memq 'doom-modeline-warning (ensure-list icon-face)) " ⬇")
       ;; `nf-dev-git_compare' / `nf-dev-git_merge' indicate edited/added/merge
       ((and icon-raw (member icon-raw '("" "🔃" "🔀"))) " *")
       (t "")))))

(defun helheim-modeline--pill-vcs ()
  "Build the yellow Git branch/status pill spec matching Starship's `[git_branch]'."
  (when (and (doom-modeline--active)
             (or doom-modeline--vcs vc-mode))
    (let* ((vcs-text (alist-get 'text doom-modeline--vcs))
           (raw-branch (cond
                        ((and (stringp vcs-text) (not (string-empty-p vcs-text)))
                         vcs-text)
                        ((stringp vc-mode)
                         (replace-regexp-in-string "^ ?Git[:-]" "" (string-trim vc-mode)))))
           (marker (or (helheim-modeline--vcs-status-marker) "")))
      (when (and raw-branch (not (string-empty-p raw-branch)))
        (let* ((branch (copy-sequence raw-branch))
               (help (or (get-text-property 0 'help-echo raw-branch)
                         (and (stringp vc-mode) (get-text-property 1 'help-echo vc-mode))))
               (map (or (get-text-property 0 'local-map raw-branch)
                        (and (stringp vc-mode) (get-text-property 1 'local-map vc-mode))))
               (content (concat " \xf418 " (substring-no-properties branch) marker " ")))
          (when help (put-text-property 0 (length content) 'help-echo help content))
          (when map (put-text-property 0 (length content) 'local-map map content))
          (put-text-property 0 (length content) 'mouse-face 'doom-modeline-highlight content)
          (list content 'yellow :weight 'bold))))))

(defun helheim-modeline--pill-selection ()
  "Build optional teal selection/word-count pill spec."
  (when (and (doom-modeline--active)
             (not doom-modeline--limited-width-p))
    (let* ((sel (when (region-active-p)
                  (string-trim (or (format-mode-line (doom-modeline-segment--selection-info)) ""))))
           (wc (when (and doom-modeline-enable-word-count
                          (memq major-mode doom-modeline-continuous-word-count-modes))
                 (string-trim (or (format-mode-line (doom-modeline-segment--word-count)) ""))))
           (text (cond ((and sel (not (string-empty-p sel))) sel)
                       ((and wc (not (string-empty-p wc))) wc))))
      (when text
        (list (format " %s " text) 'teal :weight 'bold)))))

(defun helheim-modeline--diagnostics-info ()
  "Return (TEXT BG HELP-ECHO LOCAL-MAP) for Flymake/Flycheck diagnostics, or nil."
  (cond
   ((and (bound-and-true-p flymake-mode) doom-modeline--flymake)
    (let* ((err (or (alist-get 'error doom-modeline--flymake-counts) 0))
           (warn (or (alist-get 'warning doom-modeline--flymake-counts) 0))
           (bg (cond ((> err 0) 'red)
                     ((> warn 0) 'yellow)
                     (t 'green)))
           (summary (string-join
                     (delq nil
                           (list (when (> err 0) (format "\xf057 %d" err))
                                 (when (> warn 0) (format "\xf071 %d" warn))
                                 (when (and (zerop err) (zerop warn)) "\xf00c")))
                     " ")))
      (list summary bg
            (get-text-property 0 'help-echo doom-modeline--flymake)
            (get-text-property 0 'local-map doom-modeline--flymake))))
   ((and (bound-and-true-p flycheck-mode) doom-modeline--flycheck)
    (let* ((err (or (alist-get 'error doom-modeline--flycheck-counts) 0))
           (warn (or (alist-get 'warning doom-modeline--flycheck-counts) 0))
           (bg (cond ((> err 0) 'red)
                     ((> warn 0) 'yellow)
                     (t 'green)))
           (summary (string-join
                     (delq nil
                           (list (when (> err 0) (format "\xf057 %d" err))
                                 (when (> warn 0) (format "\xf071 %d" warn))
                                 (when (and (zerop err) (zerop warn)) "\xf00c")))
                     " ")))
      (list summary bg
            (get-text-property 0 'help-echo doom-modeline--flycheck)
            (get-text-property 0 'local-map doom-modeline--flycheck))))))

(defun helheim-modeline--lsp-info ()
  "Return propertized LSP indicator string if Eglot or lsp-mode is active."
  (when doom-modeline-lsp
    (cond
     ((bound-and-true-p eglot--managed-mode)
      (let* ((cached (and (boundp 'doom-modeline--eglot) doom-modeline--eglot))
             (sample (or (plist-get cached 'doom-modeline-lsp-success)
                         (plist-get cached 'doom-modeline-lsp-warning)))
             (str (copy-sequence "\xf013")))
        (when (stringp sample)
          (when-let* ((h (get-text-property 0 'help-echo sample)))
            (put-text-property 0 (length str) 'help-echo h str))
          (when-let* ((m (get-text-property 0 'local-map sample)))
            (put-text-property 0 (length str) 'local-map m str)))
        (put-text-property 0 (length str) 'mouse-face 'doom-modeline-highlight str)
        str))
     ((bound-and-true-p lsp-mode)
      (let ((str (copy-sequence "\xf013")))
        (when (stringp doom-modeline--lsp)
          (when-let* ((h (get-text-property 0 'help-echo doom-modeline--lsp)))
            (put-text-property 0 (length str) 'help-echo h str))
          (when-let* ((m (get-text-property 0 'local-map doom-modeline--lsp)))
            (put-text-property 0 (length str) 'local-map m str)))
        (put-text-property 0 (length str) 'mouse-face 'doom-modeline-highlight str)
        str)))))

(defun helheim-modeline--pill-mode-and-checks ()
  "Build the green/diagnostic language, LSP, check, and process pill spec."
  (when (doom-modeline--active)
    (let* ((limited doom-modeline--limited-width-p)
           (diag (helheim-modeline--diagnostics-info))
           (lsp-str (helheim-modeline--lsp-info))
           (proc (string-trim (or (format-mode-line mode-line-process) "")))
           (comp (when (bound-and-true-p compilation-in-progress) "Compiling"))
           (enc (when (and (eq doom-modeline-buffer-encoding t)
                           (fboundp 'doom-modeline-segment--buffer-encoding))
                  (string-trim (or (format-mode-line (doom-modeline-segment--buffer-encoding)) ""))))
           (mode-str (unless limited
                       (let ((name (string-trim (substring-no-properties (format-mode-line mode-name)))))
                         (unless (string-empty-p name)
                           (propertize name
                                       'help-echo "Major mode\nmouse-1: Display major mode menu\nmouse-2: Show help for major mode\nmouse-3: Toggle minor modes"
                                       'mouse-face 'doom-modeline-highlight
                                       'local-map mode-line-major-mode-keymap)))))
           (diag-str (when diag
                       (let ((s (copy-sequence (nth 0 diag))))
                         (when (nth 2 diag) (put-text-property 0 (length s) 'help-echo (nth 2 diag) s))
                         (when (nth 3 diag) (put-text-property 0 (length s) 'local-map (nth 3 diag) s))
                         (put-text-property 0 (length s) 'mouse-face 'doom-modeline-highlight s)
                         s)))
           (bg (or (nth 1 diag) 'green))
           (parts (delq nil
                        (list mode-str
                              lsp-str
                              diag-str
                              (unless (string-empty-p (or proc "")) proc)
                              comp
                              (unless (string-empty-p (or enc "")) enc)))))
      (when parts
        (let ((joined (car parts)))
          (dolist (p (cdr parts))
            (setq joined (concat joined " " p)))
          (list (concat " " joined " ") bg :weight 'bold))))))

(defun helheim-modeline--pill-desktop-status ()
  "Build the sapphire desktop connectivity pill spec when available."
  (when (and helheim-modeline--desktop-enabled
             (boundp helheim-modeline--desktop-status-var))
    (let ((status (symbol-value helheim-modeline--desktop-status-var)))
      (when (and (stringp status) (not (string-empty-p (string-trim status))))
        (list status 'sapphire :inactive-bg 'surface1)))))

(defun helheim-modeline--pill-battery ()
  "Build the battery pill spec when `display-battery-mode' is enabled."
  (when (and doom-modeline-battery
             (bound-and-true-p display-battery-mode)
             (bound-and-true-p doom-modeline--battery-status))
    (let* ((icon (car doom-modeline--battery-status))
           (raw-text (cdr doom-modeline--battery-status))
           (pct (and (stringp raw-text)
                     (string-match "\\([0-9]+\\)" raw-text)
                     (string-to-number (match-string 1 raw-text))))
           (face (and (stringp raw-text) (get-text-property 0 'face raw-text)))
           (bg (cond
                ((eq face 'doom-modeline-battery-critical) 'red)
                ((eq face 'doom-modeline-battery-error) 'red)
                ((eq face 'doom-modeline-battery-warning) 'yellow)
                ((and pct (< pct 20) (not (eq face 'doom-modeline-battery-charging))) 'yellow)
                (t 'blue)))
           (clean-text (if (stringp raw-text)
                           (string-replace "%%" "%" (substring-no-properties raw-text))
                         ""))
           (help (or (and (stringp raw-text) (get-text-property 0 'help-echo raw-text))
                     (and (stringp icon) (get-text-property 0 'help-echo icon))))
           (icon-str (if (stringp icon) (copy-sequence icon) ""))
           (content (concat " " icon-str
                            (unless (string-empty-p clean-text) (concat " " clean-text))
                            " ")))
      (when help
        (put-text-property 0 (length content) 'help-echo help content))
      (list content bg :inactive-bg 'surface0 :weight 'bold))))

(defun helheim-modeline--pill-time ()
  "Render the centered/standalone lavender clock pill matching Starship's `[time]'."
  (when (and (bound-and-true-p doom-modeline-time)
             (bound-and-true-p display-time-mode)
             (stringp display-time-string)
             (not (string-empty-p (string-trim display-time-string))))
    (let* ((time-str (string-trim (substring-no-properties display-time-string)))
           (text (propertize (format " \xf43a %s " time-str)
                             'help-echo (format-time-string "%a %b %d, %Y"))))
      (helheim-modeline--render-pills
       (list (list text 'lavender :inactive-bg 'surface0 :weight 'bold))
       'left))))

;;; ---------------------------------------------------------------------------
;;; Doom Modeline Setup & Segment Registration
;;; ---------------------------------------------------------------------------

(defun helheim-modeline--install-starship-modelines ()
  "Install Starship pill segments across all Doom Modeline layouts."
  (doom-modeline-def-segment starship-left
    "Starship Catppuccin Mocha Powerline left pill chain."
    (helheim-modeline--render-pills
     (list (helheim-modeline--pill-state)
           (helheim-modeline--pill-buffer)
           (helheim-modeline--pill-vcs)
           (helheim-modeline--pill-selection))
     'left))

  (doom-modeline-def-segment starship-right
    "Starship Catppuccin Mocha Powerline right pill chain."
    (helheim-modeline--render-pills
     (list (helheim-modeline--pill-mode-and-checks)
           (helheim-modeline--pill-desktop-status)
           (helheim-modeline--pill-battery)
           (unless helheim-modeline--desktop-enabled
             (when (and (bound-and-true-p doom-modeline-time)
                        (bound-and-true-p display-time-mode)
                        (stringp display-time-string)
                        (not (string-empty-p (string-trim display-time-string))))
               (list (format " \xf43a %s " (string-trim (substring-no-properties display-time-string)))
                     'lavender :inactive-bg 'surface0 :weight 'bold))))
     'right))

  (doom-modeline-def-segment starship-time
    "Starship lavender clock pill."
    (helheim-modeline--pill-time))

  (dolist (definition (copy-sequence doom-modeline--modelines))
    (let ((name (car definition)))
      (unless (eq name 'desktop)
        (doom-modeline-def-modeline name '(starship-left) '(starship-right))))))

(defun helheim-modeline--apply-faces (&rest _)
  "Ensure mode-line faces are flat and match Catppuccin Mocha Powerline pills."
  (let ((active-bg (helheim-modeline--bar-bg t))
        (inactive-bg (helheim-modeline--bar-bg nil))
        (text-fg (helheim-modeline--color 'text))
        (muted-fg (helheim-modeline--color 'overlay0))
        (hl-bg (helheim-modeline--color 'surface1)))
    (set-face-attribute 'mode-line nil
                        :background active-bg :foreground text-fg :box nil)
    (when (facep 'mode-line-active)
      (set-face-attribute 'mode-line-active nil
                          :background active-bg :foreground text-fg :box nil))
    (set-face-attribute 'mode-line-inactive nil
                        :background inactive-bg :foreground muted-fg :box nil)
    (when (facep 'doom-modeline-highlight)
      (set-face-attribute 'doom-modeline-highlight nil
                          :background hl-bg :foreground text-fg))))

(setup doom-modeline
  (:install t)
  ;; Variables should be set before package is loaded.
  (:setopt doom-modeline-buffer-file-name-style 'relative-from-project
           doom-modeline-major-mode-icon nil
           doom-modeline-position-column-line-format '("%c:%l")
           doom-modeline-total-line-number nil
           doom-modeline-project-name nil
           doom-modeline-minor-modes nil
           doom-modeline-buffer-encoding 'nondefault
           doom-modeline-check-icon t
           doom-modeline-check 'auto
           doom-modeline-enable-word-count t
           doom-modeline-continuous-word-count-modes '(markdown-mode gfm-mode)
           doom-modeline-github nil
           doom-modeline-gnus t
           doom-modeline-gnus-timer 15
           doom-modeline-gnus-excluded-groups nil)
  (:require t)
  (doom-modeline-remove-segment 'workspace-name 'all)
  (helheim-modeline--install-starship-modelines)
  (helheim-modeline--apply-faces)
  (doom-modeline-mode 1))

(with-eval-after-load 'catppuccin-theme
  (helheim-modeline--apply-faces))
(add-hook 'enable-theme-functions #'helheim-modeline--apply-faces)

(when-let* ((font (face-font 'fixed-pitch)))
  (set-face-font 'mode-line            font)
  (set-face-font 'mode-line-active     font)
  (set-face-font 'mode-line-inactive   font)
  (set-face-font 'header-line          font)
  (when (<= 31 emacs-major-version)
    (set-face-font 'header-line-inactive font)))

;;; .
(provide 'helheim-modeline)
;;; helheim-modeline.el ends here
