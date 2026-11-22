(defsystem "lem-marginalia"
  :description "Marginalia-style annotations for Lem's M-x and file prompts."
  :author "Lem contributors"
  :license "MIT"
  :depends-on ("lem/core" "lem-orderless")
  :serial t
  :components ((:file "package")
               (:file "marginalia")
               (:file "files")
               (:file "install")))
