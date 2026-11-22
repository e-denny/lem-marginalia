(in-package :lem-marginalia)

;;; ---------------------------------------------------------------------------
;;; Marginalia-style annotations in buffer prompts (C-x b and friends)
;;; ---------------------------------------------------------------------------
;;;
;;; Emacs' marginalia annotates a buffer candidate with three fields
;;; (marginalia--buffer-status and marginalia--buffer-file in marginalia.el):
;;;
;;;   *--     4k  Fundamental  ~/.emacs.d/init.el
;;;   ---   128k  Emacs-Lisp   *scratch*
;;;
;;; The first three characters are mode-line %-constructs: %* is "*" for a
;;; modified buffer, "%" for a read-only one, "-" otherwise; %+ is the same but
;;; "@" for a buffer whose default-directory is remote; %@ is "@" for a remote
;;; directory and "-" otherwise.  Then the size in 7 columns (the %I construct,
;;; which prints file-size-human-readable), the major mode in 20, and the file
;;; name.  The sizes line up because they are right-aligned in a fixed width,
;;; and the mode name is what is left of 20 characters.
;;;
;;; Lem has no remote buffers to distinguish here, so the second and third
;;; characters repeat the first and are always "-": the flags still say whether
;;; the buffer is modified or read-only, which is the part that matters in a
;;; buffer list.  Sizes go through the same MARGINALIA-HUMAN-SIZE as the file
;;; annotator, so "4k" and "128k" read the same as in Emacs, and the age column
;;; of the file annotator has no counterpart: a buffer's modification time is
;;; not part of marginalia's buffer fields.
;;;
;;; The file column comes from BUFFER-FILENAME; a central panel that lists a
;;; directory (LEM/DIRECTORY-MODE) has no filename, so its directory is used
;;; instead, which is what marginalia does with dired buffers.  It is truncated
;;; from the left, because the end of a path is the part that names the file.
;;;
;;; The annotation replaces the :detail lem's own PROMPT-BUFFER-COMPLETION
;;; fills with the buffer's file name (src/ext/prompt-window.lisp:453-463), so
;;; every buffer prompt gains the other fields rather than a second line.
;;; :detail is display-only -- selecting a candidate inserts its :label and
;;; narrowing-down takes the common prefix of the labels -- so annotating
;;; cannot change which buffer is switched to.

(defconstant +buffer-status-width+ 3
  "Width of the modified/read-only/remote flags (mode-line %* %+ %@).")

(defconstant +buffer-size-width+ 7
  "Width of the right-aligned size field (the mode-line %I construct).")

