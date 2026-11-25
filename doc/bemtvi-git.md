<!-- DO NOT EDIT doc/bemtvi-git.txt BY HAND. It is generated from this file by
panvimdoc — run `scripts/gen-vimdoc.sh` after editing. -->

Git integration for bemtvi. Its features compare against one diff base you choose.

`:GitChanges` opens a picker of every changed file: staged, unstaged, deleted and renamed files first, then untracked files, newest
first, so the file you just created is the first untracked row.

The diff base is `HEAD` unless you say otherwise, and it is a workspace option: a workspace for a
branch under review can compare against `origin/main` while every other session keeps `HEAD`.

<!-- Passed through verbatim so `:help bemtvi-git` lands on this page (panvimdoc
     derives per-section tags but no bare project tag). -->
```vimdoc
                                    *bemtvi-git* *bemtvi-git-intro*
```

# Commands

```
:GitChanges    Pick a file changed against the diff base.
```

Each row leads with the two porcelain status letters (`git status --short` spells them the same
way), coloured by the kind of change, then the repo-relative path:

```
 M src/app.rs            modified in the worktree
M  src/lib.rs            staged (or committed, against a base other than HEAD)
A  src/new.rs            added
 D old.rs                deleted: listed, but there is nothing to open
R  src/main.rs ← app.rs  renamed
?? notes/todo.md         untracked
```

Untracked files are listed one by one, never as their directory, and stay below every tracked change
even while you filter. The preview pane shows the highlighted file; `<CR>` opens it in the main
editor area (`<C-t>` / `<C-x>` / `<C-v>` in a tab or split, as in every picker). The picker lists
the repository that contains the editor's working directory (`:pwd`).

# Diff base

Two options decide what "changed" means:

```
git.base         the revision to compare against           default "HEAD"
git.merge_base   compare against the merge base of          default false
                        git.base and HEAD instead
```

Set them like any option, for every session or for one workspace:

```lua
btv.o["git.base"] = "main"                -- everywhere
btv.wso["git.base"] = "origin/main"       -- this workspace only, saved with it
btv.wso["git.merge_base"] = true
```

Against a base other than `HEAD`, a file you committed on your branch counts as changed, as do
staged and worktree edits. With `merge_base`, the base is where your branch forked from
`git.base` (what `git diff origin/main...` compares against), so commits that landed on
`origin/main` after you branched do not show up as changes of yours. A base that does not resolve is
reported by name.

# Configuration

The plugin sets itself up when it loads. Call `setup()` to change the options' defaults:

```lua
require("bemtvi-git").setup({
  base = "HEAD",        -- default for git.base
  merge_base = false,   -- default for git.merge_base
})
```

A value set with `btv.o` or `btv.wso` wins over these defaults. An unknown or mistyped key is an
error.

# Highlights

Every group defaults to a colour of the active theme and yields to a colorscheme or a user
definition:

```
GitChangesAdded       picker row of an added file
GitChangesModified    picker row of a modified file
GitChangesDeleted     picker row of a deleted file
GitChangesRenamed     picker row of a renamed file
GitChangesConflict    picker row of a conflicted file
GitChangesUntracked   picker row of an untracked file
```

# Lua API

```lua
local gc = require("bemtvi-git")
gc.pick(opts)     -- open the picker; opts are btv.picker.open overrides
gc.list(dir)      -- promise of { root, files }: the rows the picker shows
```

Each file in `list()` is `{ rel, path, index, worktree, orig, kind, mtime }`: `path` is absolute
and `nil` for a deleted file, `kind` is one of `added`, `modified`, `deleted`, `renamed`, `conflict`
or `untracked`, and `mtime` is set on untracked files. The picker source is registered as
`git_changed`, so `btv.picker.open("git_changed")` works too.
