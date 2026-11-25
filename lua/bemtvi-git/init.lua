-- bemtvi-git — git integration for bemtvi. Its features share one diff base.
--
--   :GitChanges       a picker of every changed file, untracked ones last and newest
--                     first
--   change marks      every buffer's added / changed / removed lines, as a gutter sign
--                     and a line background, following unsaved edits
--
-- The diff base is two options, so a workspace can override them like any other:
--
--   btv.o["git.base"]         revision to compare against        (default "HEAD")
--   btv.o["git.merge_base"]   compare against the merge base of that revision
--                             and HEAD instead                    (default false)
--
--   btv.wso["git.base"] = "origin/main"   -- this workspace only, persisted
--
--   btv.o["git.change_signs"]   show change marks in the gutter     (default true)
--   btv.o["git.change_lines"]   show them as line backgrounds        (default true)
--
-- Module map:
--   status.lua      the changed-file list (btv.git.status + mtimes)
--   picker.lua      the `git_changed` picker source
--   hunks.lua       the per-buffer change marks (btv.git.diff_file + a decor provider)
--   highlights.lua  theme-derived colours

local highlights = require("bemtvi-git.highlights")
local picker = require("bemtvi-git.picker")
local hunks = require("bemtvi-git.hunks")

local M = {}

local OPTS = {
  base = "string",
  merge_base = "boolean",
  change_signs = "boolean",
  change_lines = "boolean",
}

local installed = false

-- `setup(opts)`: install the options, the picker and `:GitChanges`. Idempotent.
--
-- ```
-- opts.base           default for git.base           (default "HEAD")
-- opts.merge_base     default for git.merge_base     (default false)
-- opts.change_signs   default for git.change_signs   (default true)
-- opts.change_lines   default for git.change_lines   (default true)
-- ```
--
-- These set the options' defaults; a value set through `btv.o` or `btv.wso` still wins.
function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    if not OPTS[k] then
      error("bemtvi-git.setup: unknown option '" .. tostring(k) .. "'", 2)
    end
    if type(v) ~= OPTS[k] then
      error("bemtvi-git.setup: " .. k .. " must be a " .. OPTS[k] .. ", got " .. type(v), 2)
    end
  end

  btv.option.define("git.base", {
    type = "string",
    default = opts.base or "HEAD",
    desc = "revision the changed files and change marks compare against",
    on_change = hunks.refresh_all,
  })
  btv.option.define("git.merge_base", {
    type = "boolean",
    default = opts.merge_base == true,
    desc = "compare against the merge base of git.base and HEAD",
    on_change = hunks.refresh_all,
  })
  btv.option.define("git.change_signs", {
    type = "boolean",
    default = opts.change_signs ~= false,
    desc = "show change marks in the gutter",
    on_change = hunks.repaint,
  })
  btv.option.define("git.change_lines", {
    type = "boolean",
    default = opts.change_lines ~= false,
    desc = "show change marks as line backgrounds",
    on_change = hunks.repaint,
  })

  highlights.apply()
  picker.register()
  hunks.install()
  btv.command("GitChanges", function()
    picker.open()
  end, { desc = "Pick a file changed against the git diff base" })

  if not installed then
    installed = true
    btv.on("ColorScheme", {}, highlights.apply)
  end
end

-- Open the changed-files picker (what `:GitChanges` runs). `opts` are
-- `btv.picker.open` overrides.
function M.pick(opts)
  return picker.open(opts)
end

-- `list(dir)` -> promise of `{ root, files }`: the changed files the picker shows, for
-- the repository containing `dir`. See `bemtvi-git.status`.
function M.list(dir)
  return require("bemtvi-git.status").list(dir)
end

return M
