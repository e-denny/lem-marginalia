(defsystem "lem-marginalia"
  :description "Marginalia-style command annotations for Lem's M-x."
  :author "Lem contributors"
  :license "MIT"
  :depends-on ("lem/core" "lem-orderless")
  :serial t
  :components ((:file "package")
               (:file "marginalia")))
