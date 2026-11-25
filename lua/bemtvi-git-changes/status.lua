-- bemtvi-git-changes.status — the changed-file list the picker shows, read through
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
    rev = btv.o["gitchanges.base"],
    merge_base = btv.o["gitchanges.merge_base"],
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

  -- Stat every untracked file at once. One that vanished since the status walk is no
  -- longer a change, so it is dropped.
  local stats = {}
  for i, f in ipairs(untracked) do
    stats[i] = btv.fs.stat(f.path):next(function(s)
      return s.mtime
    end, function()
      return false
    end)
  end
  local mtimes = btv.await(btv.promise.all(stats))
  local live = {}
  for i, f in ipairs(untracked) do
    if mtimes[i] then
      f.mtime = mtimes[i]
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
