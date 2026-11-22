# lem-marginalia

Marginalia-style annotations for Lem's prompts:

- **`M-x`** — the first line of each command's docstring next to the command
  name, plus its keybindings in a right-aligned column.
- **file prompts** (`C-x C-f`, `C-x C-w`, …) — the mode, size and modification
  time of every candidate, the way Emacs' marginalia annotates `find-file`:

  ```
  lem/  drwxr-xr-x       4k     1d 3h ago
  ```

- **buffer prompts** (`C-x b`, …) — modified/read-only flags, size, major mode
  and file name:

  ```
  *Messages*  **-     3.3k  Fundamental
  ```

- **other prompts** — variables (`describe-lem-variable`), libraries
  (`load-library`), color themes (`load-theme`) and `apropos-command`, annotated
  with the fields Lem actually has for them; see [Other prompts](#other-prompts).

Loading the system applies all four. `lem-marginalia:install` is idempotent, so
reloading the system is safe.

Annotation is display-only: a completion item's `:detail` is what gets printed
after the label column, selecting a candidate inserts its `:label`, and
narrowing-down takes the common prefix of `:labels`, so annotating cannot change
which command runs, which file is opened or which buffer is switched to.

The width of every column is measured against the popup box —
`lem-vertico:*prompt-max-width*` when that system is loaded, the frame width
otherwise — so an annotation uses all of the row and never widens the popup.

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

## Buffer annotations

The fields are Emacs' own (`marginalia--buffer-status` and
`marginalia--buffer-file`): three status characters, the size right-aligned in
7 columns, the major mode in 20, and the file name:

```
*Messages*  **-     3.3k  Fundamental  ~/lem/src/ext/prompt-window.lisp
*scratch*   ---        0  Fundamental
```

The characters are the mode-line constructs: `*` for a modified buffer, `%` for
a read-only one, `-` otherwise, then the same again for a remote directory, then
`@`/`-` for that directory. Lem has no remote buffers to mark here, so the last
two repeat the first and stay `-`; modified and read-only are what a buffer list
needs to show. Sizes are `file-size-human-readable`, the same formatting the
file annotator uses, so `4k` and `128k` read the same in both.

The file column shows `buffer-filename`, or the directory for a buffer that
lists one (`LEM/DIRECTORY-MODE` names such a buffer after its path), as
marginalia does for dired buffers. It is truncated from the left, because the
end of a path is the part that names the file. This replaces the file name
lem's own `prompt-buffer-completion` puts in `:detail`, so a row gains columns
rather than a second line.

As with files and commands, only the candidates that can be on screen are
annotated. The size counts characters, like `%I` in Emacs, not bytes.

## Other prompts

Lem has no completion categories, so where Emacs chooses an annotator from the
candidate category (`marginalia-annotators`, refined by its classifiers), this
system classifies by prompt string — the analogue of
`marginalia-prompt-categories` — and looks the annotator up in
`lem-marginalia:*prompt-annotators*`:

| prompt | command | annotation |
|---|---|---|
| `Enter Variable: ` | `describe-lem-variable` | `editor`/`variable`, the value, the docstring |
| `load library: `, `library: ` | `load-library`, `site-init-add-dependency` | `Loaded`, the system description, its directory |
| `Color theme: ` | `load-theme` | `current`, and the theme it inherits from |
| `Apropos: ` | `apropos-command` | the first line of each command's docstring |

A variable's value is printed with a bounded `*print-length*` and cut to 16
columns, because a value can be a keymap or an alist; the docstring gets the rest
of the row. The fields are not padded, which is how
`marginalia-annotate-variable` lays them out, and the class column
(`editor`/`variable`) is dropped when every candidate has the same one: a column
of identical words is not worth ten columns of a row that has about a hundred.
`Loaded` and the directory come from ASDF, which is where Lem keeps a library.
Themes have no documentation and no file in Lem's data model, so the two columns
are what it does have.

The candidates of those prompts are plain strings, so the annotator builds the
completion items itself with the prompt's input range: Tab and Return replace the
whole input, exactly as they do in M-x. Only the candidates that can be on screen
are annotated.

Not annotated, and why:

| Emacs annotator | why not here |
|---|---|
| `bookmark` | Lem's bookmark struct holds a name, a filename and a position — no context strings; the file name is already the candidate's `:detail` |
| `function`, `symbol`, `imenu` | no prompt over the running image's symbols; a language-mode prompt would cost one connection round trip per candidate |
| `coding-system`, `charset`, `input-method`, `minor-mode`, `customize-group`, `face`, `color`, `package`, `environment-variable`, `tab`, `frame`, `embark-keybinding`, `multi-category` | no such prompt exists in Lem (no customize, package manager, tab bar, Embark or mixed-source prompt; `prompt-for-character` reads a key, not a list) |

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
| `lem-marginalia:*marginalia-description-width*` | nil | longest command description, in characters; nil fills the row |
| `lem-marginalia:*marginalia-key-column*` | 12 | minimum width of the keybinding column |
| `lem-marginalia:*marginalia-label-column*` | 40 | widest label column before the annotation; nil keeps Lem's own width |
| `lem-marginalia:*marginalia-buffer-mode-width*` | 20 | width of the major mode column in buffer prompts |
| `lem-marginalia:*marginalia-max-relative-age*` | 14 days | younger file entries get a relative age, older ones a date |

`lem-marginalia:*prompt-annotators*` is the prompt-to-annotator alist; push a
`(substring . function)` pair to annotate another prompt, or set it to nil to
turn the prompt classifier off. The functions receive the candidate strings and
return completion items built with the internal `marginalia-prompt-item`.

The label column is capped at `*marginalia-label-column*`. Lem pads it to the
longest candidate on screen, so one long name takes the room of every row — a
prompt completing over package-qualified variable names
(`lem-lsp-base/protocol-3-17:failure-handling-kind-transactional` is 72 columns)
would otherwise leave the annotation a third of the box and truncate every
description to a few words. Rows whose own label is longer than the cap start
their annotation right after the label; `nil` restores Lem's own width. The cap
is applied by an `:around` method on the popup's `apply-print-spec`, so it holds
for every completion list, not only the prompts annotated here.

The description column is what the row has left: the box is
`lem-vertico:*prompt-max-width*` columns wide (120 by default), the frame width
when that system is not loaded, and the label and keybinding columns come out of
it. A description therefore runs to the right edge of the box — about 70 columns
next to a typical command name — instead of stopping at a fixed 60, which is what
Emacs' marginalia would do with its half-the-window `marginalia-field-width`
rule. It is cut at the column, like `truncate-string-to-width`, not backed up to
the previous word boundary: a word boundary gave away a whole word of the few
columns an annotation has. Setting the knob to a number caps it below that, and
a row can never push the popup wider than the prompt.

## Requires

`lem-orderless`. Commands without a docstring (most extension commands) keep
their keybinding column and show nothing after it, as marginalia does in Emacs.

File annotations read the permission bits and times through `sb-posix`, so they
need SBCL; on other implementations file candidates are left unannotated.
