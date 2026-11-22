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

(defvar *marginalia-description-width* nil
  "Longest description, in characters, or NIL for all the room the row has left.
The popup box is *PROMPT-MAX-WIDTH* columns wide (120), and the label,
keybinding and separator columns come out of it, so the description fills what
is left instead of stopping at a fixed 60.  A number caps it below that.")

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
  "STRING cut to exactly WIDTH characters, with an ellipsis when it is longer.
A hard cut, like Emacs' truncate-string-to-width: the annotation has to fit a
fixed number of columns, and backing up to the previous word boundary gives
away a whole word of the little room there is."
  (cond ((<= width 0) "")
        ((<= (length string) width) string)
        (t (concatenate 'string (subseq string 0 (1- width)) "…"))))

(defun marginalia-truncate-tail (string width)
  "STRING cut to at most WIDTH characters from the right, with a leading ellipsis.
That is how a path is shortened: the end of it names the file, so it is the
beginning that goes, as with marginalia's negative :truncate widths."
  (cond ((<= (length string) width) string)
        ((< width 2) "")
        (t (concatenate 'string "…" (subseq string (- (length string) (1- width)))))))

(defun marginalia-first-line (doc)
  "First non-empty line of the docstring DOC with its whitespace collapsed."
  (when doc
    (loop :for line :in (uiop:split-string doc :separator '(#\Newline))
          :for text := (marginalia-collapse-whitespace
                        (string-trim '(#\Space #\Tab #\Return) line))
          :unless (string= text "")
            :do (return text))))

(defun marginalia-docstring (name)
  "First non-empty line of the docstring of the command named NAME, or NIL."
  (let* ((command (lem:find-command name))
         (doc (and command
                   (documentation (lem:command-name command) 'function))))
    (marginalia-first-line doc)))

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

;;; Room for a :detail, in characters.
;;;
;;; apply-print-spec puts one space, the label padded to max-label + 1, two
;;; spaces, the detail and one trailing space on the row, so a row is
;;; max-label + |detail| + 4 wide and the detail gets what the box has left of
;;; those columns.  The same 4 is what the command annotator leaves out of its
;;; description budget on top of the label and keybinding columns, so a full
;;; row ends at the right edge of the box instead of a couple of columns short.
;;;
;;; The label column is what really decides how much is left, and Lem pads it to
;;; the longest candidate on screen.  That is fine for command and buffer names
;;; and ruinous for the variable prompt, which completes over package-qualified
;;; names: one 72-character name pads every row to 72 and leaves a third of the
;;; box for the annotation.  So the label column is capped, here and in the
;;; renderer (see the :AROUND method below), and a row whose own label is longer
;;; than the cap simply starts its annotation after the label.

(defvar *marginalia-label-column* 40
  "Widest label column, in characters, or NIL to keep Lem's own width.
Lem pads the label column to the longest candidate on screen, so a single long
name takes the room of every row.")

(defun marginalia-label-width (max-label)
  "MAX-LABEL as the column actually used, capped by *MARGINALIA-LABEL-COLUMN*."
  (if *marginalia-label-column*
      (min max-label *marginalia-label-column*)
      max-label))

(defun marginalia-detail-budget (max-label)
  "Characters of :detail a row with a MAX-LABEL wide label column can hold."
  (max 10 (- (completion-popup-width) (marginalia-label-width max-label) 4)))

(defun marginalia-fit-budget (max-label label)
  "The :detail budget for LABEL in a list whose widest label is MAX-LABEL.
Same as MARGINALIA-DETAIL-BUDGET unless LABEL is wider than the cap: the
renderer then puts that row's detail after the label itself, with no padding,
so only what the label leaves is usable."
  (let ((cap *marginalia-label-column*))
    (min (marginalia-detail-budget max-label)
         (max 10 (- (completion-popup-width)
                    (min (1+ max-label)
                         (max (if cap (1+ cap) 0) (1+ (length label))))
                    3)))))

(defun marginalia-description-width (max-label key-column)
  "Longest description next to a MAX-LABEL label and KEY-COLUMN keybinding column.
Everything the row has left, capped by *MARGINALIA-DESCRIPTION-WIDTH* when the
knob is set to a number."
  (let ((available (- (completion-popup-width) 6
                      (marginalia-label-width max-label) key-column)))
    (max 20 (if *marginalia-description-width*
                (min *marginalia-description-width* available)
                available))))

;;; The renderer pads the label column to (1+ max-label), so it has to use the
;;; same cap the budgets above assume; otherwise a capped budget would be paired
;;; with an uncapped column and every row would come up short again.  The width
;;; is capped per row to (max cap (1+ label)), which is what keeps a long label
;;; from moving the insertion point back into itself -- MOVE-TO-COLUMN moves
;;; *backwards* when the column is already behind the point
;;; (src/buffer/internal/basic.lisp:361-380).

(defmethod lem/popup-menu:apply-print-spec :around
    ((print-spec lem/completion-mode::print-spec) point item)
  (let* ((label (lem/completion-mode:completion-item-label item))
         (width (lem/completion-mode::label-width print-spec))
         (capped (and *marginalia-label-column*
                      (min width
                           (max (1+ *marginalia-label-column*)
                                (1+ (length label)))))))
    (if (and capped (< capped width))
        (call-next-method (make-instance 'lem/completion-mode::print-spec
                                         :label-width capped)
                          point item)
        (call-next-method))))

(defun marginalia-prompt-item (label detail)
  "A completion item for LABEL with DETAIL that replaces the prompt's whole input.
The prompt functions that annotate plain strings (an apropos list, a variable
list) do not build completion items themselves -- open-prompt-completion turns
strings into items carrying the input range -- so an annotator has to do the
same or Tab and Return would insert at point instead of replacing the input."
  (with-point ((start (lem/prompt-window::current-prompt-start-point))
               (end (lem/prompt-window::current-prompt-start-point)))
    (lem/completion-mode:make-completion-item
     :label label
     :detail detail
     :start start
     :end (line-end end))))

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
         ;; description.  The popup is no wider than the frame, and no wider
         ;; than lem-vertico's cap when that system is loaded, so that is the
         ;; width to measure against -- the description takes everything the
         ;; label and keybinding columns leave of those 120 columns rather than
         ;; stopping at a fixed width.
         (description-width (marginalia-description-width max-label key-column)))
    (mapcar (lambda (item)
              (let ((label (lem/completion-mode:completion-item-label item)))
                (alexandria:if-let (description (marginalia-docstring label))
                  (marginalia-copy-item
                   item
                   (format nil "~va  ~a"
                           key-column
                           (marginalia-first-keybinding
                            (lem/completion-mode:completion-item-detail item))
                           (marginalia-truncate
                            description
                            ;; A command whose own name is wider than the
                            ;; label cap has no padding to spend, so its row
                            ;; gets only what is left after the name.
                            (min description-width
                                 (- (marginalia-fit-budget max-label label)
                                    key-column 2)))))
                  item)))
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

;;; Installation.
;;;
;;; The annotation is installed by wrapping LEM-ORDERLESS's completion function
;;; rather than by replacing *PROMPT-COMMAND-COMPLETION-FUNCTION*: the variable
;;; keeps pointing at ORDERLESS-COMMAND-COMPLETION, so whichever of the two
;;; systems is reloaded last cannot silently unhook the other.  INSTALL is the
;;; umbrella entry point (install.lisp); it calls this and the file annotator.

(defvar *original-orderless-command-completion* nil
  "The unwrapped LEM-ORDERLESS:ORDERLESS-COMMAND-COMPLETION, captured on the
first INSTALL so that reloading replaces the wrapper instead of stacking it.")

(defun install-command-annotations ()
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
