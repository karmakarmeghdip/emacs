;;; user-eshell.el                 -*- lexical-binding: t; no-byte-compile: t -*-

;;; Commentary:
;;
;; Personal Eshell configuration:
;; - Catppuccin Mocha Powerline prompt matching ~/.config/starship.toml
;; - Ghostel-style dynamic buffer titles (*eshell: <dir>* / command / OSC title)
;; - Eat integration for running interactive TUI applications (vim, htop, btop, etc.)
;; - Native file icons for `eshell/ls' via `nerd-icons' (no external binaries like eza)
;; - Quick session spawning via `eshell-new'
;;
;;; Code:

(require 'esh-mode)
(require 'em-prompt)
(require 'em-term)
(require 'em-ls)
(require 'rx)

;;;###autoload
(defun eshell-new (&optional arg)
  "Open a new Eshell buffer, or switch to one with ARG."
  (interactive "P")
  (eshell (or arg t)))

(defun eshell/clear ()
  "Clear the Eshell buffer without duplicating the prompt."
  (interactive)
  (let ((inhibit-read-only t))
    (erase-buffer))
  (when (called-interactively-p 'interactive)
    (eshell-emit-prompt)))

;;; ---------------------------------------------------------------------------
;;; Catppuccin Colors
;;; ---------------------------------------------------------------------------

(defun user-eshell--color (color fallback)
  "Return hex string for COLOR from Catppuccin theme or use FALLBACK."
  (cond
   ((and (featurep 'catppuccin-theme) (fboundp 'catppuccin-color))
    (catppuccin-color color))
   (t fallback)))

;;; ---------------------------------------------------------------------------
;;; Starship Catppuccin Mocha Powerline Prompt (matching ~/.config/starship.toml)
;;; ---------------------------------------------------------------------------

(defconst user-eshell--dir-substitutions
  '(("Documents" . "󰈙 ")
    ("Downloads" . " ")
    ("Music"     . "󰝚 ")
    ("Pictures"  . " ")
    ("Developer" . "󰲋 "))
  "Directory component substitutions matching Starship config.")

(defconst user-eshell--os-symbol
  (cond
   ((eq system-type 'darwin) "󰀵 ")
   ((eq system-type 'windows-nt) " ")
   ((file-readable-p "/etc/os-release")
    (with-temp-buffer
      (insert-file-contents "/etc/os-release")
      (let ((id (when (re-search-forward "^ID=\\(.+\\)$" nil t)
                  (string-trim (match-string 1) "\"" "\""))))
        (pcase id
          ("cachyos" "\xf385 ")
          ((or "arch" "artix") "󰣇 ")
          ("ubuntu" "󰕈 ")
          ("debian" "󰣚 ")
          ("fedora" "󰣛 ")
          ("gentoo" "󰣨 ")
          ("linuxmint" "󰣭 ")
          ("manjaro" " ")
          ("alpine" " ")
          ("void" " ")
          (_ "󰌽 ")))))
   (t "󰌽 "))
  "OS icon matching `[os.symbols]' in Starship config.")

(defun user-eshell--segment (text bg &optional fg)
  "Propertize TEXT with background BG and foreground FG."
  (propertize text 'face `(:background ,bg :foreground ,(or fg (user-eshell--color 'crust "#11111b")))))

