-- The changed-file list: what is in it, in what order, and against which base.

local here = btv.utils.dirname(debug.getinfo(1, "S").source:sub(2))
local S = dofile(btv.utils.joinpath(here, "support.lua"))
local status = require("bemtvi-git.status")

require("bemtvi-git").setup({})

local expect = btv.test.expect

-- "<XY> <rel>" per file, in list order.
local function rows(dir, base)
  local res = btv.await(status.list(dir, base))
  local out = {}
  for _, f in ipairs(res.files) do
    out[#out + 1] = f.index .. f.worktree .. " " .. f.rel
  end
  return out
end

btv.test.describe("status.list", function()
  btv.test.it("lists tracked changes by path, then untracked files newest first", function()
    local dir = S.repo()
    S.write(dir, "mod.txt", "one\nTWO\nthree\n")
    btv.await(btv.fs.remove(btv.utils.joinpath(dir, "gone.txt")))
    S.write(dir, "added.txt", "new\n")
    S.git(dir, "add", "added.txt")
    -- Untracked, inside a brand-new directory (never collapsed), with distinct ages.
    S.write(dir, "fresh/old.txt", "o\n")
    S.write(dir, "fresh/deep/newest.txt", "n\n")
    S.write(dir, "middle.txt", "m\n")
    S.touch(dir, "fresh/old.txt", "202001010000")
    S.touch(dir, "middle.txt", "202101010000")
    S.touch(dir, "fresh/deep/newest.txt", "202201010000")

    expect(rows(dir)).to_equal({
      "A  added.txt",
      " D gone.txt",
      " M mod.txt",
      "?? fresh/deep/newest.txt",
      "?? middle.txt",
      "?? fresh/old.txt",
    })
  end)

  btv.test.it("gives absolute paths, none for a deleted file, and a kind", function()
    local dir = S.repo()
    btv.await(btv.fs.remove(btv.utils.joinpath(dir, "gone.txt")))
    S.git(dir, "mv", "keep.txt", "kept.txt")
    S.write(dir, "u.txt", "u\n")
    local res = btv.await(status.list(dir))
    local by = {}
    for _, f in ipairs(res.files) do
      by[f.rel] = f
    end
    expect(by["gone.txt"].kind).to_be("deleted")
    expect(by["gone.txt"].path).to_be_nil()
    expect(by["kept.txt"].kind).to_be("renamed")
    expect(by["kept.txt"].orig).to_be("keep.txt")
    expect(by["u.txt"].kind).to_be("untracked")
    expect(by["u.txt"].path).to_be(btv.utils.joinpath(res.root, "u.txt"))
    expect(type(by["u.txt"].mtime)).to_be("number")
  end)

  btv.test.it("opens the file a staged deletion left on disk, from either row", function()
    -- `git rm --cached`: the deletion is staged and the file, still there, is untracked.
    -- git lists the path twice; both rows name a file that exists.
    local dir = S.repo()
    S.git(dir, "rm", "-q", "--cached", "keep.txt")
    local res = btv.await(status.list(dir))
    local got = {}
    for _, f in ipairs(res.files) do
      got[#got + 1] = f.index .. f.worktree .. " " .. f.kind .. " " .. tostring(f.path)
    end
    local path = btv.utils.joinpath(res.root, "keep.txt")
    expect(got).to_equal({ "D  deleted " .. path, "?? untracked " .. path })
  end)

  btv.test.it("gives no path for a conflict both sides deleted", function()
    -- Renamed apart on two branches: the original path is deleted on both (`DD`) and is
    -- gone from the worktree.
    local dir = S.repo()
    S.git(dir, "checkout", "-q", "-b", "other")
    S.git(dir, "mv", "keep.txt", "theirs.txt")
    S.git(dir, "commit", "-q", "-m", "theirs")
    S.git(dir, "checkout", "-q", "main")
    S.git(dir, "mv", "keep.txt", "ours.txt")
    S.git(dir, "commit", "-q", "-m", "ours")
    expect(pcall(S.git, dir, "merge", "-q", "other")).to_be(false)
    local res = btv.await(status.list(dir))
    local got = {}
    for _, f in ipairs(res.files) do
      local open = f.path ~= nil
      got[#got + 1] = ("%s%s %s %s %s"):format(f.index, f.worktree, f.rel, f.kind, tostring(open))
    end
    expect(got).to_equal({
      "DD keep.txt conflict false",
      "AU ours.txt conflict true",
      "UA theirs.txt conflict true",
    })
  end)

  btv.test.it("keeps an untracked symlink whose target is missing", function()
    -- git lists the link itself; that its target is gone does not make it less a change.
    local dir = S.repo()
    local r = btv.await(btv.run({ cmd = "ln", args = { "-s", "nowhere", "dangling" }, cwd = dir }))
    assert(r.code == 0, r.stderr)
    expect(rows(dir)).to_equal({ "?? dangling" })
  end)

  btv.test.it("compares against git.base, and its merge base on request", function()
    local dir = S.repo()
    S.git(dir, "checkout", "-q", "-b", "feature")
    S.write(dir, "mod.txt", "one\nTWO\nthree\n")
    S.git(dir, "commit", "-q", "-am", "feature work")
    S.git(dir, "checkout", "-q", "main")
    S.write(dir, "keep.txt", "keep\nmore\n")
    S.git(dir, "commit", "-q", "-am", "upstream work")
    S.git(dir, "checkout", "-q", "feature")

    -- Default base: HEAD, nothing changed.
    expect(rows(dir)).to_equal({})

    btv.o["git.base"] = "main"
    expect(rows(dir)).to_equal({ "M  keep.txt", "M  mod.txt" })

    btv.o["git.merge_base"] = true
    expect(rows(dir)).to_equal({ "M  mod.txt" })

    -- A workspace override wins over the global value.
    btv.wso["git.base"] = "HEAD"
    btv.wso["git.merge_base"] = false
    expect(rows(dir)).to_equal({})
  end)

  btv.test.it("rejects a base that does not resolve, naming it", function()
    local dir = S.repo()
    local ok, err = pcall(btv.await, status.list(dir, { rev = "origin/nope", merge_base = false }))
    expect(ok).to_be(false)
    expect(err.code).to_be("ENOENT")
    expect(err.message:find("origin/nope", 1, true) ~= nil).to_be(true)
  end)

  btv.test.it("rejects ENOREPO outside a repository", function()
    local ok, err = pcall(btv.await, status.list(btv.test.tempdir()))
    expect(ok).to_be(false)
    expect(err.code).to_be("ENOREPO")
  end)
end)

btv.test.describe("status.list untracked dates", function()
  -- Wrap a `btv` function for the duration of `fn`, counting its calls.
  local function counting(tbl, key, fn)
    local orig, calls = tbl[key], 0
    tbl[key] = function(...)
      calls = calls + 1
      return orig(...)
    end
    local ok, err = pcall(fn)
    tbl[key] = orig
    if not ok then
      error(err, 0)
    end
    return calls
  end

  btv.test.it("takes the dates from status, with no stat per file", function()
    local dir = S.repo()
    for i = 1, 30 do
      S.write(dir, ("u%02d.txt"):format(i), "x\n")
    end
    S.touch(dir, "u07.txt", "203001010000")
    local res
    local calls = counting(btv.fs, "lstat", function()
      res = btv.await(status.list(dir))
    end)
    expect(calls).to_be(0)
    expect(#res.files).to_be(30)
    expect(res.files[1].rel).to_be("u07.txt")
  end)

  btv.test.it("falls back to a stat per file when status gives no dates", function()
    local dir = S.repo()
    S.write(dir, "older.txt", "o\n")
    S.write(dir, "newer.txt", "n\n")
    S.touch(dir, "older.txt", "202001010000")
    S.touch(dir, "newer.txt", "202301010000")
    -- An older engine (or daemon) ignores `mtime = true` and leaves the fields out.
    local orig = btv.git.status
    btv.git.status = function(path, opts)
      return orig(path, opts):next(function(st)
        for _, e in ipairs(st.entries) do
          e.mtime, e.type = nil, nil
        end
        return st
      end)
    end
    local ok, res = pcall(btv.await, status.list(dir))
    btv.git.status = orig
    expect(ok).to_be(true)
    expect(res.files[1].rel).to_be("newer.txt")
    expect(res.files[2].rel).to_be("older.txt")
  end)
end)
