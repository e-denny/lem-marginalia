# lem-marginalia

Marginalia-style annotations for Lem's `M-x`: the first line of each command's
docstring next to the command name, plus its keybindings in a right-aligned
column.

Loading the system applies it. `lem-marginalia:install` wraps
`lem-orderless:orderless-command-completion` so the matches are annotated before
the popup prints them. The prompt completion function keeps pointing at
orderless, so reloading either system cannot silently unhook the other.

Annotation is display-only: a completion item's `:detail` is what gets printed
after the label column, selecting a candidate inserts its `:label`, and
narrowing-down takes the common prefix of `:labels`, so annotating cannot change
which command runs.

## Loading

```lisp
(pushnew (merge-pathnames "extensions/marginalia/" (lem-home)) asdf:*central-registry* :test #'equal)
(asdf:load-system "lem-marginalia")
```

Loading the system applies it; there is nothing else to call.

## Knobs

| variable | default | meaning |
|---|---|---|
| `lem-marginalia:*marginalia-description-width*` | 60 | longest description, in characters |
| `lem-marginalia:*marginalia-key-column*` | 12 | minimum width of the keybinding column |

The description column is shortened when the candidate labels or keybindings are
long, using the popup width: `lem-vertico:*prompt-max-width*` when that system is
loaded, the frame width otherwise, so a row can never push the popup wider than
the prompt.

## Requires

`lem-orderless`. Commands without a docstring (most extension commands) keep
their keybinding column and show nothing after it, as marginalia does in Emacs.
