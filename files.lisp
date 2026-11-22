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
Reading the attributes needs SB-POSIX; other implementations show no
annotation rather than an incomplete one."
  #+sbcl
  (let ((stat (ignore-errors (sb-posix:lstat path))))
    (when stat
      (concatenate 'string
                   (format nil "~a  ~7@a  ~12@a"
                           (marginalia-permissions (sb-posix:stat-mode stat))
                           (marginalia-human-size (marginalia-file-size path stat))
                           (marginalia-file-age (sb-posix:stat-mtime stat)))
                   (marginalia-file-owner stat))))
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

(defun marginalia-annotate-shown-file-items (items string directory)
  "ITEMS with each candidate's mode, size and age appended as its :detail."
  (mapcar (lambda (item)
            (alexandria:if-let (detail
                                (marginalia-file-detail
                                 (marginalia-file-entry-path
                                  (lem/completion-mode:completion-item-label item)
                                  string directory)))
              (marginalia-copy-item item detail)
              item))
          items))

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
