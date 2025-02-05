;;; elquery.el --- The HTML library for elisp. -*- lexical-binding: t -*-

;; Copyright 2017 Adam Niederer

;; Author: Adam Niederer
;; Maintainer: Adam Niederer
;; Created: 19 Feb 2017

;; Keywords: html hypermedia tools webscale
;; Package-Version: 20180917.2217
;; Homepage: https://github.com/AdamNiederer/elquery
;; Version: 0.1.0
;; Package-Requires: ((emacs "25.1") (s "1.11.0") (dash "2.13.0"))

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;

;;; Code:

(require 's)
(require 'dash)
(require 'cl-lib)
(require 'subr-x)

;; Functions to eventually break out into a seperate tree library
(defun elquery-tree-remove-if (pred tree)
  "Remove all elements satisfying PRED from TREE.
This function preserves the structure and order of the tree."
  (if (not (listp tree)) tree
    (thread-last tree
      (--remove (and (not (listp it)) (funcall pred it)))
      (--map (if (and (listp it) (not (-cons-pair? it)))
                 (elquery-tree-remove-if pred it)
               it)))))

(defun elquery-tree-remove-if-not (pred tree)
  "Remove all elements not satisfying PRED from TREE.
This function preserves the structure and order of the tree."
  (elquery-tree-remove-if (lambda (e) (not (funcall pred e))) tree))

(defun elquery-tree-flatten (tree)
  "Return TREE without any nesting.
This does not preserve the order of the elements."
  ;; TODO: elquery-tree-flatten-inorder, elquery-tree-flatten-postorder, elquery-tree-flatten-preorder
  (let ((ret nil))
    (dolist (el tree ret)
      (if (or (not (listp el)) (elquery--alistp el))
          (setq ret (cons el ret))
        (setq ret (append (elquery-tree-flatten el) ret))))))

(defun elquery-tree-flatten-until (pred tree)
  "Flatten elements not satsifying PRED in TREE.
This does not preserve the order of the elements."
  (let ((ret nil))
    (dolist (el tree ret)
      (if (or (not (listp el)) (elquery--alistp el) (funcall pred el))
          (setq ret (cons el ret))
        (setq ret (append (elquery-tree-flatten-until pred el) ret))))))

;; Functions to eventually upstream into Dash
(defun elquery--alistp (list)
  "Return whether LIST is an alist."
  (if (or (not (listp list)) (-cons-pair? list)) nil
    (--reduce (and acc (-cons-pair? it)) (cons t list))))

(defun elquery--alist-to-plist (list)
  "Convert alist LIST to a plist, preserving all key-value relationships."
  (--reduce (append acc (list (elquery--to-kw (car it))) (list (cdr it)))
            (cons '() list)))

(defun elquery--sym-to-kw (sym)
  "Convert symbol SYM to a keyword."
  (intern (concat ":" (prin1-to-string sym))))

(defun elquery--kw-to-string (kw)
  "Convert keyword KW to a string."
  (substring (prin1-to-string kw) 1))

(defun elquery--kw-to-sym (kw)
  "Convert keyword KW to a symbol."
  (make-symbol (substring (prin1-to-string kw) 1)))

(defun elquery--to-kw (obj)
  "Convert OBJ to a keyword."
  (if (keywordp obj) obj
    (elquery--sym-to-kw (if (symbolp obj) obj
                          (make-symbol (if (stringp obj) obj
                                         (prin1-to-string obj)))))))

(defun elquery--plist-set! (list kw val)
  "In LIST, destructively set KW to VAL."
  ;; TODO: Does plist-put do everything this function does?
  (let ((ptr list))
    (while (and (cdr ptr) (not (equal (car ptr) kw)))
      (setq ptr (cdr ptr)))
    (if (cdr ptr)
        (setcar (cdr ptr) val)
      (setcdr ptr (list kw))
      (setcdr (cdr ptr) (list val)))))

(defun elquery--plist-remove-if (pred list)
  "Return a copy of LIST with all keys satisfying PRED removed."
  (let ((ignore-next nil)
        (remove-next nil))
    (--remove (cond (remove-next (progn (setq remove-next nil) t))
                    (ignore-next (progn (setq ignore-next nil) nil))
                    ((funcall pred it) (progn (setq remove-next t) t))
                    (t (progn (setq ignore-next t) nil)))
              list)))

(defun elquery--plist-map (fn list)
  "Apply FN to all key-value pairs in LIST, a list half as long as the original."
  (if (null list) nil
    (cons (funcall fn (car list) (cadr list)) (elquery--plist-map fn (cddr list)))))

(defun elquery--plist-keys (list)
  "Return a list of keys from plist LIST."
  (let ((i 0))
    (--remove (prog1 (equal (% i 2) 1)
                (setq i (1+ i)))
              list)))

(defun elquery--plist-equal (a b &optional keys)
  "Return whether plists A and B are equal in content.
If KEYS is supplied, only test keys from that list."
  (--reduce (and acc (equal (plist-get a it) (plist-get b it)))
            (cons t (or keys (-union (elquery--plist-keys a) (elquery--plist-keys b))))))

(defun elquery--plist-subset? (a b &optional keys)
  "Return whether plist A is a subset of plist B are equal in content.
If KEYS is supplied, only test keys from that list."
  (--reduce (and acc (equal (plist-get a it) (plist-get b it)))
            (cons t (or keys (-union (elquery--plist-keys a) (elquery--plist-keys b))))))

(defun elquery--subset? (sub set)
  "Return whether the elements of SUB is a subset of the elements of SET."
  (--reduce (and acc (member it set)) (cons t sub)))

;; Functions to eventually upstream into s
(defun elquery--whitespace? (s)
  "Return whether S consists solely of whitespace characters."
  (and (stringp s) (s-matches-p "^[[:space:]]*$" s)))

;; Predicates specific to elquery
(defun elquery-nodep (obj)
  "Return whether OBJ is a DOM element."
  (member :el obj))

(defun elquery-elp (obj)
  "Return whether OBJ is a DOM element and is not a text node."
  (plist-get obj :el))

(defun elquery-textp (obj)
  "Return whether OBJ is a text node."
  (and (elquery-nodep obj) (not (elquery-elp obj))))

;; Accessor Aliases on DOM nodes
(defun elquery-props (node)
  "Return a list of NODE's properties (id, class, data*, etc)."
  (plist-get node :props))

(defun elquery-attrs (node)
  "Return a list of NODE's properies, without its classes and id."
  (elquery--plist-remove-if (lambda (it) (member it '(:id :class)))
                            (elquery-props node)))

(cl-defun elquery-children (node &key include-empty)
  "Return a list of the children of NODE.

If INCLUDE-EMPTY is not nil, also consider empty text nodes."
  (if include-empty (plist-get node :children)
    (-filter (lambda (el) (or (elquery-elp el)
                         (not (string-empty-p (elquery-text el)))))
             (plist-get node :children))))

(cl-defun elquery-next-children (node &key include-empty)
  "Return a list of children of NODE with their children removed.

If INCLUDE-EMPTY is not nil, also consider empty text nodes."
  (--map (append '(:children nil) it)
         (elquery-children node :include-empty include-empty)))

(cl-defun elquery-siblings (node &key include-empty)
  "Return a list of NODE's siblings, including NODE.

If INCLUDE-EMPTY is not nil, also consider empty text nodes."
  (elquery-children (elquery-parent node) :include-empty include-empty))

(cl-defun elquery-next-sibling (node &key include-empty)
  "Return the sibling immediately after NODE.

If INCLUDE-EMPTY is not nil, also consider empty text nodes."
  (let ((siblings (elquery-siblings node :include-empty include-empty)))
    (when (-find-index (-partial #'eq node) siblings)
      (nth (1+ (-find-index (-partial #'eq node) siblings)) siblings))))

(defun elquery-prop (node prop &optional val)
  "In NODE, return the value of PROP.
If VAL is supplied, destructively set PROP to VAL."
  (let ((props (elquery-props node)))
    (when val
      (elquery--plist-set! props (elquery--to-kw prop) val))
    (plist-get props (elquery--to-kw prop))))

(defun elquery-rm-prop (node prop)
  "In NODE, destructively remove PROP."
  (elquery--plist-set! node :props (--remove (equal (car it) prop)
                                             (elquery-props node))))

(defun elquery-parent (node)
  "Return the parent of NODE."
  (plist-get node :parent))

(defun elquery-el (node)
  "Return NODE's element name (e.g. body, div, span)."
  (plist-get node :el))

(defun elquery-text (node)
  "Return the text content of NODE.
If there are multiple text nodes in NODE
\(e.g.  <h1>some text<span></span>more text</h1>), return the concatenation of
these text nodes"
  (plist-get node :text))

(defun elquery-classes (node)
  "Return a list of NODE's classes."
  (let ((classes (elquery-prop node :class)))
    (if (listp classes) classes
      (s-split " " classes))))

(defun elquery-class? (node class)
  "Return whether NODE has the class CLASS."
  (if (member class (elquery-classes node)) t nil))

(defun elquery-id (node)
  "Return the id of NODE."
  (elquery-prop node :id))

(defun elquery-data (node key &optional val)
  "Return the value of NODE's data- KEY property.
If VAL is supplied, destructively set NODE's data-KEY property to VAL"
  (if val
      (elquery-prop node (s-concat "data-" key) val)
    (elquery-prop node (s-concat "data-" key))))

(defun elquery-read-file (file)
  "Return the AST of the HTML file FILE as a plist."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((tree (libxml-parse-html-region (point-min) (point-max))))
      (thread-last tree
        (--tree-map (if (stringp it) (s-trim (s-collapse-whitespace it)) it))
        (elquery--parse-libxml-tree nil)))))

(defun elquery-read-string (string)
  "Return the AST of the HTML string STRING as a plist."
  (with-temp-buffer
    (set-buffer-multibyte nil) ; ref debbugs.gnu.org/cgi/bugreport.cgi?bug=31427
    (insert string)
    (let ((tree (libxml-parse-html-region (point-min) (point-max))))
      (thread-last tree
        (--tree-map (if (stringp it) (s-trim (s-collapse-whitespace it)) it))
        (elquery--parse-libxml-tree nil)))))

(defun elquery--parse-libxml-tree (parent tree)
  "Convert libxml's alist-heavy and position-dependant format to a plist format.
Additionally, remove some useless whitespace nodes, and recursively set nodes'
PARENTs via pointer bashing.
Argument TREE is the libxml tree to convert."
  (if (stringp tree)
      `(:el nil :text ,tree :children nil :parent ,parent)
    (let ((self (append (list :el (prin1-to-string (car tree)))
                        (list :text (--reduce (if (stringp it) (concat acc it) acc)
                                              (cons "" (cddr tree))))
                        (list :props (elquery--alist-to-plist (cl-second tree)))
                        (list :children nil)
                        (list :parent nil))))
      (elquery--plist-set! self :parent parent) ; We can't do functional stuff here because we need a circular list, which requires messing with pointers
      (elquery--plist-set! self :children (--map (elquery--parse-libxml-tree self it)
                                                 (cdr (cdr tree))))
      self)))

(defun elquery--intersects? (query tree)
  "Return whether QUERY matches the head element of TREE."
  (and tree
       (or (not (elquery-el query))
           (equal "*" (elquery-el query))
           (equal (elquery-el tree) (elquery-el query)))
       (or (not (elquery-classes query))
           (elquery--subset? (elquery-classes query) (elquery-classes tree)))
       (or (not (elquery-props query))
           (not (--remove (equal it :class) (elquery--plist-keys (elquery-props query))))
           (elquery--plist-equal (elquery-props query)
                                 (elquery-props tree)
                                 (--remove (equal it :class)
                                           (elquery--plist-keys (elquery-props query)))))))

(defconst elquery--el-re "^[A-Za-z0-9*\-]+")
(defconst elquery--classes-re "\\.\\([a-zA-Z0-9\-_]+\\)")
(defconst elquery--id-re "#\\([a-zA-Z0-9\-_]+\\)")
(defconst elquery--attr-re "\\[\\([A-z\-]+\\)=\\(.+?\\)\\]")
(defconst elquery--heirarchy-re (concat "^\\([^[:space:]]+\\)" ; Head of heirarchy tree
                                        "[[:space:]]*\\([>~+]?\\)[[:space:]]*" ; Relationship operator
                                        "\\(.+\\)?")) ; Rest of tree (recursively parsed)

(defun elquery--parse-intersection (string)
  "Return a plist representing a single intersection in the query STRING.
For example, span#kek.bur[foo=bar]"
  (let* ((el (car (s-match elquery--el-re string)))
         (attrs (elquery--alist-to-plist
                 (mapcar (lambda (match) (apply 'cons (cdr match)))
                         (s-match-strings-all elquery--attr-re string))))
         (id (cl-second (s-match elquery--id-re string)))
         (classes (mapcar 'cl-second (s-match-strings-all elquery--classes-re string))))
    (list :el el :props (append (if id `(:id ,id))
                                (if classes `(:class ,classes))
                                attrs))))

(defun elquery--rel-kw (string)
  "Return a readable keyword for the relationship operator STRING."
  (cond
   ((equal string ">") :next-child)
   ((equal string "+") :next-sibling)
   ((equal string "~") :sibling)
   (t :child)))

(defun elquery--kw-rel (kw)
  "Return a relationship operator for the keyword KW."
  (cond
   ((equal kw :next-child) ">")
   ((equal kw :next-sibling) "+")
   ((equal kw :sibling) "~")
   (t " ")))

(defun elquery--parse-heirarchy (string)
  "Return a plist representing a heirarchical structure in a query STRING.
For example, #foo .bar > #bur[name=baz] returns
\(:el nil :props (:id \"foo\") :rel :child :children
     (:el nil :props (:class \"bar\") :rel :next-child :children
          (:el nil :props (:id \"bur\" :name \"baz\") :rel :child :children
               nil)))"
  (let* ((match (s-match elquery--heirarchy-re (s-trim string)))
         (head (cl-second match))
         (rel (cl-third match))
         (rest (cl-fourth match)))
    (append (elquery--parse-intersection head)
            `(:rel ,(elquery--rel-kw rel)
                   :children ,(if rest (elquery--parse-heirarchy rest) nil)))))

(defun elquery--parse-union (string)
  "Return a list of plists representing the query STRING."
  (mapcar 'elquery--parse-heirarchy (s-split ", " string)))

(defun elquery--$-next (query tree)
  "For QUERY, Return a list of subtrees of TREE corresponding to :rel in QUERY."
  (cl-case (plist-get query :rel)
    (:next-child (elquery-next-children tree))
    (:next-sibling (list (elquery-next-sibling tree)))
    ;; TODO: Does returning the siblings INCLUDING the element cause
    ;; issues with selectors like el-type ~ el-type?
    (:sibling (elquery-siblings tree))
    (:child (elquery-children tree))))

(defun elquery--$-recurse? (query)
  "Return whether recursion until finding a matching element is allowed.
This is determined via the relationship operator :rel in QUERY."
  (equal (plist-get query :rel) :child))

(defun elquery--$ (query tree can-recurse)
  "For QUERY, return a subtree of TREE matching QUERY, or nil if none is found.
If CAN-RECURSE is set, continue down the tree until a matching element is found."
  (cond
   ;; If we're out of stuff to search, we can't do anything else
   ((equal tree nil) nil)
   ;; No children in the query, no searchable children in the tree, and a match
   ;; in the tree means we can return the leaf
   ((and (elquery--intersects? query tree)
         (not (elquery-children query))
         (or (not can-recurse)
             (not (elquery-children tree))))
    tree)
   ;; A match with children remaining in the query to find means we have to
   ;; recurse according to the query's heirarchy relationship
   ((and (elquery--intersects? query tree)
         (elquery-children query))
    (-non-nil (--map (elquery--$ (elquery-children query) it (elquery--$-recurse? query))
                     (elquery--$-next query tree))))
   ;; A match without children in the query will return the tree, but we must
   ;; still recurse to find any matching children in tree if we aren't looking
   ;; for siblings or next-children
   ((and can-recurse
         (elquery--intersects? query tree)
         (not (elquery-children query)))
    (append (list tree) (-non-nil (--map (elquery--$ query it t)
                                         (elquery-children tree)))))
   ;; No match and a recurse flag means we can continue down the tree and see if
   ;; we get any matches. If we do, collect them in a list
   (can-recurse
    (-non-nil (--map (elquery--$ query it t)
                     (elquery-children tree))))
   ;; No match and no allowed recursion means we can't do anything else
   (t nil)))

(defun elquery-$ (query-string tree)
  "Return a list of elements matching QUERY-STRING in the subtree of TREE."
  (let ((queries (elquery--parse-union query-string)))
    (elquery-tree-flatten-until #'elquery-nodep
                                (-non-nil (--map (elquery--$ it tree t) queries)))))

(defun elquery--write-props (node)
  "Return a string representing the properties of NODE."
  (let ((props (elquery-props node)))
    (if (not props) ""
      (s-concat " " (s-join " " (--map (format "%s=\"%s\""
                                               (elquery--kw-to-string it)
                                               (plist-get props it))
                                       (elquery--plist-keys props)))))))

(defun elquery--indent-insert (string depth whitespace?)
  "Insert the proper amount of indentation for STRING.
Inserts the product of based on `sgml-basic-offset' and DEPTH, then STRING, then
a newline.  If WHITESPACE? is nil, do not insert any indentation or newline."
  (insert (if whitespace? (s-repeat (* depth sgml-basic-offset) " ") "")
          string
          (if whitespace? "\n" "")))

(defun elquery--write (tree depth &optional whitespace?)
  "A recursive subroutine for `elquery-write'.
Inserts the HTML string representation of TREE into the current buffer with
depth DEPTH.  If WHITESPACE is provided, insert the appropriate amount of
whitespace as well."
  ;; TODO: Close singleton elements with no children (<input/> and friends)
  (if (not (elquery-el tree))
      (elquery--indent-insert (elquery-text tree) depth whitespace?)
    (elquery--indent-insert (format "<%s%s>" (elquery-el tree) (elquery--write-props tree)) depth whitespace?)
    (dolist (child (elquery-children tree))
      (elquery--write child (1+ depth) whitespace?))
    (elquery--indent-insert (format "</%s>" (elquery-el tree)) depth whitespace?)))

(defun elquery-write (tree &optional whitespace?)
  "Return an html string representing TREE.
If WHITESPACE? is non-nil, insert indentation and newlines according to
`sgml-basic-offset'."
  (with-temp-buffer
    (elquery--write tree 0 whitespace?)
    (buffer-string)))

(defun elquery-fmt (tree)
  "Return an html string representing the top level element of TREE."
  (if (not tree) "nil"
    (format "<%s%s>" (elquery-el tree) (elquery--write-props tree))))

(defun elquery--fmt-union (query)
  "Return a query string for the given query QUERY."
  (s-join ", " (-map 'elquery--fmt-heirarchy query)))

(defun elquery--fmt-intersection (query)
  "Return a query string for the given query intersection QUERY.
Always of the form el-name#id.class[key=val], with null elements omitted."
  (concat (or (elquery-el query) "")
          (and (elquery-id query) (concat "#" (elquery-id query)))
          (s-join "" (--map (concat "." it) (elquery-classes query)))
          (s-join "" (elquery--plist-map (lambda (a b)
                                           (format "[%s=%s]" (elquery--kw-to-string a) b))
                                         (elquery-attrs query)))))

(defalias 'elquery-pprint 'elquery--fmt-intersection)

(defun elquery--pad-operator (string)
  "Return a padded version of the inheritance operator STRING."
  (if (equal string " ") " "
    (s-concat " " string " ")))

(defun elquery--fmt-heirarchy (query)
  "Return a query string for the given query heirarchy QUERY."
  (if (null query) ""
    (s-concat (elquery--fmt-intersection query)
              (if (null (elquery-children query)) ""
                (s-concat (elquery--pad-operator (elquery--kw-rel (plist-get query :rel)))
                          (elquery--fmt-heirarchy (elquery-children query)))))))

(provide 'elquery)
;;; elquery.el ends here
