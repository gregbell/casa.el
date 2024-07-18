;;; casa.el --- Manage dotfiles with Emacs and Org-Mode  -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2024 Greg Bell
;;
;; Author: Greg Bell <code@gregbell.ca>
;; Keywords: dotfiles
;; URL: https://github.com/gregbell/casa.el
;;
;;; Commentary:
;;
;;; Code:

(require 'vc)

(defcustom casa-dotfiles-dir "~/.config/dotfiles"
  "The location of your dotfiles directory."
  :type '(directory)
  :group 'casa)

(defvar casa--deploy-filename "deploy")

(defun casa-dotfiles-dir ()
  "Return the dotfiles directory expanded"
  (expand-file-name casa-dotfiles-dir))

(defvar casa--default-readme-text
"#+TITLE: README

My dotfiles managed by =casa.el=.")

(defun casa--git (&rest args)
  "Run a git command"
  (apply #'vc-git-command "*casa-git*" 0 nil args))

(defun casa-init-dotfiles-dir ()
  "Initialize an empty dotfiles directory and repo."
  (interactive)
  (mkdir (casa-dotfiles-dir) t)

  ;; cd casa-dotfiles-dir
  (let ((default-directory (casa-dotfiles-dir)))
    (with-temp-buffer
      (vc-git-create-repo)

      ;; Create a README & commit
      (let ((readme-file (expand-file-name "README.org" casa-dotfiles-dir)))
        (unless (file-exists-p readme-file)
          (with-current-buffer (find-file-noselect readme-file)
            (insert casa--default-readme-text)
            (vc-register)
            (vc-checkin (list readme-file) 'git "Initial README")))))))

(defun casa-init-worktree-dir ()
  "Initialize the dotfiles worktree in the home directory."
  (interactive)
  (let ((default-directory (casa-dotfiles-dir)))
    ;; Initialize the workdir in a temp location. git-worktree does not support
    ;; initializing into a directory with contents, which we assume your home
    ;; directory has. *This will fail if a branch with that name already
    ;; exists locally.*
    (with-temp-buffer
      (vc-git-command nil 0 nil "config" "extensions.worktreeConfig" "true")
      (vc-git-command nil 0 nil "worktree" "add" "-b"
                      (concat "machine-" (system-name))
                      "--orphan"
                      (expand-file-name "~/.home-dotfiles"))))

  (let ((default-directory (expand-file-name "~/")))
    (with-temp-buffer
      ;; Move the worktree to the home folder
      (rename-file (expand-file-name "~/.home-dotfiles/.git") (expand-file-name "~/.git"))
      ;; Repair the worktree with the main repo
      (vc-git-command nil 0 nil "worktree" "repair" (expand-file-name "~/"))
      ;; Don't show untracked files
      (vc-git-command nil 0 nil "config" "--worktree" "status.showUntrackedFiles" "no")
      ;; Delete the temp folder
      (delete-directory (expand-file-name "~/.home-dotfiles")))))

(defun casa-init ()
  "Initialize an empty dotfiles directory and worktree."
  (interactive)
  (casa-init-dotfiles-dir)
  (casa-init-worktree-dir))

(defun casa-deploy ()
  "Tangle all your dotfiles and commit them to your home directory."
  (interactive)

  (let ((deploy-file (expand-file-name "deploy.el" (casa-dotfiles-dir))))
    (when (file-exists-p deploy-file)
      (load deploy-file)))

  ;; 1. Raise error if there are any changes to existing dot files
  ;; 2. Iterate through each .org file in the dotfiles directory:
  (let ((org-files (directory-files (casa-dotfiles-dir) t "\\.org$")))
    (dolist (file org-files)
      (with-current-buffer (find-file-noselect file)
  ;;   a. tangle the file
        (let ((tangled (org-babel-tangle)))
          (message "Successfully tangled %s, got %s" file tangled)
          (let ((default-directory (expand-file-name "~/")))
            (with-temp-buffer
  ;;   b. add the file to git
              (apply #'casa--git "add" tangled))

          )))))

  ;; 3. Commit all the changes. (rollback if there's an error?)
  (let ((default-directory (expand-file-name "~/")))
    (with-temp-buffer
      (casa--git "commit" "-m" (format-time-string "'Deployed dotfiles at %Y-%m-%d %H:%M:%S'")))))

(defun casa-clone-dotfiles (url)
  "Clone dotfiles from a remote onto this machine"
  (interactive "sDotfiles URL: ")
  (casa--git "clone" url (casa-dotfiles-dir)))

(defun casa-home-dir-dirty-p ()
  "Check if dotfiles in the home directory have been modified. The results
   of the check are stored in the *casa-git* buffer."
  (interactive)
  (let ((default-directory (expand-file-name "~/")))
    (with-temp-buffer
      (casa--git "status" "--porcelain"))
    (with-current-buffer "*casa-git*"
      (not (eq (buffer-size) 0)))))

(defun casa-load-host-deploy-file ()
  "Load deploy/{hostname}.el if it exists. This can be used in your deploy.el file."
  (let ((deploy-file (expand-file-name
                      (concat  "deploy/" system-name ".el")
                      (casa-dotfiles-dir))))
    (if (file-exists-p deploy-file)
        (load deploy-file)
      (message "Host deploy file %s does not exist" deploy-file))))

(provide 'casa)
;;; casa.el ends here
