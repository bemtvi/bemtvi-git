# bemtvi-git

Git integration for [bemtvi](https://github.com/bemtvi/bemtvi). Its features share one diff base
you choose, per workspace if you like.

- **`:GitChanges`** — a picker of every changed file: tracked changes first, then untracked files,
  newest first.
- **Change marks** — every buffer's added, changed and removed lines in the gutter and as a line
  background, following unsaved edits.
- **A per-workspace diff base** — `HEAD` by default; set `git.base` to `origin/main` (and
  `git.merge_base` to compare against where you branched) for one workspace with `btv.wso`.

Built on the native `btv.*` API: `btv.git` for status and diffs, `btv.picker` for the list, a
`btv.decor` provider for the marks, plugin options for the base. Status and file reads go through `btv.git` and `btv.fs`, which run where
the files are in a remote (daemon) session.

## Install

```lua
btv.plugins({
  { "bemtvi/bemtvi-git" },
})
```

then `:PluginSync`. It sets itself up on load; `require("bemtvi-git").setup({ base = "main" })`
changes the defaults.

## Documentation

- In the editor: `:help bemtvi-git`
- On GitHub: [doc/bemtvi-git.md](./doc/bemtvi-git.md) (the help source)
