(defpackage :lem-marginalia
  (:use :cl :lem)
  (:documentation "Marginalia-style annotations for Lem's prompts: command
docstrings in M-x, file attributes in C-x C-f.")
  (:export #:marginalia-annotate-command-items
           #:marginalia-annotate-file-items
           #:marginalia-file-detail
           #:*marginalia-description-width*
           #:*marginalia-key-column*
           #:*marginalia-max-relative-age*
           #:install
           #:install-command-annotations
           #:install-file-annotations))
