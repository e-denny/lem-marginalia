# lem-marginalia

Marginalia-style annotations for Lem's prompts, in two parts:

- **`M-x`** — the first line of each command's docstring next to the command
  name, plus its keybindings in a right-aligned column.
- **file prompts** (`C-x C-f`, `C-x C-w`, …) — the mode, size and modification
  time of every candidate, the way Emacs' marginalia annotates `find-file`:

  ```
  lem/  drwxr-xr-x       4k     1d 3h ago
  ```

Loading the system applies both. `lem-marginalia:install` runs the two
installers and is idempotent, so reloading the system is safe.

Annotation is display-only: a completion item's `:detail` is what gets printed
after the label column, selecting a candidate inserts its `:label`, and
narrowing-down takes the common prefix of `:labels`, so annotating cannot change
which command runs or which file is opened.

## Loading

```lisp
(pushnew (merge-pathnames "extensions/marginalia/" (lem-home)) asdf:*central-registry* :test #'equal)
(asdf:load-system "lem-marginalia")
```

Loading the system applies it; there is nothing else to call.

## File annotations

The three fields are Emacs' own: the mode string, the size right-aligned in 7
characters, and the age right-aligned in 12, separated by two spaces
(`marginalia--annotate-local-file`). The formatting matches Emacs' helpers
exactly, so the numbers read the same in both editors:

| field | rule |
|---|---|
| modes | `ls -l`-style, including setuid/setgid/sticky (`s`, `S`, `t`, `T`) |
| size | `file-size-human-readable`: binary units, a decimal only below 10 units and only when the fraction is not close to 0 or 1 (`2.5k`, `54k`, `1024k`, `1.4M`) |
| age | `seconds-to-string` with `expanded` and `abbrev`: `1d 3h ago`, `1w 4d ago`; above `*marginalia-max-relative-age*` an absolute `Aug 24 19:27`, or `2025 Nov 10` in another year |

Attributes come from `lstat`, so a symbolic link shows its own mode
(`lrwxrwxrwx`) and the length of the path it names as its size, exactly as
`ls -l` prints it. Entries that cannot be read — a permission error, or a remote
path — get no annotation and keep just their name, which is also what marginalia
does. A file owned by someone else gets a trailing `root:root` field, again
matching marginalia.

Only the candidates that can be on screen are annotated (`completion-mode` keeps
the first `*limit-number-of-items*`), so a directory with thousands of entries
costs a handful of `lstat` calls rather than thousands.

## Colors

Each field, and each character of the permission string, is painted the way
Emacs' marginalia paints it: the flags follow the `marginalia--file-modes` pcase
table (directory/link, read, write, execute, the setuid/setgid/sticky
characters, and the dim "no permission" dashes), and the size, date and owner
fields carry `marginalia-size`, `marginalia-date` and `marginalia-file-owner`.
The palette is what those faces resolve to in doom-one, the theme this was
modelled on:

| role | attribute | colour |
|---|---|---|
| no permission (`-`) | `marginalia-file-mode-no-attribute` | `#5B6268` |
| directory (`d`) | `marginalia-file-mode-dir-attribute` | `#51afef` |
| link (`l`) | `marginalia-file-mode-link-attribute` | `#a9a1e1` |
| read (`r`) | `marginalia-file-mode-read-attribute` | `#ECBE7B` |
| write (`w`) | `marginalia-file-mode-write-attribute` | `#ff6c6b` |
| execute (`x`) | `marginalia-file-mode-exec-attribute` | `#98be65` |
| setuid/setgid/sticky (`s S t T`) | `marginalia-file-mode-other-attribute` | `#c678dd` |
| rare type character | `marginalia-file-mode-rare-attribute` | `#bbc2cf` |
| size | `marginalia-file-size-attribute` | `#a9a1e1` |
| date | `marginalia-file-age-attribute` | `#51afef` |
| owner | `marginalia-file-owner-attribute` | `#51afef` |

They are plain `define-attribute` forms in `files.lisp`, so changing one is a
one-line edit followed by `(asdf:load-system "lem-marginalia" :force t)`; a
Lem theme keyword (`:base0D`, `:base0A`, …) works there too if the colours
should follow the editor's theme instead.

The colours are per-character `:attribute` properties, set by an `:around`
method on `lem/popup-menu:apply-print-spec` after Lem has inserted the row. Note
that the *selected* row is still drawn in the popup's focus attribute, which
covers the whole line, so its annotation shows the selection colours while the
other rows show theirs.


## Knobs

| variable | default | meaning |
|---|---|---|
| `lem-marginalia:*marginalia-description-width*` | 60 | longest command description, in characters |
| `lem-marginalia:*marginalia-key-column*` | 12 | minimum width of the keybinding column |
| `lem-marginalia:*marginalia-max-relative-age*` | 14 days | younger file entries get a relative age, older ones a date |

The description column is shortened when the candidate labels or keybindings are
long, using the popup width: `lem-vertico:*prompt-max-width*` when that system is
loaded, the frame width otherwise, so a row can never push the popup wider than
the prompt.

## Requires

`lem-orderless`. Commands without a docstring (most extension commands) keep
their keybinding column and show nothing after it, as marginalia does in Emacs.

File annotations read the permission bits and times through `sb-posix`, so they
need SBCL; on other implementations file candidates are left unannotated.
