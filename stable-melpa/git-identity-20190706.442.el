;;; git-identity.el --- Identity management for (ma)git -*- lexical-binding: t -*-

;; Copyright (C) 2019 Akira Komamura

;; Author: Akira Komamura <akira.komamura@gmail.com>
;; Version: 0.1
;; Package-Version: 20190706.442
;; Package-Requires: ((emacs "25.1") (dash "2.10") (hydra "0.14") (f "0.20"))
;; Keywords: vc convenience
;; URL: https://github.com/akirak/git-identity.el

;; This file is not part of GNU Emacs.

;;; License:

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This Emacs package lets you manage local Git identities, i.e.
;; user.name and user.email options in .git/config, inside
;; Emacs.  It can be useful if you satisfy all of the following
;; conditions:

;; - You have multiple Git identities on the same machine(s).
;; 
;; - You use Emacs.
;; 
;; - You almost always use magit for Git operations on your
;;   machine(s).

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'f)
(require 'dash)
(require 'hydra)

(declare-function 'magit-commit "magit-commit")

(defgroup git-identity nil
  "Identity management for Git."
  :group 'vc)

;;;; Custom vars

;;;###autoload
(defcustom git-identity-git-executable "git"
  "Executable file of Git."
  :group 'git-identity
  :type 'string)

;;;###autoload
(defcustom git-identity-default-username
  (when (and (stringp user-full-name)
             (not (string-empty-p user-full-name)))
    user-full-name)
  "Default full name of the user set in Git repositories."
  :group 'git-identity
  :type 'string)

;;;###autoload
(defcustom git-identity-list nil
  "List of plists of Git identities."
  :group 'git-identity
  :type '(alist :tag "Identity setting"
                :key-type (string :tag "E-mail address (user.email)")
                :value-type (plist :tag "Options"
                                   :options
                                   (((const :tag "Full name" :name)
                                     string)
                                    ((const :tag "Host names" :domains)
                                     (repeat string))
                                    ((const :tag "Directories" :dirs)
                                     (repeat string))))))

(defcustom git-identity-verify t
  "When non-nil, check if the identity is consistent.

This check is run if the repository doesn't have a local
identity.
If the repository is expected to have a certain
identity according to the domain name or the local directory (see
`git-identity-list'), and the identity is different from the
global setting, `git-identity-magit-mode' asks if you want to
add a local identity setting to the repository.
This ensures that your identity policies defined in
`git-identity-list' are applied properly when you have a global
identity setting."
  :group 'git-identity
  :type 'boolean)

;;;; Identity operations
(defun git-identity--username (identity)
  "Extract the user name in IDENTITY or return the default."
  (or (plist-get (cdr identity) :name)
      (git-identity--default-username)))

(defun git-identity--email (identity)
  "Extract the email in IDENTITY."
  (car identity))

(defun git-identity--default-username ()
  "Retrieve the default user name."
  (or git-identity-default-username
      (customize-set-variable
       'git-identity-default-username
       (read-string "Enter your full name used as the default: "
                    nil nil
                    (when (and (stringp user-full-name)
                               (not (string-empty-p user-full-name)))
                      user-full-name)))))

;;;; Guessing identity for the current repository

(defun git-identity--guess-identity ()
  "Pick an identity which seems suitable for the current repo."
  (let ((url (or (git-identity--git-config-get "remote.origin.pushurl")
                 (git-identity--git-config-get "remote.origin.url"))))
    (-find (lambda (ent)
             ;; Which should take precedence? Domain or directory?
             (let ((plist (cdr ent)))
               (or (when url
                     (let ((domain (git-identity--host-in-git-url url)))
                       (when (-contains? (plist-get plist :domains) domain)
                         (message "Chosen an identity based on domain %s in url \"%s\""
                                  domain url)
                         t)))
                   (let ((ancestor (git-identity--inside-dirs-p default-directory
                                                                (plist-get plist :dirs))))
                     (when ancestor
                       (message "Chosen an identity based on an ancestor directory %s"
                                ancestor)
                       t)))))
           git-identity-list)))

(defun git-identity--host-in-git-url (url)
  "Extract the host from URL of a Git repository."
  (cond
   ((string-match (rx bol "https://" (group (+ (not (any "/:"))))) url)

    (match-string 1 url))
   ((string-match (rx bol (?  (+ (not (any "@:"))) "@")
                      (group (+ (not (any ":"))))) url)
    (match-string 1 url))))

(defun git-identity--inside-dirs-p (target maybe-ancestors)
  "Return non-nil if TARGET is a descendant of any of MAYBE-ANCESTORS."
  (let ((abs-target (expand-file-name target)))
    (--some (f-ancestor-of-p (expand-file-name it) abs-target)
            maybe-ancestors)))

;;;; Querying and setting an identity in a repository

;;;###autoload
(defun git-identity-complete (prompt)
  "Display PROMPT and select an identity from `git-identity-list'."
  (let ((input (completing-read prompt git-identity-list
                                nil nil nil nil
                                (car
                                 (git-identity--guess-identity)))))
    (or (assoc input git-identity-list)
        (if (git-identity--validate-mail-address input)
            (let* ((name (read-string "Name: "))
                   (newent (list input :name name)))
              (customize-set-variable git-identity-list
                                      (cons newent git-identity-list)))
          (user-error "Not a valid mail address: %s" input)))))

(defun git-identity--validate-mail-address (_input)
  "Return non-nil if _INPUT is a valid e-mail address."
  ;; TODO: Really validate the input
  t)

;;;###autoload
(defun git-identity-set-identity (&optional prompt)
  "Set the identity for the repository at the working directory.

This function lets the user choose an identity for the current
repository using `git-identity-complete' function and sets the
user name and the email address in the local configuration of the
Git repository.

Optionally, you can set PROMPT for the identity.
If it is omitted, the default prompt is used."
  (interactive)
  (let ((root (git-identity--find-repo)))
    (unless root
      (user-error "Not in a Git repository"))
    (let* ((default-directory root)
           (identity (git-identity-complete
                      (or prompt
                          (format "Select an identity in %s: " root)))))
      (git-identity--set-identity identity))))

(defun git-identity--has-identity-p ()
  "Return non-nil If the current repository has an identity."
  (and (git-identity--git-config-get "user.name")
       (git-identity--git-config-get "user.email")))

(defun git-identity--find-repo (&optional startdir)
  "Find a Git working directory which is STARTDIR or its ancestor."
  (let ((startdir (or startdir default-directory)))
    (if (file-directory-p ".git")
        startdir
      (locate-dominating-file startdir ".git"))))

(defun git-identity--set-identity (identity)
  "Set the identity in the current repo to IDENTITY."
  (git-identity--git-config-set
   "user.name" (git-identity--username identity)
   "user.email" (git-identity--email identity)))

;;;; Hydra

(defhydra git-identity-hydra ()
  "
Git identity in %s(git-identity--find-repo)
=======================================================
User name: %(git-identity--git-config-get \"user.name\")
E-mail: %s(git-identity--git-config-get \"user.email\")
-------------------------------------------------------
"
  ("s" (progn
         (git-identity-set-identity)
         (hydra-keyboard-quit))
   "Set an identity")
  ("C" (customize-variable 'git-identity-list)
   "Configure your identities"))

;;;###autoload (autoload 'git-identity-info "git-identity")
(defalias 'git-identity-info 'git-identity-hydra/body
  "Display the identity information of the current repository.")

(defun git-identity--block-if-not-in-repo (orig &rest args)
  "Prevent running ORIG function with ARGS if not in a Git repo."
  (if (git-identity--find-repo)
      (apply orig args)
    (user-error "Not inside a Git repo")))

(advice-add #'git-identity-info :around #'git-identity--block-if-not-in-repo)


;;;; Mode definition
;;;###autoload
(define-minor-mode git-identity-magit-mode
  "Global minor mode for running Git identity checks in Magit.

This mode enables the following features:

- Add a hook to `magit-commit' to ensure that you have a
  global/local identity configured in the repository.
"
  :global t
  (cond
   ;; Activate the mode
   (git-identity-magit-mode
    (advice-add #'magit-commit :before #'git-identity-ensure-internal))
   ;; Deactivate the mode
   (t
    (advice-remove #'magit-commit #'git-identity-ensure-internal))))

(defun git-identity-ensure-internal ()
  "Ensure that the current repository has an identity."
  (let ((local-email (git-identity--git-config-get "user.email" "--local"))
        (global-email (git-identity--git-config-get "user.email" "--global"))
        (expected-identity (git-identity--guess-identity)))
    (cond
     ;; No identity is configured yet, but there is an expected identity.
     ((not (git-identity--has-identity-p))
      (if (and expected-identity
               (yes-or-no-p
                (format "Set the identity in %s to \"%s\" <%s>? "
                        (git-identity--find-repo)
                        (git-identity--username expected-identity)
                        (git-identity--email expected-identity))))
          (git-identity--set-identity expected-identity)
        (git-identity-set-identity "A proper identity is not set. Select one: ")))
     ;; There is no local setting, and the global setting is contradictory
     ;; with the expectation. Ask if you want to apply the local setting.
     ((and git-identity-verify
           (not local-email)
           (not (equal (git-identity--email expected-identity)
                       global-email))
           (yes-or-no-p
            (format "This repository (%s) is supposed to have an identity of\n\
\"%s\", but \"%s\" is about to be used \n\
because of a global setting.\n\
Apply the expected identity \"%s\" <%s>\n\
to this repository? "
                    (git-identity--find-repo)
                    (git-identity--email expected-identity)
                    global-email
                    (git-identity--username expected-identity)
                    (git-identity--email expected-identity))))
      (git-identity--set-identity expected-identity)))))

;;;; Git utilities
(defun git-identity--git-config-set (&rest pairs)
  "Set a PAIRS of Git options."
  (unless (yes-or-no-p (format "Are you sure you want to set the following Git options in %s?\n\n%s"
                               (git-identity--find-repo)
                               (mapconcat (pcase-lambda (`(,key ,value))
                                            (format "%s=%s" key value))
                                          (-partition 2 pairs)
                                          "\n")))
    (user-error "Aborted"))
  (cl-loop for (key value . _) on pairs by #'cddr
           do (git-identity--run-git "config" "--local" "--add" key value)))

(defun git-identity--run-git (&rest args)
  "Run Git with ARGS."
  (apply #'call-process git-identity-git-executable nil nil nil args))

(defun git-identity--git-config-get (key &optional scope)
  "Get the value of a Git option.

KEY is the name of the option, and optional SCOPE is a string passed
as an argument to Git command to specify the scope, which is either
\"--global\" or \"--local\"."
  (with-temp-buffer
    (when (= 0 (apply #'call-process git-identity-git-executable nil t nil
                      (delq nil `("config" "--get" ,scope ,key))))
      (string-trim-right (buffer-string)))))

(provide 'git-identity)
;;; git-identity.el ends here
