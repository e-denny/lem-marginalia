(in-package :lem-marginalia)

;;; ---------------------------------------------------------------------------
;;; Marginalia-style annotations in the other prompts
;;; ---------------------------------------------------------------------------
;;;
;;; Emacs' marginalia decides *which* annotation a prompt gets from its class of
;;; candidate: the completion metadata's category, refined by a list of
;;; classifiers (marginalia-classifiers) that look at the completing command, the
;;; candidate table and the minibuffer prompt (marginalia-prompt-categories, an
;;; alist of regexps to categories).  Lem has no completion metadata: a prompt is
;;; a function call with a completion function and a prompt string.  So the
;;; classifier here matches the prompt string, which is the closest equivalent of
;;; marginalia-prompt-categories, and the annotators are looked up in
;;; *PROMPT-ANNOTATORS* -- the equivalent of marginalia-annotators.
;;;
;;; The prompt strings are matched with SEARCH rather than with regexps: Lem has
;;; no regexp engine of its own, and the strings being matched are fixed ones
;;; from the commands that prompt ("Variable: ", "load library: ", ...).
;;;
;;; The prompts that take a plain string list (all of them are prompt-for-string
;;; calls) are annotated by an :around method on %PROMPT-FOR-LINE, which wraps
;;; the completion function the caller passed.  Annotators therefore receive the
;;; candidates as strings and return completion items; MARGINALIA-PROMPT-ITEM
;;; gives them the prompt's input range, so Tab and Return replace the input the
;;; way they do in M-x.
;;;
;;; What is annotated, and why the rest of Emacs' marginalia has no counterpart
;;; here:
;;;
;;;   variable  describe-lem-variable, "Enter Variable: " -- symbol class, value
;;;             and docstring, Emacs' marginalia-annotate-variable fields.
;;;   library   load-library and site-init, "library: " / "Package:" -- whether
;;;             the ASDF system is loaded, its description and its directory
;;;             (marginalia-annotate-library).
;;;   theme     load-theme, "Color theme: " -- whether it is the current theme
;;;             and its parent (marginalia-annotate-theme, minus the file, which
;;;             Lem does not keep per theme).
;;;   command   apropos-command / describe-command, "Apropos: " -- the same
;;;             docstring the M-x annotator shows, without a keybinding column,
;;;             because Lem's apropos completes over bare command names.
;;;
;;; Bookmarks are not annotated: Emacs' marginalia-annotate-bookmark prints the
;;; type, the file and the text before and after the position, and Lem's
;;; bookmark struct holds only a name, a filename and a position
;;; (extensions/bookmark/bookmark.lisp:80-83), with the file name already in the
;;; candidate's :detail.  Symbols in language modes are not annotated either:
;;; their docs live behind the Lisp connection, so a docstring column would cost
;;; one round trip per candidate.  Encodings (prompt-for-encodings, "Encodings: ")
;;; are not annotated either: Lem keeps no description per encoding -- which is
;;; what marginalia-annotate-coding-system shows -- no per-buffer external
;;; format to mark, and the default is :DETECT-ENCODING, so a "default" column
;;; would be empty in every prompt.

(defvar *prompt-annotators*
  '(("Apropos:" . marginalia-annotate-command-names)
    ("Variable:" . marginalia-annotate-variable-names)
    ("library:" . marginalia-annotate-library-names)
    ("Color theme:" . marginalia-annotate-theme-names))
  "Alist of prompt substring to the function that annotates its candidates.
Each function takes the candidate strings the prompt's completion function
returned and returns completion items, built with MARGINALIA-PROMPT-ITEM.
Matched case-insensitively with SEARCH against the prompt string, so a prompt
can be added by pushing a (SUBSTRING . FUNCTION) pair here.")

(defun marginalia-annotator-for-prompt (prompt)
  "The annotator for PROMPT's candidates, or NIL."
  (when (and prompt (stringp prompt))
    (let ((prompt (string-downcase prompt)))
      (cdr (assoc-if (lambda (needle) (search (string-downcase needle) prompt))
                     *prompt-annotators*)))))

