(in-package :lem-marginalia)

;;; ---------------------------------------------------------------------------
;;; Marginalia-style annotations in M-x
;;; ---------------------------------------------------------------------------
;;;
;;; Emacs' marginalia shows the first line of each command's docstring next to
;;; the command name in M-x -- the same text M-x describe-function prints.
;;; lem already has the plumbing: a completion item carries a :detail string
;;; (src/ext/completion-mode.lisp:52-56) which lem's own
;;; PROMPT-COMMAND-COMPLETION fills with the command's keybindings
;;; (src/ext/prompt-window.lisp:486-518); apply-print-spec then prints it after
;;; the label column in the dim DETAIL-ATTRIBUTE
;;; (src/ext/completion-mode.lisp:152-160).
;;;
;;; :detail is display-only: selecting a candidate inserts its :label, and
;;; narrowing-down takes the common prefix of :labels, so annotating items
;;; cannot change which command runs.  The docstring is read exactly the way
;;; describe-command reads it (src/commands/help.lisp:169-177):
;;; (documentation (command-name command) 'function).
;;;
;;; About 650 of the 1081 commands in a fully loaded image have no docstring
;;; (mostly extensions), so those keep their keybinding column and show nothing
;;; after it -- marginalia does the same for undocumented functions.
;;;
;;; The annotation is applied by MARGINALIA-COMMAND-COMPLETION, which INSTALL
;;; sets as *prompt-command-completion-function* on top of LEM-ORDERLESS's
;;; matching, so every M-x path goes through it (single token, orderless tokens,
;;; and the :candidates lists that other commands pass to prompt-for-command).
;;; It runs after matching, on the candidates that will really be shown, because
;;; the column widths are computed from them; annotating all 1081 commands would
;;; size the description from the longest command name in the image and leave
;;; ~20 usable columns.

(defvar *marginalia-key-column* 12
  "Minimum width of the right-aligned keybinding column that precedes the
command description. Widened when the current candidates carry longer ones.")

(defvar *marginalia-description-width* 60
  "Longest description, in characters. Shortened when the candidates have long
command names, so that no row can push the popup past the frame edge (the
popup is as wide as the prompt, which fills the frame).")

(defun marginalia-collapse-whitespace (string)
  "STRING with each run of spaces/tabs turned into one space."
  (with-output-to-string (s)
    (let ((pending nil))
      (loop :for c :across string
            :do (if (member c '(#\Space #\Tab))
                    (setf pending t)
                    (progn (when pending (write-char #\Space s))
                           (setf pending nil)
                           (write-char c s)))))))

(defun marginalia-truncate (string width)
  "STRING cut at a word boundary to at most WIDTH characters, with an ellipsis."
  (if (<= (length string) width)
      string
      (let* ((cut (subseq string 0 (1- width)))
             (space (position #\Space cut :from-end t)))
        (concatenate 'string
                     (if (and space (> space (floor width 2)))
                         (subseq cut 0 space)
                         (string-right-trim " " cut))
                     "…"))))

(defun marginalia-docstring (name)
  "First non-empty line of the docstring of the command named NAME, or NIL."
  (let* ((command (lem:find-command name))
         (doc (and command
                   (documentation (lem:command-name command) 'function))))
    (when doc
      (loop :for line :in (uiop:split-string doc :separator '(#\Newline))
            :for text := (marginalia-collapse-whitespace
                          (string-trim '(#\Space #\Tab #\Return) line))
            :unless (string= text "")
              :do (return text)))))

(defun marginalia-first-keybinding (detail)
  "First binding of a keybinding list DETAIL (\"C-x C-f, F5\"), or \"\"."
  (let ((end (search ", " detail)))
    (if end (subseq detail 0 end) detail)))

(defun marginalia-copy-item (item detail)
  "ITEM with its :detail replaced by DETAIL (the other slots preserved)."
  (lem/completion-mode:make-completion-item
   :label (lem/completion-mode:completion-item-label item)
   :detail detail
   :chunks (lem/completion-mode::completion-item-chunks item)
   :start (lem/completion-mode::completion-item-start item)
   :end (lem/completion-mode::completion-item-end item)
   :focus-action (lem/completion-mode::completion-item-focus-action item)))

(defun completion-popup-width ()
  "Width in characters available to the completion popup.
LEM-VERTICO caps the prompt at *PROMPT-MAX-WIDTH*; when it is not loaded the
frame's width is the only limit."
  (let* ((vertico (find-package :lem-vertico))
         (symbol (and vertico (find-symbol "*PROMPT-MAX-WIDTH*" vertico)))
         (cap (and symbol (boundp symbol) (symbol-value symbol))))
    (min (lem:display-width) (or cap (lem:display-width)))))

(defun marginalia-annotate-shown-command-items (items)
  "ITEMS with each command's docstring appended after its keybindings.
The keybinding column is right-aligned and the description column starts at
the same screen column on every row, the way marginalia aligns its fields."
  (let* ((max-label
           (reduce (lambda (width item)
                     (max width (length (lem/completion-mode:completion-item-label item))))
                   items :initial-value 0))
         (key-column
           (reduce (lambda (width item)
                     (max width (length (marginalia-first-keybinding
                                         (lem/completion-mode:completion-item-detail item)))))
                   items :initial-value *marginalia-key-column*))
         ;; apply-print-spec puts one space, the label padded to max-label + 1,
         ;; two spaces, the detail and one trailing space on the row, so the
         ;; popup's width minus those fixed columns is what is left for the
         ;; description (the -2 keeps it inside the border).  The popup is no
         ;; wider than the frame, and no wider than lem-vertico's cap when that
         ;; system is loaded, so that is the width to measure against.
         (popup-width (completion-popup-width))
         (description-width
           (max 20 (min *marginalia-description-width*
                        (- popup-width 8 max-label key-column)))))
    (mapcar (lambda (item)
              (alexandria:if-let (description
                                  (marginalia-docstring
                                   (lem/completion-mode:completion-item-label item)))
                (marginalia-copy-item
                 item
                 (format nil "~va  ~a"
                         key-column
                         (marginalia-first-keybinding
                          (lem/completion-mode:completion-item-detail item))
                         (marginalia-truncate description description-width)))
                item))
            items)))

;;; Only the candidates that will be on screen matter for the column widths,
;;; and completion-mode keeps just the first *limit-number-of-items* of them
;;; (src/ext/completion-mode.lisp:302-312, applied before *completion-reverse*
;;; flips the list).  Annotating that prefix keeps the description column as
;;; wide as the popup can afford instead of sizing it from all 1081 commands.

(defun marginalia-annotate-command-items (items)
  "ITEMS with each command's docstring appended after its keybindings."
  (let* ((limit lem/completion-mode::*limit-number-of-items*)
         (shown (if (and limit (< limit (length items)))
                    (subseq items 0 limit)
                    items))
         (annotated (marginalia-annotate-shown-command-items shown)))
    (if (eq shown items)
        annotated
        (append annotated (nthcdr (length shown) items)))))

;;; Entry point.
;;;
;;; The annotation is installed by wrapping LEM-ORDERLESS's completion function
;;; rather than by replacing *PROMPT-COMMAND-COMPLETION-FUNCTION*: the variable
;;; keeps pointing at ORDERLESS-COMMAND-COMPLETION, so whichever of the two
;;; systems is reloaded last cannot silently unhook the other.

(defvar *original-orderless-command-completion* nil
  "The unwrapped LEM-ORDERLESS:ORDERLESS-COMMAND-COMPLETION, captured on the
first INSTALL so that reloading replaces the wrapper instead of stacking it.")

(defun install ()
  "Annotate M-x candidates with this system's descriptions."
  (setf *original-orderless-command-completion*
        (or *original-orderless-command-completion*
            (symbol-function 'lem-orderless:orderless-command-completion)))
  (setf (symbol-function 'lem-orderless:orderless-command-completion)
        (lambda (string &key candidates)
          (marginalia-annotate-command-items
           (funcall *original-orderless-command-completion*
                    string :candidates candidates))))
  (values))

(install)
