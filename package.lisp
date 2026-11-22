(defpackage :lem-marginalia
  (:use :cl :lem)
  (:documentation "Marginalia-style command docstrings next to M-x candidates.")
  (:export #:marginalia-annotate-command-items
           #:*marginalia-description-width*
           #:*marginalia-key-column*
           #:install))
(in-package :lem-marginalia)
