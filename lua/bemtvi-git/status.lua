-- bemtvi-git.status — the changed-file list the picker shows, read through
-- `btv.git.status` against the configured diff base.
--
-- Tracked changes come first, sorted by path. Untracked files follow, each listed on
-- its own (never a collapsed directory) and ordered by modification time, newest first,
-- so the file you just created is at the top of its group.

local M = {}

-- The porcelain `XY` letters -> one kind, the thing a row is coloured by.
function M.kind(index, worktree)
  if index == "?" then
    return "untracked"
  end
  if
    index == "U"
    or worktree == "U"
    or (index == "A" and worktree == "A")
    or (index == "D" and worktree == "D")
  then
    return "conflict"
  end
  if index == "D" or worktree == "D" then
    return "deleted"
  end
  if index == "R" or worktree == "R" then
    return "renamed"
  end
  if index == "A" then
    return "added"
  end
  return "modified"
end

-- The diff base in effect: `{ rev, merge_base }` from the plugin's options (a workspace
-- override wins over the global value).
function M.base()
  return {
    rev = btv.o["git.base"],
    merge_base = btv.o["git.merge_base"],
  }
end

-- A short human label for a base, for titles and messages.
function M.describe(base)
  if base.merge_base then
    return "merge base of " .. base.rev
  end
  return base.rev
end

-- `M.list(dir, base)` -> promise of `{ root, files }`. `dir` is any directory inside
-- the repository; `base` is `{ rev, merge_base }` (defaults to `M.base()`). Each file:
--
-- ```
-- rel        repo-relative path ("/"-separated)
-- path       absolute path, nil for a file gone from the worktree
-- index      porcelain X letter
-- worktree   porcelain Y letter
-- orig       the source path of a rename, "" otherwise
-- kind       added | modified | deleted | renamed | conflict | untracked
-- mtime      modification time in seconds (untracked files only)
-- dir        true for an untracked directory: a nested repository, which git lists
--            as one entry rather than walking into it
-- ```
--
-- Rejects with the `btv.git` error (`ENOREPO` outside a repository, `ENOENT` for a
-- base revision that does not resolve).
M.list = btv.async(function(dir, base)
  base = base or M.base()
  local disc = btv.await(btv.git.discover(dir))
  local root = disc.root
  -- `mtime = true` dates and types each untracked entry inside the same op, so a
  -- repository with thousands of untracked files costs one call, not one stat each.
  local st = btv.await(btv.git.status(root, {
    untracked = "all",
    rev = base.rev,
    merge_base = base.merge_base,
    mtime = true,
  }))

  local tracked, untracked = {}, {}
  for _, e in ipairs(st.entries) do
    local kind = M.kind(e.index, e.worktree)
    local f = {
      rel = e.path,
      path = btv.utils.joinpath(root, e.path),
      index = e.index,
      worktree = e.worktree,
      orig = e.orig_path or "",
      kind = kind,
    }
    if kind == "deleted" or (e.index == "D" and e.worktree == "D") then
      -- Gone from the worktree: nothing to preview or open. (A staged deletion of a file
      -- still on disk gets its path back below, from the untracked row git adds for it.)
      f.path = nil
    end
    if kind == "untracked" then
      f.mtime = e.mtime
      f.dir = e.type == "directory" or nil
      untracked[#untracked + 1] = f
    else
      tracked[#tracked + 1] = f
    end
  end

  -- An entry status could not date is stat-ed here: on a current engine that is only a
  -- file that vanished during the walk (its stat fails and it is dropped, being no longer
  -- a change); an older engine or daemon dates none, and then every untracked file is
  -- stat-ed. `lstat`, so a symlink is dated itself (a dangling one is still a change).
  -- The replies are gathered with a counter rather than a promise per file plus
  -- `btv.promise.all`, which is a real share of the cost on tens of thousands of files.
  local undated = {}
  for _, f in ipairs(untracked) do
    if f.mtime == nil then
      undated[#undated + 1] = f
    end
  end
  local gone = {}
  btv.await(btv.promise.new(function(resolve)
    local left = #undated
    if left == 0 then
      return resolve()
    end
    local function settle(f, info)
      if info then
        f.mtime = info.mtime
        f.dir = info.type == "directory" or nil
      else
        gone[f] = true
      end
      left = left - 1
      if left == 0 then
        resolve()
      end
    end
    for _, f in ipairs(undated) do
      btv.fs.lstat(f.path):next(function(info)
        settle(f, info)
      end, function()
        settle(f, false)
      end)
    end
  end))
  local live = {}
  for _, f in ipairs(untracked) do
    if not gone[f] then
      live[#live + 1] = f
    end
  end

  -- `git rm --cached`: the staged deletion (`D `) and the file left on disk (`??`) are
  -- two rows for one path, and the file is there to open from either.
  local on_disk = {}
  for _, f in ipairs(live) do
    on_disk[f.rel] = f.path
  end
  for _, f in ipairs(tracked) do
    if f.path == nil and f.kind == "deleted" then
      f.path = on_disk[f.rel]
    end
  end

  table.sort(tracked, function(a, b)
    return a.rel < b.rel
  end)
  table.sort(live, function(a, b)
    if a.mtime ~= b.mtime then
      return a.mtime > b.mtime
    end
    return a.rel < b.rel
  end)

  local files = tracked
  for _, f in ipairs(live) do
    files[#files + 1] = f
  end
  return { root = root, files = files }
end)

return M
