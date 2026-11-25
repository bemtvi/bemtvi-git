-- bemtvi-git-changes — what changed in this repository, against a diff base you pick.
--
--   :GitChanges       a picker of every changed file, untracked ones last and newest
--                     first
--
-- The diff base is two options, so a workspace can override them like any other:
--
--   btv.o["gitchanges.base"]         revision to compare against   (default "HEAD")
--   btv.o["gitchanges.merge_base"]   compare against the merge base of that revision
--                                    and HEAD instead               (default false)
--
--   btv.wso["gitchanges.base"] = "origin/main"   -- this workspace only, persisted
--
-- Module map:
--   status.lua      the changed-file list (btv.git.status + mtimes)
--   picker.lua      the `git_changed` picker source
--   highlights.lua  theme-derived colours

local highlights = require("bemtvi-git-changes.highlights")
local picker = require("bemtvi-git-changes.picker")

local M = {}

local OPTS = { base = "string", merge_base = "boolean" }

local installed = false

-- `setup(opts)`: install the options, the picker and `:GitChanges`. Idempotent.
--
-- ```
-- opts.base         default for gitchanges.base        (default "HEAD")
-- opts.merge_base   default for gitchanges.merge_base  (default false)
-- ```
--
-- These set the options' defaults; a value set through `btv.o` or `btv.wso` still wins.
function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    if not OPTS[k] then
      error("bemtvi-git-changes.setup: unknown option '" .. tostring(k) .. "'", 2)
    end
    if type(v) ~= OPTS[k] then
      error("bemtvi-git-changes.setup: " .. k .. " must be a " .. OPTS[k] .. ", got " .. type(v), 2)
    end
  end

  btv.option.define("gitchanges.base", {
    type = "string",
    default = opts.base or "HEAD",
    desc = "revision the changed files and hunk marks compare against",
  })
  btv.option.define("gitchanges.merge_base", {
    type = "boolean",
    default = opts.merge_base == true,
    desc = "compare against the merge base of gitchanges.base and HEAD",
  })

  highlights.apply()
  picker.register()
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
-- the repository containing `dir`. See `bemtvi-git-changes.status`.
function M.list(dir)
  return require("bemtvi-git-changes.status").list(dir)
end

return M
