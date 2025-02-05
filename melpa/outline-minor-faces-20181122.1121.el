;;; outline-minor-faces.el --- Headings faces for outline-minor-mode  -*- lexical-binding: t -*-

;; Copyright (C) 2018 Jonas Bernoulli

;; Author: Jonas Bernoulli <jonas@bernoul.li>
;; Homepage: https://github.com/tarsius/bicycle
;; Keywords: outlines
;; Package-Version: 20181122.1121

;; Package-Requires: ((emacs "25.1"))

;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Unlike `outline-mode', `outline-minor-mode' does not change
;; the appearance of headings to look different from comments.

;; This package defines the faces `outline-minor-N', which inherit
;; from the respective `outline-N' faces used in `outline-mode' and
;; arranges for them to be used in `outline-minor-mode'.

;; Usage:
;;
;;   (use-package outline-minor-faces
;;     :after outline
;;     :config (add-hook 'outline-minor-mode-hook
;;                       'outline-minor-faces-add-font-lock-keywords))

;;; Code:

(defface outline-minor-0
  '((((class color) (background light)) :weight bold :background "light grey")
    (((class color) (background  dark)) :weight bold :background "grey20"))
  "Face that other `outline-minor-N' faces inherit from."
  :group 'outlines)

(defface outline-minor-1
  '((t (:inherit (outline-minor-0 outline-1))))
  "Level 1 headings in `outline-minor-mode'."
  :group 'outlines)

(defface outline-minor-2
  '((t (:inherit (outline-minor-0 outline-2))))
  "Level 2 headings in `outline-minor-mode'."
  :group 'outlines)

(defface outline-minor-3
  '((t (:inherit (outline-minor-0 outline-3))))
  "Level 3 headings in `outline-minor-mode'."
  :group 'outlines)

(defface outline-minor-4
  '((t (:inherit (outline-minor-0 outline-4))))
  "Level 4 headings in `outline-minor-mode'."
  :group 'outlines)

(defface outline-minor-5
  '((t (:inherit (outline-minor-0 outline-5))))
  "Level 5 headings in `outline-minor-mode'."
  :group 'outlines)

(defface outline-minor-6
  '((t (:inherit (outline-minor-0 outline-6))))
  "Level 6 headings in `outline-minor-mode'."
  :group 'outlines)

(defface outline-minor-7
  '((t (:inherit (outline-minor-0 outline-7))))
  "Level 7 headings in `outline-minor-mode'."
  :group 'outlines)

(defface outline-minor-8
  '((t (:inherit (outline-minor-0 outline-8))))
  "Level 8 headings in `outline-minor-mode'."
  :group 'outlines)

(defvar outline-minor-faces
  [outline-minor-1 outline-minor-2 outline-minor-3 outline-minor-4
   outline-minor-5 outline-minor-6 outline-minor-7 outline-minor-8])

(defvar-local outline-minor-faces-regexp nil
  "Regular expression to match a complete of a heading.
If this is nil, then a regular expression based on
`outline-regexp' is used.  The value of that variable cannot
be used directly because it is only supposed to match the
beginning of a heading.")

(defun outline-minor-faces--font-lock-keywords ()
  `((eval . (list ,(or outline-minor-faces-regexp
                       (concat "^\\(?:"
                               (if (derived-mode-p 'lisp-mode 'emacs-lisp-mode)
                                   ";;;\\(;* [^ \t\n]\\)"
                                 outline-regexp)
                               "\\)\\(?:.+\n\\|\n?\\)"))
                  0 '(outline-minor-faces--get-face) t))))

(defvar-local outline-minor-faces--top-level nil)

(defun outline-minor-faces--level ()
  (save-excursion
    (beginning-of-line)
    (looking-at outline-regexp)
    (funcall outline-level)))

(defun outline-minor-faces--get-face ()
  (save-excursion
    (goto-char (match-beginning 0))
    (aref outline-minor-faces
          ;; If we depended on `bicycle', then we could use:
          ;; (% (- (bicycle--level) (bicycle--top-level)) ...)
          (% (- (outline-minor-faces--level)
                (or outline-minor-faces--top-level
                    (setq outline-minor-faces--top-level
                          (save-excursion
                            (goto-char (point-min))
                            (outline-minor-faces--level)))))
             (length outline-minor-faces)))))

;;;###autoload
(defun outline-minor-faces-add-font-lock-keywords ()
  (ignore-errors
    (font-lock-add-keywords nil (outline-minor-faces--font-lock-keywords) t)
    (save-restriction
      (widen)
      (font-lock-flush)
      (font-lock-ensure))))

;;; _
(provide 'outline-minor-faces)
;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; outline-minor-faces.el ends here
