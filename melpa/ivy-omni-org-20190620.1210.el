;;; ivy-omni-org.el --- Browse anything in Org mode -*- lexical-binding: t -*-

;; Copyright (C) 2019 Akira Komamura

;; Author: Akira Komamura <akira.komamura@gmail.com>
;; Version: 0.2
;; Package-Version: 20190620.1210
;; Package-Requires: ((emacs "25.1") (ivy "0.10") (dash "2.12"))
;; Keywords: outlines
;; URL: https://github.com/akirak/ivy-omni-org

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

;; This library provides `ivy-omni-org' command, which lets you access
;; buffers, files, and bookmarks via a single Ivy interface.

;;; Code:

(require 'ivy)
(require 'bookmark)
(require 'dash)
(require 'cl-lib)
(require 'seq)

(defgroup ivy-omni-org nil
  "Ivy interface to Org buffers, files, and bookmarks."
  :group 'org
  :group 'ivy)

(declare-function 'org-contextualize-keys "org")
(autoload 'org-contextualize-keys "org")
(defvar org-agenda-custom-commands)
(defvar org-agenda-custom-commands-contexts)

;;;; Custom variables
(defcustom ivy-omni-org-file-sources nil
  "List of sources producing a list of Org files."
  :type '(repeat (choice symbol function))
  :group 'ivy-omni-org)

(defcustom ivy-omni-org-buffer-display-transformer
  'ivy-omni-org-default-buffer-transformer
  "Display transformer for Org buffers."
  :type 'function
  :group 'ivy-omni-org)
(defcustom ivy-omni-org-file-display-transformer
  'ivy-omni-org-default-file-transformer
  "Display transformer for Org files."
  :type 'function
  :group 'ivy-omni-org)
(defcustom ivy-omni-org-bookmark-display-transformer
  'ivy-omni-org-default-bookmark-transformer
  "Display transformer for Org bookmarks."
  :type 'function
  :group 'ivy-omni-org)

(defcustom ivy-omni-org-content-types
  '(buffers files agenda-commands bookmarks)
  "Permutation of types to include in `ivy-omni-org'."
  :type '(repeat (choice (const buffers)
                         (const files)
                         (const agenda-commands)
                         (const bookmarks)))
  :group 'ivy-omni-org)

;;;; Faces
(defface ivy-omni-org-file-name
  '((default :inherit 'ivy-virtual))
  "Face for file names in the function.")

(defface ivy-omni-org-bookmark-name
  '((default :inherit 'font-lock-string-face))
  "Face for file names in the function.")

(defface ivy-omni-org-custom-agenda-key
  '((default :inherit 'font-lock-keyword-face))
  "Face for the key of each custom agenda command.")

(defface ivy-omni-org-custom-agenda-desc
  '((default))
  "Face for the description of each custom agenda command.")