(defvar *marginalia-buffer-mode-width* 20
  "Width of the major mode field.  Emacs' marginalia--buffer-status gives the
mode name 20 columns and truncates longer ones.")

(defun marginalia-buffer-status (buffer)
  "The three-character status marginalia prints for BUFFER.
Modified is \"*\", read-only is \"%\", neither is \"-\"; Lem has no remote
directories to mark, so the two remote positions are \"-\"."
  (let ((flag (cond ((buffer-modified-p buffer) #\*)
                    ((buffer-read-only-p buffer) #\%)
                    (t #\-))))
    (coerce (list flag flag #\-) 'string)))

(defun marginalia-buffer-size (buffer)
  "BUFFER's size in characters, the way the mode-line %I construct prints it.
Lem points are 1-based, so the end point of an N-character buffer is at
position N+1."
  (marginalia-human-size
   (max 0 (1- (lem:position-at-point (lem:buffer-end-point buffer))))))

(defun marginalia-buffer-mode (buffer)
  "BUFFER's major mode name, cut to *MARGINALIA-BUFFER-MODE-WIDTH*."
  (let ((name (ignore-errors (lem:mode-name (lem:buffer-major-mode buffer)))))
    (cond ((null name) "")
          ((<= (length name) *marginalia-buffer-mode-width*) name)
          (t (concatenate 'string
                          (subseq name 0 (1- *marginalia-buffer-mode-width*))
                          "…")))))

(defun marginalia-buffer-file (buffer)
  "The file or directory BUFFER stands for, or \"\".
Like marginalia--buffer-file, a buffer that lists a directory reports the
directory: LEM/DIRECTORY-MODE names such a buffer after the path it lists."
  (or (ignore-errors (lem:buffer-filename buffer))
      (let ((name (ignore-errors (lem:buffer-name buffer))))
        (and name
             (plusp (length name))
             (char= (char name 0) #\/)
             name))
      ""))

(defun marginalia-buffer-detail (buffer budget)
  "The marginalia annotation of BUFFER, at most BUDGET characters long."
  (let* ((fixed (+ +buffer-status-width+ 2 +buffer-size-width+ 2
                   *marginalia-buffer-mode-width* 2))
         (file (marginalia-buffer-file buffer)))
    (string-right-trim
     " "
     (format nil "~a  ~v@a  ~va  ~a"
             (marginalia-buffer-status buffer)
             +buffer-size-width+ (marginalia-buffer-size buffer)
             *marginalia-buffer-mode-width* (marginalia-buffer-mode buffer)
             (marginalia-truncate-tail file (max 0 (- budget fixed)))))))

(defun marginalia-annotate-shown-buffer-items (items)
  "ITEMS with each buffer's status, size, mode and file appended as its :detail."
  (let* ((max-label
           (reduce (lambda (width item)
                     (max width (length (lem/completion-mode:completion-item-label
                                         item))))
                   items :initial-value 0)))
    (mapcar (lambda (item)
              (let ((label (lem/completion-mode:completion-item-label item))
                    (buffer (ignore-errors
                             (lem:get-buffer
                              (lem/completion-mode:completion-item-label item)))))
                (if buffer
                    (marginalia-copy-item
                     item (marginalia-buffer-detail
                           buffer (marginalia-fit-budget max-label label)))
                    item)))
            items)))

(defun marginalia-annotate-buffer-items (items)
  "ITEMS from a buffer prompt, annotated with this system's buffer fields.
Only the candidates that can be on screen are annotated, the way the file and
command annotators do it: the column widths are computed from the shown rows,
and a buffer list of hundreds costs a few hundred lookups instead of one per
buffer in the editor."
  (let ((limit lem/completion-mode::*limit-number-of-items*))
    (if (and limit (< limit (length items)))
        (append (marginalia-annotate-shown-buffer-items (subseq items 0 limit))
                (nthcdr limit items))
        (marginalia-annotate-shown-buffer-items items))))

;;; Installation.
;;;
;;; Every buffer prompt goes through the function named by
;;; *PROMPT-BUFFER-COMPLETION-FUNCTION* (src/prompt.lisp:109-124), whether it is
;;; lem's own PROMPT-BUFFER-COMPLETION or LEM-ORDERLESS's
;;; ORDERLESS-BUFFER-COMPLETION, so that symbol is patched in place -- the same
;;; way the file annotator patches *PROMPT-FILE-COMPLETION-FUNCTION* -- and the
;;; variable keeps naming it.  The unwrapped producer is captured once per
;;; symbol, so reloading replaces the wrapper instead of stacking another one.

(defvar *buffer-completion-originals* (make-hash-table :test #'eq)
  "The unwrapped buffer producers, keyed by the symbol that names them.")

(defun marginalia-buffer-completion-producer ()
  "The symbol whose function produces the candidates of a buffer prompt, or NIL."
  (let ((current lem:*prompt-buffer-completion-function*))
    (and (symbolp current) current (fboundp current) current)))

(defun install-buffer-annotations ()
  "Annotate the candidates of every buffer prompt (C-x b and friends)."
  (alexandria:when-let (symbol (marginalia-buffer-completion-producer))
    (let ((original (or (gethash symbol *buffer-completion-originals*)
                        (setf (gethash symbol *buffer-completion-originals*)
                              (symbol-function symbol)))))
      (setf (symbol-function symbol)
            (lambda (string &rest args)
              (marginalia-annotate-buffer-items
               (apply original string args))))))
  (values))