(defun user-eshell--powerline-sep (from-bg to-bg)
  "Return Powerline separator transitioning from FROM-BG to TO-BG."
  (if to-bg
      (propertize "\xe0b0" 'face `(:foreground ,from-bg :background ,to-bg))
    (propertize "\xe0b4" 'face `(:foreground ,from-bg))))

(defun user-eshell--root-p ()
  "Return non-nil if current session is running as root locally or remotely."
  (if-let* ((remote-user (file-remote-p default-directory 'user)))
      (string= remote-user "root")
    (= (user-uid) 0)))

(defun user-eshell--user-segment ()
  "Return OS + username (or user@host on TRAMP remotes) matching Starship's red pill."
  (if-let* ((remote (file-remote-p default-directory)))
      (let* ((vec (tramp-dissect-file-name remote))
             (user (or (tramp-file-name-user vec)
                       (file-remote-p default-directory 'user)
                       (user-login-name)))
             (host (tramp-file-name-host vec)))
        (if (and (stringp host) (not (string-empty-p host)))
            (format "󰌽 %s@%s" user host)
          (format "󰌽 %s" user)))
    (concat user-eshell--os-symbol (user-login-name))))

(defun user-eshell--substitute-dir-parts (path)
  "Apply `user-eshell--dir-substitutions' to directory components of PATH."
  (mapconcat (lambda (part)
               (or (cdr (assoc part user-eshell--dir-substitutions))
                   part))
             (split-string path "/")
             "/"))

(defun user-eshell--prompt-dir ()
  "Return formatted directory matching Starship truncation and substitutions."
  (let* ((pwd (if (fboundp 'eshell/pwd) (eshell/pwd) default-directory))
         (remote (file-remote-p pwd))
         (abbrev (if remote
                     (file-local-name pwd)
                   (abbreviate-file-name pwd)))
         (clean (directory-file-name abbrev))
         (repo-root (unless remote
                      (locate-dominating-file pwd ".git")))
         (formatted
          (cond
           (repo-root
            (let* ((root-clean (directory-file-name (abbreviate-file-name repo-root)))
                   (root-name (file-name-nondirectory root-clean))
                   (rel (file-relative-name clean root-clean))
                   (combined (if (string= rel ".")
                                 root-name
                               (concat root-name "/" rel)))
                   (parts (split-string combined "/" t))
                   (trimmed (if (> (length parts) 3)
                                (last parts 3)
                              parts)))
              (concat "…/" (user-eshell--substitute-dir-parts
                            (string-join trimmed "/")))))
           ((string= clean "~") "~")
           ((string= clean "") "/")
           (t
            (let* ((sub (user-eshell--substitute-dir-parts clean))
                   (parts (split-string sub "/" t)))
              (if (> (length parts) 3)
                  (concat "…/" (string-join (last parts 3) "/"))
                sub))))))
    (format " %s " (string-trim-right formatted))))

(defun user-eshell--git-info ()
  "Return Starship-like git branch and status string, or empty string."
  (if (file-remote-p default-directory)
      ""
    (if-let* ((_ (locate-dominating-file default-directory ".git")))
        (with-temp-buffer
          (if (not (zerop (call-process "git" nil t nil "status" "--porcelain=v1" "-b")))
              ""
            (goto-char (point-min))
            (let ((header (buffer-substring-no-properties
                           (line-beginning-position) (line-end-position)))
                  branch ahead behind staged modified untracked deleted conflicted)
              (cond
               ((string-match "^## \\(.+?\\)\\.\\.\\.[^ \n]+\\(?: \\[\\(.*\\)\\]\\)?$" header)
                (setq branch (match-string 1 header))
                (when-let* ((track (match-string 2 header)))
                  (when (string-match "ahead \\([0-9]+\\)" track)
                    (setq ahead (match-string 1 track)))
                  (when (string-match "behind \\([0-9]+\\)" track)
                    (setq behind (match-string 1 track)))))
               ((string-match "^## No commits yet on \\(.+\\)$" header)
                (setq branch (match-string 1 header)))
               ((string-match "^## HEAD (no branch)$" header)
                (with-temp-buffer
                  (when (zerop (call-process "git" nil t nil "rev-parse" "--short" "HEAD"))
                    (setq branch (string-trim (buffer-string))))))
               ((string-match "^## \\(.+\\)$" header)
                (setq branch (match-string 1 header))))
              (forward-line 1)
              (while (not (eobp))
                (let ((x (char-after (point)))
                      (y (char-after (1+ (point)))))
                  (cond
                   ((and (eq x ??) (eq y ??)) (setq untracked t))
                   ((or (eq x ?U) (eq y ?U)
                        (and (eq x ?A) (eq y ?A))
                        (and (eq x ?D) (eq y ?D)))
                    (setq conflicted t))
                   (t
                    (when (memq x '(?M ?A ?R ?C)) (setq staged t))
                    (when (eq x ?D) (setq deleted t))
                    (when (eq y ?M) (setq modified t))
                    (when (eq y ?D) (setq deleted t)))))
                (forward-line 1))
              (let ((status (concat
                             (when conflicted "=")
                             (when staged "+")
                             (when modified "!")
                             (when deleted "✘")
                             (when untracked "?")
                             (when ahead (concat "⇡" ahead))
                             (when behind (concat "⇣" behind)))))
                (if branch
                    (concat " \xf418 " branch " "
                            (if (string-empty-p status) "" (concat status " ")))
                  "")))))
      "")))

(defun user-eshell--venv-info ()
  "Return formatted Python virtualenv info if active, else empty string."
  (if-let* ((venv (getenv "VIRTUAL_ENV")))
      (format " \xe606 (#%s) " (file-name-nondirectory (directory-file-name venv)))
    ""))

(defun user-eshell--env-info ()
  "Return formatted Conda/Docker info for sapphire pill, else empty string."
  (cond
   ((getenv "CONDA_DEFAULT_ENV")
    (format "  %s " (getenv "CONDA_DEFAULT_ENV")))
   ((and (getenv "DOCKER_CONTEXT") (not (string-empty-p (getenv "DOCKER_CONTEXT"))))
    (format " \xf308 %s " (getenv "DOCKER_CONTEXT")))
   (t "")))

(defun user-eshell-prompt ()
  "Return Starship Catppuccin Mocha Powerline prompt matching `~/.config/starship.toml'."
  (condition-case nil
      (let ((c-user (user-eshell--color 'red "#f38ba8"))
            (c-dir  (user-eshell--color 'peach "#fab387"))
            (c-git  (user-eshell--color 'yellow "#f9e2af"))
            (c-lang (user-eshell--color 'green "#a6e3a1"))
            (c-env  (user-eshell--color 'sapphire "#74c7ec"))
            (c-time (user-eshell--color 'lavender "#b4befe")))
        (concat
         (propertize "\xe0b6" 'face `(:foreground ,c-user))
         (user-eshell--segment (user-eshell--user-segment) c-user)
         (user-eshell--powerline-sep c-user c-dir)
         (user-eshell--segment (user-eshell--prompt-dir) c-dir)
         (user-eshell--powerline-sep c-dir c-git)
         (user-eshell--segment (user-eshell--git-info) c-git)
         (user-eshell--powerline-sep c-git c-lang)
         (user-eshell--segment (user-eshell--venv-info) c-lang)
         (user-eshell--powerline-sep c-lang c-env)
         (user-eshell--segment (user-eshell--env-info) c-env)
         (user-eshell--powerline-sep c-env c-time)
         (user-eshell--segment (format " \xf43a %s " (format-time-string "%H:%M")) c-time)
         (user-eshell--powerline-sep c-time nil)
         "\n"
         (let ((char (if (user-eshell--root-p) "# " "λ "))
               (success (eshell-exit-success-p)))
           (propertize char 'face
                       `(:foreground ,(if success
                                          (user-eshell--color 'green "#a6e3a1")
                                        (user-eshell--color 'red "#f38ba8"))
                         :weight bold)))))
    (error
     ;; Fallback prompt if any remote or tramp inspection fails
     (concat (if (file-remote-p default-directory)
                 (file-local-name (abbreviate-file-name default-directory))
               (abbreviate-file-name default-directory))
             "\nλ "))))

;; Disable eshell-highlight-prompt so custom faces are preserved
(setq eshell-highlight-prompt nil)
(setq eshell-prompt-regexp "^[λ❯#$] ")
(setq eshell-prompt-function #'user-eshell-prompt)

;;; ---------------------------------------------------------------------------
;;; Native File Icons for `eshell/ls' via `nerd-icons' (SSH & TRAMP friendly)
;;; ---------------------------------------------------------------------------

(defun user-eshell--add-icon-to-decorated-name (orig-fun file)
  "Add a nerd-icon prefix to FILE decorated by ORIG-FUN in `eshell/ls'."
  (let ((result (funcall orig-fun file)))
    (if (or (not (stringp result))
            (not (fboundp 'nerd-icons-icon-for-file))
            (get-text-property 0 'user-eshell-icon-p result))
        result
      (let* ((filename (car file))
             (attrs (cdr file))
             (is-dir (eq (file-attribute-type attrs) t))
             (is-symlink (stringp (file-attribute-type attrs)))
             (base (and (stringp filename)
                        (file-name-nondirectory (substring-no-properties filename))))
             (name (if (or (null base) (string-empty-p base)) (or filename "") base))
             (icon (cond
                    ((or is-dir (string-match-p (rx bos (or "." "..") eos) name))
                     (nerd-icons-icon-for-dir name))
                    (is-symlink
                     (nerd-icons-octicon "nf-oct-file_symlink_file" :face 'nerd-icons-dsilver))
                    (t
                     (nerd-icons-icon-for-file name)))))
        (if (and icon (not (string-empty-p icon)))
            (propertize (concat icon " " result) 'user-eshell-icon-p t)
          (propertize result 'user-eshell-icon-p t))))))

(with-eval-after-load 'em-ls
  (advice-add 'eshell-ls-decorated-name :around #'user-eshell--add-icon-to-decorated-name))

;; Pure-Elisp helper commands for long and all-files listing without eza
(defun eshell/ll (&rest args)
  "List files in long format."
  (apply #'eshell/ls "-l" args))

(defun eshell/la (&rest args)
  "List all files including hidden."
  (apply #'eshell/ls "-a" args))

(defun eshell/lla (&rest args)
  "List all files in long format."
  (apply #'eshell/ls "-la" args))

(defun eshell/edit (&rest files)
  "Open FILES in Emacs buffers using `find-file'.
If no file is specified, prompt interactively for one."
  (if (null files)
      (call-interactively #'find-file)
    (dolist (file (flatten-tree files))
      (let* ((f (format "%s" file))
             (remote (file-remote-p default-directory))
             (target (cond
                      ((and remote (string-prefix-p "~/" f))
                       (concat remote f))
                      ((and remote (string= f "~"))
                       (concat remote "~"))
                      (t
                       (expand-file-name f)))))
        (find-file target)))))

(defalias 'eshell/e #'eshell/edit)
(put 'eshell/edit 'eshell-filename-arguments t)
(put 'eshell/edit 'eshell-no-numeric-conversions t)
(put 'eshell/e 'eshell-filename-arguments t)
(put 'eshell/e 'eshell-no-numeric-conversions t)

(defun pcomplete/edit ()
  "Completion for `edit'."
  (while (pcomplete-here (pcomplete-entries))))
(defalias 'pcomplete/e #'pcomplete/edit)

(defun eshell/tramp-cleanup ()
  "Flush all remote TRAMP connections and cache."
  (interactive)
  (when (fboundp 'tramp-cleanup-all-connections)
    (tramp-cleanup-all-connections))
  (eshell-printn "All TRAMP connections and caches have been cleaned."))

;;; ---------------------------------------------------------------------------
;;; Remote Navigation & Completion Hardening
;;; ---------------------------------------------------------------------------

(defun user-eshell--fix-remote-cd (orig-fun &rest args)
  "Ensure `cd', `cd ~', or `cd ~/path' stays on remote host when `default-directory' is remote."
  (let* ((remote (file-remote-p default-directory))
         (flat-args (flatten-tree args))
         (path (car flat-args)))
    (if (and remote (or (null path) (string= path "") (string= path "~") (string-prefix-p "~/" path)))
        (let ((remote-target (if (or (null path) (string= path "") (string= path "~"))
                                 (concat remote "~")
                               (concat remote path))))
          (apply orig-fun (cons remote-target (cdr flat-args))))
      (apply orig-fun args))))

(advice-add 'eshell/cd :around #'user-eshell--fix-remote-cd)

(defun user-eshell--inhibit-corfu-auto ()
  "Inhibit `corfu-auto' in remote TRAMP directories.
This prevents `while-no-input' from interrupting in-flight SSH commands
and desynchronizing TRAMP connection buffers.  Explicit TAB completion remains."
  (or (file-remote-p default-directory)
      (when-let* ((word (thing-at-point 'filename t)))
        (file-remote-p word))))

(with-eval-after-load 'corfu
  (add-hook '+corfu-inhibit-auto-functions #'user-eshell--inhibit-corfu-auto))

;;; ---------------------------------------------------------------------------
;;; Eat Terminal Emulation for Eshell (inline interactive TUI apps)
;;; ---------------------------------------------------------------------------

(defun user-eshell--sync-eat-hel ()
  "Disable `hel-local-mode' while Eat forwards raw/semi-char keys to a TUI."
  (when (boundp 'hel-local-mode)
    (if (or (bound-and-true-p eat--semi-char-mode)
            (bound-and-true-p eat--char-mode)
            (bound-and-true-p eat--eshell-semi-char-mode)
            (bound-and-true-p eat--eshell-char-mode))
        (when hel-local-mode
          (hel-local-mode -1))
      (unless hel-local-mode
        (hel-local-mode 1)))))

(defun eshell/v (&rest args)
  "Run ARGS as a visual command in Eat, or open an Eat terminal buffer."
  (if args
      (apply #'eshell-exec-visual args)
    (eat)))

;; Run inside `(setup eat (:install t) ...)' so Elpaca activates `eat' on
;; `load-path' before `eat' functions or hooks execute during startup.
(setup eat
  (:install t)
  (:setopt eat-kill-buffer-on-exit t
           eat-enable-blinking-text t)
  (add-hook 'eshell-load-hook #'eat-eshell-mode)
  (add-hook 'eshell-load-hook #'eat-eshell-visual-command-mode)
  (when (featurep 'eshell)
    (eat-eshell-mode 1)
    (eat-eshell-visual-command-mode 1)))

(with-eval-after-load 'eat
  (dolist (hook '(eat--semi-char-mode-hook
                  eat--char-mode-hook
                  eat--eshell-semi-char-mode-hook
                  eat--eshell-char-mode-hook))
    (add-hook hook #'user-eshell--sync-eat-hel)))

;; Visual commands to run with Eat inside Eshell
(dolist (cmd '("vim" "nvim" "nano" "view"
               "htop" "btop" "top" "gputop"
               "less" "more"
               "yazi" "ranger"
               "lazygit" "tig"
               "tmux" "zellij" "screen"
               "ssh" "fzf" "fish"
               "nmtui" "alsamixer"
               "k9s" "lazydocker" "glow"))
  (add-to-list 'eshell-visual-commands cmd))

(dolist (subcmd '(("git" "log" "diff" "show")
                  ("gh" "dash")))
  (add-to-list 'eshell-visual-subcommands subcmd))

(dolist (opt '(("git" "--paginate")))
  (add-to-list 'eshell-visual-options opt))

;;; ---------------------------------------------------------------------------
;;; Buffer Title Tracking (Ghostel-style title + `*eshell: <title>*')
;;; ---------------------------------------------------------------------------

(defvar-local user-eshell-title nil
  "Clean window/modeline title for the current Eshell buffer (without `*eshell: ' wrapper).")

(defvar-local user-eshell--managed-buffer-name nil
  "Last buffer name set by `user-eshell--update-title'.
If the buffer name differs, the user manually renamed it and tracking stops.")

(defvar-local user-eshell--running-command nil
  "Currently executing command name in this Eshell buffer, or nil.")

(defvar-local user-eshell--osc-title nil
  "Live OSC 0/2 title reported by an Eat-managed process in Eshell, or nil.")

(defun user-eshell--title-dir ()
  "Return compact directory label for Eshell buffer title (zero TRAMP I/O)."
  (if-let* ((remote (file-remote-p default-directory)))
      (let* ((vec (tramp-dissect-file-name remote))
             (user (or (tramp-file-name-user vec)
                       (file-remote-p default-directory 'user)))
             (host (tramp-file-name-host vec))
             (local-dir (directory-file-name (file-local-name default-directory))))
        (if (and (stringp user) (not (string-empty-p user)))
            (format "%s@%s:%s" user host (if (string-empty-p local-dir) "/" local-dir))
          (format "%s:%s" host (if (string-empty-p local-dir) "/" local-dir))))
    (let ((abbrev (abbreviate-file-name (directory-file-name default-directory))))
      (if (string-empty-p abbrev) "/" abbrev))))

(defun user-eshell--compute-title ()
  "Return the clean title string matching Ghostel/Fish (`<dir> - eshell')."
  (let ((dir (user-eshell--title-dir)))
    (cond
     ((and (stringp user-eshell--osc-title)
           (not (string-empty-p user-eshell--osc-title)))
      user-eshell--osc-title)
     ((and (stringp user-eshell--running-command)
           (not (string-empty-p user-eshell--running-command)))
      (format "%s: %s - eshell" dir user-eshell--running-command))
     (t (format "%s - eshell" dir)))))

(defun user-eshell--format-title ()
  "Return the formatted `*eshell: TITLE*' buffer name for current buffer state."
  (format "*eshell: %s*" (user-eshell--compute-title)))

(defun user-eshell--update-title (&rest _)
  "Update `user-eshell-title' and rename buffer to match directory, command, or OSC title.
Declines after a manual rename or on non-default project-eshell buffers."
  (when (derived-mode-p 'eshell-mode)
    (if (or (equal (buffer-name) user-eshell--managed-buffer-name)
            (and (null user-eshell--managed-buffer-name)
                 (string-prefix-p "*eshell" (buffer-name))))
        (let* ((title (user-eshell--compute-title))
               (new-name (format "*eshell: %s*" title)))
          (setq user-eshell-title title)
          (unless (equal new-name (buffer-name))
            ;; Skip if buffer already holds the uniquified name `NEW-NAME<N>'.
            (unless (equal (buffer-name)
                           (generate-new-buffer-name new-name (buffer-name)))
              (rename-buffer new-name t)))
          (setq user-eshell--managed-buffer-name (buffer-name))
          (force-mode-line-update))
      (setq user-eshell-title nil))))

(defun user-eshell--on-prepare-command ()
  "Record active command and update Eshell buffer title before execution."
  (when (and (derived-mode-p 'eshell-mode)
             (bound-and-true-p eshell-last-command-name))
    (let ((cmd (file-name-nondirectory eshell-last-command-name)))
      (unless (string-empty-p cmd)
        (setq user-eshell--running-command cmd)
        (user-eshell--update-title)))))

(defun user-eshell--on-post-command ()
  "Clear running command state once command finishes and restore directory title."
  (when (derived-mode-p 'eshell-mode)
    (setq user-eshell--running-command nil
          user-eshell--osc-title nil)
    (user-eshell--update-title)))

(defun user-eshell--setup-eat-title-hook ()
  "Forward Eat OSC 0/2 title updates inside Eshell to the buffer name."
  (when-let* ((term (bound-and-true-p eat-terminal)))
    (let ((buf (current-buffer)))
      (setf (eat-term-parameter term 'set-title-function)
            (lambda (_term title)
              (when (buffer-live-p buf)
                (with-current-buffer buf
                  (setq user-eshell--osc-title
                        (and (stringp title) (not (string-empty-p title)) title))
                  (user-eshell--update-title))))))))

(add-hook 'eshell-mode-hook #'user-eshell--update-title)
(add-hook 'eshell-directory-change-hook #'user-eshell--update-title)
(add-hook 'eshell-prepare-command-hook #'user-eshell--on-prepare-command)
(add-hook 'eshell-post-command-hook #'user-eshell--on-post-command)

(with-eval-after-load 'eat
  (add-hook 'eat-eshell-exec-hook #'user-eshell--setup-eat-title-hook)
  (add-hook 'eat-eshell-exit-hook #'user-eshell--on-post-command))

;;; ---------------------------------------------------------------------------
;;; General Eshell Settings
;;; ---------------------------------------------------------------------------

(setopt eshell-banner-message ""
        eshell-destroy-buffer-when-process-dies t
        eshell-scroll-to-bottom-on-input 'this
        eshell-error-if-no-glob t
        eshell-hist-ignoredups t
        eshell-save-history-on-exit t)

;;; ---------------------------------------------------------------------------
;;; Built-in Prompt & Input Rebinding (eshell-rebind)
;;; ---------------------------------------------------------------------------

(require 'em-rebind)
(add-to-list 'eshell-modules-list 'eshell-rebind)
;; Do not let eshell-rebind blindly confine movement commands to input in all states,
;; because that breaks Hel normal-mode navigation (<up>, k, line-move into scrollback).
(setopt eshell-confine-point-to-input nil)
;; Ensure DEL (ascii 127) as well as <backspace> are mapped to eshell-delete-backward-char
(add-to-list 'eshell-rebind-keys-alist '([127] . eshell-delete-backward-char))

;;; ---------------------------------------------------------------------------
;;; Hel Modal Editor Integration
;;; ---------------------------------------------------------------------------

;; Start Eshell in insert mode
(when (fboundp 'hel-set-initial-state)
  (hel-set-initial-state 'eshell-mode 'insert))

;; Bindings in Eshell
(with-eval-after-load 'esh-mode
  ;; Clear screen with C-l in Eshell
  (keymap-set eshell-mode-map "C-l" #'eshell/clear))

;;; ---------------------------------------------------------------------------
;;; Global Keybindings
;;; ---------------------------------------------------------------------------

(keymap-global-set "s-<return>" #'eshell-new)
(keymap-global-set "s-RET" #'eshell-new)
(keymap-global-set "S-s-<return>" #'ghostel-new)
(keymap-global-set "S-s-RET" #'ghostel-new)
(keymap-global-set "C-c o e" #'eshell-new)

;;; .
(provide 'user-eshell)
;;; user-eshell.el ends here
