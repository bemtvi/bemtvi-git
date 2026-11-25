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
