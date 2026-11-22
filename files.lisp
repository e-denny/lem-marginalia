(in-package :lem-marginalia)

;;; ---------------------------------------------------------------------------
;;; Marginalia-style annotations for file prompts (C-x C-f and friends)
;;; ---------------------------------------------------------------------------
;;;
;;; Emacs' marginalia annotates every candidate of a file prompt with the entry's
;;; permission bits, its size and its modification time:
;;;
;;;   drwxr-xr-x       4k     1d 3h ago
;;;   -rw-------     2.5k     1w 4d ago
;;;
;;; Those are three fields (marginalia--annotate-local-file in marginalia.el):
;;; the mode string, the size right-aligned in 7 characters, and the age
;;; right-aligned in 12, separated by two spaces.  The widths are what makes the
;;; rows line up, so they are reproduced here rather than computed from the
;;; candidates.  File sizes go through Emacs' file-size-human-readable, and ages
;;; through its seconds-to-string, so the numbers read the same in both editors:
;;; binary units with a decimal only below 10 units, and a two-unit relative age
;;; ("1d 3h ago") for entries younger than *MARGINALIA-MAX-RELATIVE-AGE*, an
;;; absolute date ("Aug 24 19:27", or "2025 Nov 10" in another year) above it.
;;;
;;; The attributes come from LSTAT, so a symbolic link shows its own mode
;;; ("lrwxrwxrwx") and the length of the path it names as its size, exactly as
;;; `ls -l' and marginalia print it.  Entries that cannot be read (a permission
;;; error, or a remote path -- SB-POSIX cannot see those) simply get no
;;; annotation, which is also what marginalia does.
;;;
;;; :detail is display-only (see marginalia.lisp), so annotating file candidates
;;; cannot change which file is opened: selecting an item inserts its :label.
;;;
;;; The annotation is colored field by field, and the permission string character
;;; by character, with the faces and colors Emacs' marginalia gives them: the
;;; permission flags are margified through marginalia--file-modes' pcase table
;;; (dir/link/read/write/exec/other/rare/none) and the size, date and owner
;;; fields carry marginalia-size, marginalia-date and marginalia-file-owner.
;;; Colors are the ones those faces resolve to in doom-one, the theme the
;;; screenshot this reproduces was taken in; they are plain :foreground values
;;; here, so swapping them for Lem theme keywords (:base0D etc.) or another
;;; palette is a one-line edit per role.

(defvar *marginalia-max-relative-age* (* 14 24 60 60)
  "Entries younger than this, in seconds, get a relative age (\"1d 3h ago\").
Older entries get an absolute date.  The same 14 days as Emacs'
marginalia-max-relative-age.")

(defconstant +unix-epoch+ (encode-universal-time 0 0 0 1 1 1970 0)
  "Universal time of the Unix epoch; SB-POSIX reports file times in seconds
since 1970, while DECODE-UNIVERSAL-TIME expects seconds since 1900.")

;;; Field formatting.

(defparameter *marginalia-months*
  #("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec")
  "Month abbreviations, as format-time-string prints them in the C locale.")

(defparameter *marginalia-size-suffixes*
  #("" "k" "M" "G" "T" "P" "E" "Z" "Y")
  "Unit suffixes, binary, as file-size-human-readable produces them.")

(defparameter *marginalia-time-units*
  '((31556952 . "Y") (2629746 . "M") (604800 . "w")
    (86400 . "d") (3600 . "h") (60 . "m") (1 . "s"))
  "Unit lengths in seconds, longest first, with their abbreviations.
Emacs' seconds-to-string uses the same average year (365.2425 days) and month
(30.436875 days), and rounds its second unit, which is why it prints
\"6d 24h\" for 604799 seconds.")

;;; Field widths.  marginalia--annotate-local-file asks for the size at :width -7
;;; and the age at :width -12, and marginalia-separator is two spaces, which is
;;; what makes the columns line up.

(defconstant +size-width+ 7)
(defconstant +age-width+ 12)
(defparameter *field-separator* "  "
  "marginalia-separator, the two spaces between the fields.")

;;; Colors.  These are the colors the faces marginalia-file-priv-* and friends
;;; resolve to in doom-one; see the header comment.

(define-attribute marginalia-file-mode-no-attribute (t :foreground "#5B6268"))
(define-attribute marginalia-file-mode-dir-attribute (t :foreground "#51afef"))
(define-attribute marginalia-file-mode-link-attribute (t :foreground "#a9a1e1"))
(define-attribute marginalia-file-mode-read-attribute (t :foreground "#ECBE7B"))
(define-attribute marginalia-file-mode-write-attribute (t :foreground "#ff6c6b"))
(define-attribute marginalia-file-mode-exec-attribute (t :foreground "#98be65"))
(define-attribute marginalia-file-mode-other-attribute (t :foreground "#c678dd"))
(define-attribute marginalia-file-mode-rare-attribute (t :foreground "#bbc2cf"))
(define-attribute marginalia-file-size-attribute (t :foreground "#a9a1e1"))
(define-attribute marginalia-file-age-attribute (t :foreground "#51afef"))
(define-attribute marginalia-file-owner-attribute (t :foreground "#51afef"))

(defun marginalia-human-size (bytes)
  "BYTES the way Emacs' file-size-human-readable prints them: binary units, and
one decimal only below 10 units when the fraction is not close to 0 or 1."
  (let ((value (coerce bytes 'double-float))
        (index 0))
    (loop :while (and (>= value 1024.0d0)
                      (< (1+ index) (length *marginalia-size-suffixes*)))
          :do (setf value (/ value 1024.0d0))
              (incf index))
    (let* ((suffix (aref *marginalia-size-suffixes* index))
           (fraction (- value (floor value)))
           (decimal (and (< value 10.0d0)
                         (<= 0.05d0 fraction)
                         (< fraction 0.95d0))))
      (if decimal
          (let ((tenths (round (* value 10))))
            (format nil "~d.~d~a"
                    (floor tenths 10)
                    (- tenths (* 10 (floor tenths 10)))
                    suffix))
          (format nil "~d~a" (round value) suffix)))))

(defun marginalia-permissions (mode)
  "MODE as the ten characters `ls -l' prints, e.g. \"drwxr-xr-x\"."
  (flet ((permission-bit (mask char) (if (logtest mode mask) char #\-))
         (exec (exec-mask special-mask special-char plain-special-char)
           ;; setuid/setgid/sticky replace the execute character.
           (cond ((and (logtest mode exec-mask) (logtest mode special-mask))
                  special-char)
                 ((logtest mode exec-mask) #\x)
                 ((logtest mode special-mask) plain-special-char)
                 (t #\-))))
    (coerce
     (list (let ((kind (logand mode sb-posix:s-ifmt)))
             (cond ((= kind sb-posix:s-ifdir) #\d)
                   ((= kind sb-posix:s-iflnk) #\l)
                   ((= kind sb-posix:s-ifchr) #\c)
                   ((= kind sb-posix:s-ifblk) #\b)
                   ((= kind sb-posix:s-ififo) #\p)
                   ((= kind sb-posix:s-ifsock) #\s)
                   (t #\-)))
           (permission-bit #o400 #\r) (permission-bit #o200 #\w)
           (exec #o100 #o4000 #\s #\S)
           (permission-bit #o40 #\r) (permission-bit #o20 #\w)
           (exec #o10 #o2000 #\s #\S)
           (permission-bit #o4 #\r) (permission-bit #o2 #\w)
           (exec #o1 #o1000 #\t #\T))
     'string)))

(defun marginalia-permission-attribute (char)
  "The attribute marginalia gives permission character CHAR.
This is marginalia--file-modes' pcase table: the type character and the nine
flag characters are colored the way the same characters are in Emacs."
  (case char
    (#\- 'marginalia-file-mode-no-attribute)
    (#\d 'marginalia-file-mode-dir-attribute)
    (#\l 'marginalia-file-mode-link-attribute)
    (#\r 'marginalia-file-mode-read-attribute)
    (#\w 'marginalia-file-mode-write-attribute)
    (#\x 'marginalia-file-mode-exec-attribute)
    ((#\s #\S #\t #\T) 'marginalia-file-mode-other-attribute)
    (otherwise 'marginalia-file-mode-rare-attribute)))

(defun marginalia-relative-age (seconds)
  "SECONDS the way (seconds-to-string SECONDS 'expanded 'abbrev) prints it: the
largest whole unit, followed by the next-smaller one when that rounds to at
least 1."
  (let ((seconds (max 0 (truncate seconds))))
    (loop :for (unit . name) :in *marginalia-time-units*
          :for index :from 0
          :when (>= seconds unit)
            :return (let* ((value (floor seconds unit))
                           (next (nth (1+ index) *marginalia-time-units*))
                           (sub (and next
                                     (round (- seconds (* value unit))
                                            (car next)))))
                      (if (and sub (plusp sub))
                          (format nil "~d~a ~d~a" value name sub (cdr next))
                          (format nil "~d~a" value name)))
          :finally (return "0s"))))

(defun marginalia-file-age (mtime)
  "MTIME (in seconds since 1970) formatted as marginalia's age column."
  (let* ((universal-time (+ mtime +unix-epoch+))
         (age (- (get-universal-time) universal-time)))
    (if (< age *marginalia-max-relative-age*)
        (concatenate 'string (marginalia-relative-age age) " ago")
        (multiple-value-bind (second minute hour date month year)
            (decode-universal-time universal-time)
          (declare (ignore second))
          (if (= year (nth-value 5 (decode-universal-time (get-universal-time))))
              (format nil "~a ~2,'0d ~2,'0d:~2,'0d"
                      (aref *marginalia-months* (1- month)) date hour minute)
              (format nil "~d ~a ~2,'0d"
                      year (aref *marginalia-months* (1- month)) date))))))

(defun marginalia-file-owner (stat)
  "The owner field marginalia appends for entries that are not ours, or NIL.
marginalia only prints \"user:group\" when either id differs from the current
one, so an ordinary home directory listing stays three columns wide."
  (let ((uid (sb-posix:stat-uid stat))
        (gid (sb-posix:stat-gid stat)))
    (unless (and (= uid (sb-posix:getuid))
                 (= gid (sb-posix:getgid)))
      (format nil "  ~a:~a"
              (or (ignore-errors (sb-posix:passwd-name (sb-posix:getpwuid uid)))
                  uid)
              (or (ignore-errors (sb-posix:group-name (sb-posix:getgrgid gid)))
                  gid)))))

(defun marginalia-file-size (path stat)
  "The size field: a symbolic link shows the length of the path it names."
  (if (= (logand (sb-posix:stat-mode stat) sb-posix:s-ifmt)
         sb-posix:s-iflnk)
      (length (or (ignore-errors (sb-posix:readlink path)) ""))
      (sb-posix:stat-size stat)))

(defun marginalia-file-detail (path)
  "Marginalia's annotation for PATH, or NIL when it cannot be read.
Returns the text, and a second value: the list of (START END ATTRIBUTE) ranges
that color the fields of that text, offsets into it.
Reading the attributes needs SB-POSIX; other implementations show no
annotation rather than an incomplete one."
  #+sbcl
  (let ((stat (ignore-errors (sb-posix:lstat path))))
    (when stat
      (let* ((modes (marginalia-permissions (sb-posix:stat-mode stat)))
             (size (marginalia-human-size (marginalia-file-size path stat)))
             (age (marginalia-file-age (sb-posix:stat-mtime stat)))
             (owner (marginalia-file-owner stat))
             (text (concatenate 'string
                                modes *field-separator*
                                (format nil "~v@a" +size-width+ size)
                                *field-separator*
                                (format nil "~v@a" +age-width+ age)
                                owner))
             (size-start (+ (length modes) (length *field-separator*)))
             (age-start (+ size-start +size-width+ (length *field-separator*)))
             (owner-start (+ age-start +age-width+)))
        (values text
                (append
                 ;; One range per permission character, so a flag is colored
                 ;; the same way `ls -l' output is in Emacs.
                 (loop :for index :from 0 :below (length modes)
                       :collect (list index (1+ index)
                                      (marginalia-permission-attribute
                                       (char modes index))))
                 (list (list size-start (+ size-start +size-width+)
                             'marginalia-file-size-attribute)
                       (list age-start (+ age-start +age-width+)
                             'marginalia-file-age-attribute))
                 (when owner
                   (list (list owner-start (length text)
                               'marginalia-file-owner-attribute))))))))
  #-sbcl
  (declare (ignore path))
  #-sbcl
  nil)

;;; Resolving a candidate to a path.
;;;
;;; LEM-ORDERLESS labels file candidates with their full namestring, while lem's
;;; own completion labels them with the last segment of the path, the part that
;;; gets inserted.  A relative label is therefore merged onto the directory the
;;; prompt is currently completing into -- the directory part of the expanded
;;; input, which is what COMPLETION-FILE itself uses to list the candidates.

(defun marginalia-directory-part (path)
  "PATH up to and including its last slash, or \"\"."
  (let ((slash (position #\/ path :from-end t)))
    (if slash (subseq path 0 (1+ slash)) "")))

(defun marginalia-file-entry-path (label string directory)
  "The path LABEL names in a prompt whose input is STRING, completed in DIRECTORY."
  (cond ((zerop (length label)) nil)
        ((char= (char label 0) #\/) label)
        (t (concatenate 'string
                        (marginalia-directory-part
                         (or (ignore-errors (lem:expand-file-name string directory))
                             (namestring directory)))
                        label))))

(defclass marginalia-file-item (lem/completion-mode:completion-item)
  ((segments
    :initarg :segments
    :initform nil
    :reader item-segments))
  (:documentation "A file candidate whose :detail carries colored fields.
SEGMENTS are the (START END ATTRIBUTE) ranges of that :detail; they are stored
on the item because the :detail itself is a plain string."))

(defun marginalia-file-item (item detail segments)
  "ITEM as a MARGINALIA-FILE-ITEM showing DETAIL, with SEGMENTS colored."
  (make-instance 'marginalia-file-item
                 :label (lem/completion-mode:completion-item-label item)
                 :detail detail
                 :chunks (lem/completion-mode::completion-item-chunks item)
                 :start (lem/completion-mode::completion-item-start item)
                 :end (lem/completion-mode::completion-item-end item)
                 :focus-action (lem/completion-mode::completion-item-focus-action item)
                 :segments segments))

(defun marginalia-annotate-shown-file-items (items string directory)
  "ITEMS with each candidate's mode, size and age appended as its :detail."
  (mapcar (lambda (item)
            (multiple-value-bind (detail segments)
                (marginalia-file-detail
                 (marginalia-file-entry-path
                  (lem/completion-mode:completion-item-label item)
                  string directory))
              (if detail
                  (marginalia-file-item item detail segments)
                  item)))
          items))

;;; Coloring the annotation.
;;;
;;; The :detail is inserted as one run of text in DETAIL-ATTRIBUTE
;;; (src/ext/completion-mode.lisp:142-160), so the colors are painted over the
;;; detail's characters afterwards: an :around method lets lem insert the row as
;;; it always has -- label column, chunks, click and hover callbacks -- and then
;;; replaces the attribute of each field and permission character.  It is
;;; specialized on this system's item class, so it only ever runs on the
;;; candidates this file annotated.

(defmethod lem/popup-menu:apply-print-spec :around
    ((print-spec lem/completion-mode::print-spec) point (item marginalia-file-item))
  (call-next-method)
  (alexandria:when-let ((segments (item-segments item)))
    (let ((detail-length (length (lem/completion-mode:completion-item-detail item))))
      ;; The primary method ends the row with the detail and one trailing space.
      (with-point ((start point))
        (character-offset start (- (1+ detail-length)))
        (dolist (segment segments)
          (destructuring-bind (from to attribute) segment
            (with-point ((a start) (b start))
              (character-offset a from)
              (character-offset b to)
              (put-text-property a b :attribute attribute))))))))

(defun marginalia-annotate-file-items (items string directory)
  "ITEMS from a file prompt, annotated with this system's file attributes.
Only the candidates that can be on screen are annotated; completion-mode keeps
the first *LIMIT-NUMBER-OF-ITEMS* of them (src/ext/completion-mode.lisp:287-295)
before *COMPLETION-REVERSE* flips the list, and lstat-ing a whole large
directory would be wasted work."
  (let* ((limit lem/completion-mode::*limit-number-of-items*)
         (shown (if (and limit (< limit (length items)))
                    (subseq items 0 limit)
                    items))
         (annotated (marginalia-annotate-shown-file-items shown string directory)))
    (if (eq shown items)
        annotated
        (append annotated (nthcdr (length shown) items)))))

;;; Installation.
;;;
;;; The producer of the candidates is whichever function *PROMPT-FILE-COMPLETION-
;;; FUNCTION* names -- lem's own PROMPT-FILE-COMPLETION, LEM-ORDERLESS's
;;; ORDERLESS-FILE-COMPLETION, or TRAMP's -- and it is patched in place the way
;;; the M-x annotator patches LEM-ORDERLESS:ORDERLESS-COMMAND-COMPLETION.  The
;;; variable keeps naming the same symbol, so reloading the other system's
;;; INSTALL cannot silently unhook the annotation.

(defvar *file-completion-originals* (make-hash-table :test #'eq)
  "The unwrapped producers, keyed by the symbol that names them.
Captured once per symbol so that reloading replaces the wrapper instead of
stacking another one on top of it.")

(defun marginalia-file-completion-producer ()
  "The symbol whose function produces the candidates of a file prompt, or NIL."
  (let ((current lem:*prompt-file-completion-function*))
    (and (symbolp current) current (fboundp current) current)))

(defun install-file-annotations ()
  "Annotate the candidates of every file prompt (C-x C-f and friends)."
  (alexandria:when-let (symbol (marginalia-file-completion-producer))
    (let ((original (or (gethash symbol *file-completion-originals*)
                        (setf (gethash symbol *file-completion-originals*)
                              (symbol-function symbol)))))
      (setf (symbol-function symbol)
            (lambda (string directory &key directory-only)
              (marginalia-annotate-file-items
               (funcall original string directory :directory-only directory-only)
               string directory)))))
  (values))
