-- bemtvi-git.picker — the `git_changed` picker source.
--
-- One row per changed file: the porcelain `XY` letters as the row's tag, the
-- repo-relative path as its text, coloured by the kind of change. Untracked files are
-- pushed as `low` rows, which the picker keeps below every tracked change even while
-- you filter, in the newest-first order `status.list` gives them.

local status = require("bemtvi-git.status")
local highlights = require("bemtvi-git.highlights")

local M = {}

local PREFIX = "bemtvi-git: "

-- Report a failed listing. Outside a repository is a plain warning; anything else (a
-- base revision that does not resolve) is an error naming it.
local function report(err)
  if type(err) == "table" and err.code == "ENOREPO" then
    btv.notify(PREFIX .. "not inside a git repository", btv.log.levels.WARN)
    return
  end
  local msg = type(err) == "table" and (err.message or err.code) or tostring(err)
  btv.notify(PREFIX .. msg, btv.log.levels.ERROR)
end

-- The row for one file.
function M.row(f)
  local text = f.rel
  if f.dir then
    text = text .. "/" -- git's own spelling of a nested repository
  end
  if f.orig ~= "" then
    text = text .. " ← " .. f.orig
  end
  return {
    tag = f.index .. f.worktree,
    text = text,
    hl = highlights.row(f.kind),
    low = f.kind == "untracked" or nil,
    path = f.path,
    rel = f.rel,
    kind = f.kind,
  }
end

local function items(ctx)
  return btv.async(function()
    local ok, res = pcall(btv.await, status.list(ctx.cwd))
    if not ok then
      report(res)
      return
    end
    for _, f in ipairs(res.files) do
      ctx.push(M.row(f))
    end
  end)()
end

local function confirm(item, mode, layer)
  if not item.path then
    btv.notify(PREFIX .. item.rel .. " is deleted; there is nothing to open", btv.log.levels.WARN)
    return
  end
  btv.picker.edit(item, mode, layer)
end

function M.register()
  btv.picker.source({
    name = "git_changed",
    title = "Git Changes",
    preview = "file",
    layer = "main",
    items = items,
    confirm = confirm,
  })
end

-- Open the picker, titled with the base it compares against.
function M.open(opts)
  opts = opts or {}
  if opts.title == nil then
    opts.title = "Git Changes (vs " .. status.describe(status.base()) .. ")"
  end
  return btv.picker.open("git_changed", opts)
end

return M