(defun marginalia-annotate-candidates (annotator candidates)
  "CANDIDATES (from a prompt) annotated by ANNOTATOR.
Only plain strings are annotated; a prompt whose completion function already
builds items is left alone."
  (if (every #'stringp candidates)
      (funcall annotator candidates)
      candidates))

(defmethod lem-core::%prompt-for-line :around (prompt-string &rest args)
  "Annotate the candidates of a prompt whose text names an annotator.
The completion function the caller passes is wrapped, so prompting, matching
and history keep working exactly as before; only the items the prompt lists
gain a :detail.  This is the classifier."
  (let ((annotator (and (getf args :completion-function)
                        (marginalia-annotator-for-prompt prompt-string))))
    (if (null annotator)
        (apply #'call-next-method prompt-string args)
        (let ((args (copy-list args))
              (producer (getf args :completion-function)))
          (setf (getf args :completion-function)
                (lambda (string)
                  (marginalia-annotate-candidates
                   annotator (funcall producer string))))
          (apply #'call-next-method prompt-string args)))))

;;; Variables.
;;;
;;; Emacs prints the symbol class ("defvar"), the value truncated to half a
;;; field, and the docstring.  Lem's candidates come from LIST-ALL-LEM-VARIABLES
;;; (src/commands/help.lisp), which lists editor variables and LEM-package
;;; specials, so the class is "editor" or "variable", and the value is read the
;;; way DESCRIBE-LEM-VARIABLE reads it: through VARIABLE-VALUE for an editor
;;; variable, through SYMBOL-VALUE for a special.

(defun marginalia-variable-editor-p (symbol)
  "True when SYMBOL names an editor variable (define-editor-variable)."
  (lem:editor-variable-p (get symbol 'editor-variable)))

(defun marginalia-variable-value-string (symbol)
  "SYMBOL's value as a string, or \"\" when it cannot be read.
Bound like a printed value rather than like a data structure: a value can be a
keymap or an alist, and the column only needs enough of it to be recognisable."
  (let ((*print-length* 12)
        (*print-level* 2)
        (*print-lines* 2))
    (handler-case
        (let ((value (if (marginalia-variable-editor-p symbol)
                         (lem:variable-value symbol)
                         (symbol-value symbol))))
          (cond ((null value) "nil")
                ((eq value t) "t")
                (t (format nil "~s" value))))
      (error () ""))))

(defun marginalia-variable-row (name)
  "CLASS, VALUE and DOC of the variable named NAME, as three strings."
  (let ((symbol (ignore-errors (read-from-string name))))
    (if (not (and symbol (symbolp symbol)))
        (values "" "" "")
        (let ((editor (marginalia-variable-editor-p symbol)))
          (values (cond (editor "editor")
                        ((boundp symbol) "variable")
                        (t "unbound"))
                  ;; An editor variable keeps its value in the editor-variable
                  ;; object, not in the symbol's value cell, so an unbound
                  ;; editor variable still has one to show.
                  (if (or editor (boundp symbol))
                      (marginalia-variable-value-string symbol)
                      "")
                  (or (marginalia-first-line
                       (ignore-errors
                         (if editor
                             (lem:variable-documentation symbol)
                             (documentation symbol 'variable))))
                      ""))))))

(defun marginalia-join-fields (fields)
  "FIELDS joined with two spaces, empty ones left out."
  (format nil "~{~a~^  ~}" (remove "" fields :test #'string=)))

(defun marginalia-annotate-variable-names (names)
  "NAMES of variables, annotated with class, value and docstring.
The fields are not padded, which is how Emacs' marginalia-annotate-variable lays
them out: a padded value column costs the docstring sixteen columns even when
every value in the list is two characters long, and the label column -- which
carries the package name in Lem (lem-trans:*trans-popup-style*) -- is already
the widest fixed column of the row.  The class column is shown only when the
candidates disagree about it, because a column of the word variable repeated
down the whole popup says nothing about any single one of them."
  (let* ((max-label (reduce #'max names :key #'length :initial-value 0))
         (budget (marginalia-detail-budget max-label))
         (rows (mapcar (lambda (name)
                         (cons name (multiple-value-list
                                     (marginalia-variable-row name))))
                       names))
         (classes (remove-duplicates (mapcar #'second rows) :test #'string=))
         (class-width (and (cdr classes)
                           (reduce #'max classes :key #'length :initial-value 0)))
         ;; A value is recognisable from its first characters and the docstring
         ;; is what suffers when the value is long, so it is capped at 16.
         (value-width (max 8 (min 16
                                 (reduce (lambda (width row)
                                           (max width (length (third row))))
                                         rows :initial-value 0)
                                 (- budget (or class-width 0) 16)))))
    (loop :for (name . fields) :in rows
          :collect (destructuring-bind (class value doc) fields
                     (let* ((budget (marginalia-fit-budget max-label name))
                            (pieces (remove-if (lambda (piece)
                                                 (or (null piece)
                                                     (string= piece "")))
                                               (list (and class-width
                                                          (format nil "~va"
                                                                  class-width class))
                                                     (marginalia-truncate value value-width))))
                            (prefix (marginalia-join-fields pieces))
                            (doc-width (max 0 (- budget (length prefix)
                                                  (if pieces 2 0))))
                            (detail (marginalia-join-fields
                                     (append (when pieces (list prefix))
                                             (list (marginalia-truncate doc doc-width))))))
                       (marginalia-prompt-item name detail))))))

;;; Libraries.
;;;
;;; PROMPT-FOR-LIBRARY (src/prompt.lisp:169-190) completes over the LEM-* ASDF
;;; systems, with the "lem-" prefix stripped, so a candidate is a system name.
;;; Emacs' marginalia-annotate-library shows "Loaded", the one-line summary from
;;; the file header and the directory; the ASDF equivalents are
;;; ALREADY-LOADED-SYSTEMS, SYSTEM-DESCRIPTION and SYSTEM-SOURCE-DIRECTORY.

(defconstant +library-loaded-width+ 6
  "Width of the \"Loaded\" column of a library annotation.")

(defun marginalia-library-system (name)
  "The ASDF system a library candidate NAME names, or NIL."
  (ignore-errors (asdf:find-system (format nil "lem-~a" name) nil)))

(defun marginalia-library-fields (name loaded)
  "LOADED marker, description and directory of the library NAME."
  (let ((system (marginalia-library-system name)))
    (values (if (and system (member (asdf:component-name system) loaded
                                    :test #'string=))
                "Loaded" "")
            (or (ignore-errors (asdf:system-description system)) "")
            (let ((directory (and system
                                  (ignore-errors (asdf:system-source-directory system)))))
              (if directory
                  (enough-namestring directory (user-homedir-pathname))
                  "")))))

(defun marginalia-annotate-library-names (names)
  "NAMES of LEM libraries, annotated with loaded state, description and directory."
  (let* ((loaded (ignore-errors (asdf:already-loaded-systems)))
         (max-label (reduce #'max names :key #'length :initial-value 0))
         (budget (marginalia-detail-budget max-label))
         (rows (mapcar (lambda (name)
                         (cons name (multiple-value-list
                                     (marginalia-library-fields name loaded))))
                       names))
         (description-width (max 0 (floor (- budget 8) 2))))
    (loop :for (name . fields) :in rows
          :collect (destructuring-bind (loaded-p description directory) fields
                     (let ((budget (marginalia-fit-budget max-label name)))
                       (marginalia-prompt-item
                        name
                        (string-right-trim
                         " "
                         (format nil "~va  ~a  ~a"
                                 +library-loaded-width+ loaded-p
                                 (marginalia-truncate description description-width)
                                 (marginalia-truncate-tail
                                  directory (- budget +library-loaded-width+ 4
                                               description-width))))))))))

;;; Themes.
;;;
;;; LOAD-THEME (src/color-theme.lisp:89) completes over ALL-COLOR-THEMES, the
;;; names in *COLOR-THEMES*.  Emacs' marginalia-annotate-theme shows the theme's
;;; summary and its file; Lem themes have neither, so the columns are the ones it
;;; does have: whether the theme is current, and the theme it inherits from.

(defun marginalia-annotate-theme-names (names)
  "NAMES of color themes, annotated with the current theme marker and the parent."
  (let ((current (ignore-errors (current-theme))))
    (loop :for name :in names
          :for theme := (ignore-errors (lem:find-color-theme name))
          :for parent := (and theme
                              (ignore-errors (lem-core::color-theme-parent theme)))
          :collect (marginalia-prompt-item
                    name
                    (format nil "~a~@[  parent ~a~]"
                            (if (and current (string= current name)) "current" "")
                            parent)))))

;;; Commands outside M-x.
;;;
;;; APROPOS-COMMAND and its alias DESCRIBE-COMMAND (src/commands/help.lisp:168)
;;; complete over ALL-COMMAND-NAMES and then print the full documentation of each
;;; match.  Emacs' marginalia treats M-x, apropos and where-is as the command
;;; category, so the candidate gets the same docstring; there is no keybinding
;;; column, because the candidate is a bare name.  Emacs' command parameter is
;;; `marginalia-command-categories', the alist that says which commands complete
;;; over which category -- here it is the prompt string that says so.

(defun marginalia-annotate-command-names (names)
  "NAMES of commands, annotated with the first line of their docstring."
  (let* ((limit lem/completion-mode::*limit-number-of-items*)
         (shown (if (and limit (< limit (length names)))
                    (subseq names 0 limit)
                    names))
         (max-label (reduce #'max shown :key #'length :initial-value 0))
         (annotated
           (loop :for name :in shown
                 :for doc := (marginalia-docstring name)
                 :collect (marginalia-prompt-item
                           name
                           (marginalia-truncate
                            (or doc "") (marginalia-fit-budget max-label name))))))
    (if (eq shown names) annotated (append annotated (nthcdr limit names)))))
