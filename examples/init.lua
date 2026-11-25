-- ~~~ Runnable demo for bemtvi-git ~~~
--
-- From the repository root (it is a git repo, so there is something to compare against),
-- point bemtvi at this folder as its config and open a tracked file:
--
--     BEMTVI_CONFIG=examples bemtvi README.md
--
-- TRY IT:
--
-- 1. Change marks follow your edits.
--      type `ggOhello<Esc>`   see: a green bar in the gutter and a green line behind
--                             `hello` (an added line)
--      type `jx`              see: the next line turns blue (changed)
--      type `jjdd`            see: a red `‾` on the line below the removed one (a removal
--                             right next to a change is part of that change instead)
--    Nothing is saved; the marks diff what is in the buffer.
--
-- 2. The changed files.
--      type `<Space>gc`       see: `:GitChanges` lists README.md as ` M` (save first with
--                             `:w` for the picker to see it: it lists the files on disk),
--                             then any untracked files, newest first
--
-- 3. Another base, for this workspace only.
--      type `<Space>gb`       see: the marks and the picker compare against the previous
--                             commit (`HEAD~1`), so its changes show up too
--      type `<Space>gB`       see: back to HEAD
--
-- Undo your edits with `u` (or `:e!`) when done.

btv.g.mapleader = " "

-- Load the plugin straight from this repo (a local-dev spec: `dir` is never cloned).
-- A real config would instead use `{ "bemtvi/bemtvi-git" }`.
btv.plugins({
  {
    name = "bemtvi-git",
    dir = btv.expand("<sfile>:p:h:h"), -- the repo root (this file's grandparent dir)
    config = function()
      require("bemtvi-git").setup({})
    end,
  },
})

btv.keymap.set("n", "<leader>gc", function()
  require("bemtvi-git").pick()
end, { desc = "bemtvi-git: changed files" })
btv.keymap.set("n", "<leader>gb", function()
  btv.wso["git.base"] = "HEAD~1"
  btv.notify("bemtvi-git: comparing against HEAD~1")
end, { desc = "bemtvi-git: compare against the previous commit" })
btv.keymap.set("n", "<leader>gB", function()
  btv.wso["git.base"] = nil
  btv.notify("bemtvi-git: comparing against " .. btv.o["git.base"])
end, { desc = "bemtvi-git: back to the default base" })
