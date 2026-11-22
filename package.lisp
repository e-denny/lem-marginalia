;;; UIOP's DEFINE-PACKAGE rather than CL:DEFPACKAGE: this package's export list
;;; changes when an annotator is added or removed, and SBCL's DEFPACKAGE signals
;;; a package-at-variance error when a reload would drop an export the running
;;; image still has -- which would make (asdf:load-system "lem-marginalia")
;;; fail in a live editor exactly when it is being updated.  UIOP's version
;;; unexports and uninterns the dropped symbols instead.
(uiop:define-package :lem-marginalia
  (:use :cl :lem)
  (:documentation "Marginalia-style annotations for Lem's prompts: command
docstrings in M-x, file attributes in C-x C-f, buffer fields in C-x b, and the
variable, library, theme and apropos prompts.")
  (:export #:marginalia-annotate-command-items
           #:marginalia-annotate-file-items
           #:marginalia-annotate-buffer-items
           #:marginalia-file-detail
           #:*marginalia-description-width*
           #:*marginalia-key-column*
           #:*marginalia-label-column*
           #:*marginalia-buffer-mode-width*
           #:*marginalia-max-relative-age*
           #:*prompt-annotators*
           #:marginalia-annotator-for-prompt
           #:marginalia-annotate-command-names
           #:marginalia-annotate-variable-names
           #:marginalia-annotate-library-names
           #:marginalia-annotate-theme-names
           #:install
           #:install-command-annotations
           #:install-file-annotations
           #:install-buffer-annotations))
