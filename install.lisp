(in-package :lem-marginalia)

;;; Entry point.
;;;
;;; Loading the system annotates every prompt this system knows about: M-x
;;; candidates get the command's docstring (MARGINALIA.LISP), file prompt
;;; candidates get their mode, size and age (FILES.LISP), buffer prompt
;;; candidates get their flags, size, mode and file (BUFFERS.LISP), and the
;;; variable, library, theme and apropos prompts are annotated by the classifier
;;; in PROMPTS.LISP.  INSTALL is idempotent: each annotator replaces
;;; its previous wrapper instead of stacking another one, so reloading the
;;; system is safe.  The prompt classifier is a method on %PROMPT-FOR-LINE, so
;;; it is replaced rather than wrapped when the system is reloaded.

(defun install ()
  "Annotate the candidates of every prompt this system knows how to annotate."
  (install-command-annotations)
  (install-file-annotations)
  (install-buffer-annotations)
  (values))

(install)
