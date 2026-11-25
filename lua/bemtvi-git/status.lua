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
-- path       absolute path, nil for a file deleted from the worktree
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
  local st = btv.await(btv.git.status(root, {
    untracked = "all",
    rev = base.rev,
    merge_base = base.merge_base,
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
    if kind == "deleted" then
      f.path = nil -- gone from the worktree: nothing to preview or open
    end
    if kind == "untracked" then
      untracked[#untracked + 1] = f
    else
      tracked[#tracked + 1] = f
    end
  end

  -- Stat every untracked file at once, the link itself for a symlink (a dangling one is
  -- still a change). One that vanished since the status walk is no longer a change, so
  -- it is dropped. The replies are gathered with a counter rather than a promise per
  -- file plus `btv.promise.all`: on a repository with tens of thousands of untracked
  -- files that bookkeeping is a real share of the cost.
  local stats = {}
  btv.await(btv.promise.new(function(resolve)
    local left = #untracked
    if left == 0 then
      return resolve()
    end
    local function settle(i, info)
      stats[i] = info
      left = left - 1
      if left == 0 then
        resolve()
      end
    end
    for i, f in ipairs(untracked) do
      btv.fs.lstat(f.path):next(function(info)
        settle(i, info)
      end, function()
        settle(i, false)
      end)
    end
  end))
  local live = {}
  for i, f in ipairs(untracked) do
    local info = stats[i]
    if info then
      f.mtime = info.mtime
      f.dir = info.type == "directory" or nil
      live[#live + 1] = f
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
