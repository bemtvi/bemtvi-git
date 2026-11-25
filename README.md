# bemtvi-git-changes

What changed in your repository, for [bemtvi](https://github.com/bemtvi/bemtvi), against a diff
base you choose.

- **`:GitChanges`** — a picker of every changed file: tracked changes first, then untracked files,
  newest first.
- **A per-workspace diff base** — `HEAD` by default; set `gitchanges.base` to `origin/main` (and
  `gitchanges.merge_base` to compare against where you branched) for one workspace with `btv.wso`.

Built on the native `btv.*` API: `btv.git` for status, `btv.picker` for the list, plugin options
for the base. Status and file reads go through `btv.git` and `btv.fs`, which run where
the files are in a remote (daemon) session.

## Install

```lua
btv.plugins({
  { "bemtvi/bemtvi-git-changes" },
})
```

then `:PluginSync`. It sets itself up on load; `require("bemtvi-git-changes").setup({ base = "main" })`
changes the defaults.

## Documentation

- In the editor: `:help bemtvi-git-changes`
- On GitHub: [doc/bemtvi-git-changes.md](./doc/bemtvi-git-changes.md) (the help source)
