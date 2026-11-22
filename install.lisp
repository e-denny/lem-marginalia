(in-package :lem-marginalia)

;;; Entry point.
;;;
;;; Loading the system annotates both kinds of prompt this system knows about:
;;; M-x candidates get the command's docstring (MARGINALIA.LISP), and file
;;; prompt candidates get their mode, size and age (FILES.LISP).  INSTALL is
;;; idempotent: each annotator replaces its previous wrapper instead of stacking
;;; another one, so reloading the system is safe.

(defun install ()
  "Annotate M-x and file prompt candidates with this system's descriptions."
  (install-command-annotations)
  (install-file-annotations)
  (values))

(install)