;;;; Macros and utility functions
(defsubst ivy-omni-org--propertize-candidates (type items)
  "Add text property for TYPE to ITEMS."
  (-map #'(lambda (str)
            (propertize str 'ivy-omni-org-type type))
        items))

(defsubst ivy-omni-org--candidate-type (inp)
  "Extract the candidate type from the text property of INP."
  (get-text-property 0 'ivy-omni-org-type inp))

;;;; Commands
(defmacro ivy-omni-org--make-display-action (display-func)
  "Make an action on input using DISPLAY-FUNC."
  `(lambda (inp)
     (cl-ecase (ivy-omni-org--candidate-type inp)
       ('buffer (funcall ,display-func inp))
       ('file (ivy-omni-org--find-file-with-display-func inp ,display-func))
       ('bookmark (bookmark-jump inp ,display-func))
       ('agenda-command (org-agenda nil (ivy-omni-org--agenda-key inp))))))

;;;###autoload
(defun ivy-omni-org ()
  "Ivy interface to buffers, files, and bookmarks in Org."
  (interactive)
  (ivy-read "Org: "
            #'ivy-omni-org--complete
            :caller #'ivy-omni-org
            :action (ivy-omni-org--make-display-action 'switch-to-buffer)))

(defun ivy-omni-org--prepend-entry-type (type entry)
  "Prepend TYPE indicator to an Ivy ENTRY."
  (declare (indent 1))
  (concat (format "%-8s "
                  (propertize type 'face 'font-lock-comment-face))
          entry))

(defun ivy-omni-org-default-buffer-transformer (buf)
  "Default display transformer for BUF."
  (format "%-18s  %s" buf (or (buffer-file-name buf) nil)))

(defun ivy-omni-org-default-file-transformer (file)
  "Default display transformer for FILE."
  (propertize (abbreviate-file-name file)
              'face 'ivy-omni-org-file-name))

(defun ivy-omni-org-default-bookmark-transformer (name)
  "Default display transformer for a bookmark with NAME."
  (format "%-30s  %s"
          (propertize name 'face 'ivy-omni-org-bookmark-name)
          (propertize (abbreviate-file-name (bookmark-get-filename name))
                      'face 'ivy-omni-org-file-name)))

(defun ivy-omni-org-agenda-command-transformer (entry)
  "Transform ENTRY of a custom agenda command."
  (if (string-match (rx bol (group "@" (+ (not space)))
                        (group (+ anything))
                        eol)
                    entry)
      (concat (propertize (match-string 1 entry)
                          'face 'ivy-omni-org-custom-agenda-key)
              (propertize (match-string 2 entry)
                          'face 'ivy-omni-org-custom-agenda-desc))
    (condition-case-unless-debug err
        (error "Failed to transform agenda entry %s" entry)
      (error (progn
               (message err)
               entry)))))

(defun ivy-omni-org--display-transformer (inp)
  "The default display transformer for `ivy-omni-org'.

INP is an entry in the Ivy command."
  (condition-case-unless-debug _
      (cl-ecase (ivy-omni-org--candidate-type inp)
        ('buffer
         (ivy-omni-org--prepend-entry-type "buffer"
           (funcall ivy-omni-org-buffer-display-transformer inp)))
        ('file
         (ivy-omni-org--prepend-entry-type "file"
           (funcall ivy-omni-org-file-display-transformer inp)))
        ('agenda-command
         (ivy-omni-org--prepend-entry-type "agenda"
           (ivy-omni-org-agenda-command-transformer inp)))
        ('bookmark
         (ivy-omni-org--prepend-entry-type "bookmark"
           (funcall ivy-omni-org-bookmark-display-transformer inp))))
    (error inp)))

(ivy-set-display-transformer
 'ivy-omni-org
 #'ivy-omni-org--display-transformer)

(defun ivy-omni-org--bookmarks ()
  "Get a list of Org bookmarks."
  (bookmark-maybe-load-default-file)
  (cl-remove-if-not (lambda (info)
                      (let ((filename (alist-get 'filename (cdr info))))
                        (string-match-p "\\.org\\'" filename)))
                    bookmark-alist))

(defun ivy-omni-org--agenda-key (inp)
  "Extract the agenda key from INP."
  (if (string-match (rx bol "@" (group (+ (not space)))) inp)
      (match-string 1 inp)
    (error "Failed to extract the key from %s" inp)))

(defun ivy-omni-org--make-agenda-entry (key)
  "Build an entry for the custom agenda command with KEY."
  (format "@%-2s %s" key (nth 1 (assoc key org-agenda-custom-commands))))

(defun ivy-omni-org--complete (&rest _args)
  "Generate completion candidates.

_ARGS is a list of arguments as passed to `all-completions'."
  (let* ((bufs (cl-remove-if-not
                (lambda (buf)
                  (with-current-buffer buf
                    (derived-mode-p 'org-mode)))
                (mapcar #'get-buffer (internal-complete-buffer "" nil t))))
         (bufnames (mapcar #'buffer-name bufs))
         (loaded-files (delq nil (mapcar #'buffer-file-name bufs)))
         (files (when (cl-member 'files ivy-omni-org-content-types)
                  (cl-delete-duplicates
                   (-flatten (mapcar (lambda (source)
                                       (cl-etypecase nil
                                         (function (funcall source))
                                         (symbol (cond
                                                  ((fboundp source)
                                                   (funcall source))
                                                  ((boundp source)
                                                   (symbol-value source))))))
                                     ivy-omni-org-file-sources))
                   :test #'file-equal-p)))
         (unloaded-files (seq-difference files loaded-files #'file-equal-p))
         (bookmarks (when (cl-member 'bookmarks ivy-omni-org-content-types)
                      (ivy-omni-org--bookmarks)))
         (agenda-commands (when (cl-member 'agenda-commands ivy-omni-org-content-types)
                            (require 'org-agenda)
                            (-map (lambda (entry)
                                    (ivy-omni-org--make-agenda-entry (car entry)))
                                  (org-contextualize-keys
                                   org-agenda-custom-commands
                                   org-agenda-custom-commands-contexts)))))
    (cl-loop for type in ivy-omni-org-content-types
             append (cl-ecase type
                      ('buffers
                       (ivy-omni-org--propertize-candidates
                        'buffer
                        bufnames))
                      ('files
                       (ivy-omni-org--propertize-candidates
                        'file
                        unloaded-files))
                      ('agenda-commands
                       (ivy-omni-org--propertize-candidates
                        'agenda-command
                        agenda-commands))
                      ('bookmarks
                       (ivy-omni-org--propertize-candidates
                        'bookmark
                        (mapcar #'car bookmarks)))))))

(defun ivy-omni-org--find-file-with-display-func (file display-func)
  "Display FILE using DISPLAY-FUNC."
  (funcall display-func (find-file-noselect file)))

(defun ivy-omni-org--edit-entry-action (inp)
  "Edit an entry on INP."
  (if (ignore-errors (bookmark-get-bookmark inp))
      (bookmark-rename inp)
    (message "%s is not a bookmark" inp)))

(ivy-add-actions
 'ivy-omni-org
 `(("j" ,(ivy-omni-org--make-display-action 'switch-to-buffer-other-window)
    "other window")
   ("f" ,(ivy-omni-org--make-display-action 'switch-to-buffer-other-frame)
    "other frame")
   ("e" ivy-omni-org--edit-entry-action "edit bookmark")))

(provide 'ivy-omni-org)
;;; ivy-omni-org.el ends here
