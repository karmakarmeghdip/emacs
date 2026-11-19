;;; user-eshell.el                 -*- lexical-binding: t; no-byte-compile: t -*-

;;; Commentary:
;;
;; Personal Eshell configuration:
;; - Minimalist Starship-like prompt styled with Catppuccin palette
;; - Ghostel integration for running interactive TUI applications (vim, htop, btop, etc.)
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
;;; Minimalistic Starship-inspired Prompt
;;; ---------------------------------------------------------------------------

(defun user-eshell--root-p ()
  "Return non-nil if current session is running as root locally or remotely."
  (if-let* ((remote-user (file-remote-p default-directory 'user)))
      (string= remote-user "root")
    (= (user-uid) 0)))

(defun user-eshell--git-branch ()
  "Return current git branch or revision if in a git repository, else nil."
  (unless (file-remote-p default-directory)
    (when (locate-dominating-file default-directory ".git")
      (with-temp-buffer
        (if (zerop (call-process "git" nil t nil "symbolic-ref" "--short" "-q" "HEAD"))
            (string-trim (buffer-string))
          (when (zerop (call-process "git" nil t nil "rev-parse" "--short" "-q" "HEAD"))
            (string-trim (buffer-string))))))))

(defun user-eshell--git-dirty-p ()
  "Return non-nil if working tree has uncommitted or untracked changes."
  (unless (file-remote-p default-directory)
    (not (zerop (call-process "git" nil nil nil "status" "--porcelain" "-uno")))))

(defun user-eshell--git-info ()
  "Return formatted git info string for prompt, or nil."
  (unless (file-remote-p default-directory)
    (when-let* ((branch (user-eshell--git-branch)))
      (let* ((dirty (user-eshell--git-dirty-p))
             (branch-face `(:foreground ,(user-eshell--color 'mauve "#cba6f7") :weight bold))
             (dirty-face `(:foreground ,(user-eshell--color 'peach "#fab387")))
             (subtext-face `(:foreground ,(user-eshell--color 'overlay0 "#6c7086"))))
        (concat
         (propertize " on " 'face subtext-face)
         (propertize " " 'face branch-face)
         (propertize branch 'face branch-face)
         (if dirty
             (propertize " [!]" 'face dirty-face)
           ""))))))

(defun user-eshell--remote-info ()
  "Return remote [user@]host string if `default-directory' is remote."
  (when-let* ((remote (file-remote-p default-directory)))
    (let* ((vec (tramp-dissect-file-name remote))
           (user (or (tramp-file-name-user vec)
                     (file-remote-p default-directory 'user)))
           (host (tramp-file-name-host vec))
           (overlay-face `(:foreground ,(user-eshell--color 'overlay0 "#6c7086")))
           (user-face `(:foreground ,(user-eshell--color 'yellow "#f9e2af")))
           (host-face `(:foreground ,(user-eshell--color 'teal "#94e2d5"))))
      (concat
       (when (and (stringp user) (not (string-empty-p user)))
         (concat (propertize user 'face user-face)
                 (propertize "@" 'face overlay-face)))
       (when (and (stringp host) (not (string-empty-p host)))
         (propertize host 'face host-face))
       (propertize " in " 'face overlay-face)))))

(defun user-eshell--venv-info ()
  "Return formatted virtualenv info if active, else nil."
  (when-let* ((venv (or (getenv "VIRTUAL_ENV") (getenv "CONDA_DEFAULT_ENV"))))
    (let ((name (file-name-nondirectory (directory-file-name venv)))
          (face `(:foreground ,(user-eshell--color 'yellow "#f9e2af")))
          (subtext `(:foreground ,(user-eshell--color 'overlay0 "#6c7086"))))
      (concat (propertize " (" 'face subtext)
              (propertize (concat "󰌠 " name) 'face face)
              (propertize ")" 'face subtext)))))

(defun user-eshell--prompt-dir ()
  "Return formatted directory for prompt."
  (let* ((pwd (if (fboundp 'eshell/pwd) (eshell/pwd) default-directory))
         (dir (if (file-remote-p default-directory)
                  (file-local-name pwd)
                (abbreviate-file-name pwd))))
    (propertize (or dir "") 'face `(:foreground ,(user-eshell--color 'blue "#89b4fa") :weight bold))))

(defun user-eshell-prompt ()
  "Return Starship-like minimalistic prompt in Catppuccin colors."
  (condition-case nil
      (concat
       (or (user-eshell--remote-info) "")
       (user-eshell--prompt-dir)
       (or (user-eshell--git-info) "")
       (or (user-eshell--venv-info) "")
       "\n"
       (let ((char (if (user-eshell--root-p) "# " "λ "))
             (success (eshell-exit-success-p)))
         (propertize char 'face
                     `(:foreground ,(if success
                                        (user-eshell--color 'green "#a6e3a1")
                                      (user-eshell--color 'red "#f38ba8"))
                       :weight bold))))
    (error
     ;; Fallback prompt if any remote or tramp inspection fails
     (concat (if (file-remote-p default-directory)
                 (file-local-name (abbreviate-file-name default-directory))
               (abbreviate-file-name default-directory))
             "\nλ "))))

;; Disable eshell-highlight-prompt so custom Catppuccin faces are preserved
(setq eshell-highlight-prompt nil)
(setq eshell-prompt-regexp "^[^\n]*[λ❯#$] ")
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
;;; Ghostel Integration (interactive TUI apps)
;;; ---------------------------------------------------------------------------

(with-eval-after-load 'ghostel
  (require 'ghostel-eshell nil t)
  (when (fboundp 'ghostel-eshell-visual-command-mode)
    (ghostel-eshell-visual-command-mode 1)
    (defalias 'eshell/v #'eshell/ghostel)))

;; Additional visual commands that should run inside Ghostel
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
;;; General Eshell Settings
;;; ---------------------------------------------------------------------------

(setopt eshell-banner-message ""
        eshell-destroy-buffer-when-process-dies t
        eshell-scroll-to-bottom-on-input 'this
        eshell-error-if-no-glob t
        eshell-hist-ignoredups t
        eshell-save-history-on-exit t)

;; Hel modal editor integration: start Eshell in insert mode
(when (fboundp 'hel-set-initial-state)
  (hel-set-initial-state 'eshell-mode 'insert))

;; Clear screen with C-l in Eshell
(with-eval-after-load 'esh-mode
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
