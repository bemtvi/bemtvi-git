-- The `git_changed` picker, driven through `:GitChanges` the way a user opens it.

local here = btv.utils.dirname(debug.getinfo(1, "S").source:sub(2))
local S = dofile(btv.utils.joinpath(here, "support.lua"))

require("bemtvi-git").setup({})

local expect = btv.test.expect

-- Open the picker in `dir` and wait for `n` rows.
local function open(t, dir, n)
  t:cmd("cd " .. dir)
  t:cmd("GitChanges")
  return t:wait_for(function()
    local m = t:menu()
    return m and #m.items == n and m
  end, { tries = 300, interval = 10, message = "the picker never listed " .. n .. " rows" })
end

-- The newest message starting with the plugin's prefix.
local function notice(t)
  return t:wait_for(function()
    local m = t:message()
    return m:match("^bemtvi%-git:") and m or nil
  end, { tries = 300, interval = 10, message = "no bemtvi-git notification" })
end

btv.test.describe("git_changed picker", function()
  btv.test.it("lists tracked changes, then untracked files newest first", function(t)
    local dir = S.repo()
    S.write(dir, "mod.txt", "one\nTWO\nthree\n")
    S.write(dir, "older.txt", "o\n")
    S.write(dir, "newer.txt", "n\n")
    S.touch(dir, "older.txt", "202001010000")
    S.touch(dir, "newer.txt", "202301010000")

    local m = open(t, dir, 3)
    expect(m.items).to_equal({ " M mod.txt", "?? newer.txt", "?? older.txt" })
    expect(m.title).to_be("Git Changes (vs HEAD)")
    t:feed("<Esc>")
  end)

  btv.test.it("keeps untracked files below tracked ones while filtering", function(t)
    local dir = S.repo()
    -- The untracked name matches the query better, yet stays below the tracked change.
    S.write(dir, "mod.txt", "changed\n")
    S.write(dir, "mo.txt", "u\n")
    open(t, dir, 2)
    -- `mo.txt` is a contiguous hit in the untracked name, a scattered one in `mod.txt`.
    t:feed("mo.txt")
    t:wait_for(function()
      local cur = t:menu()
      return cur and #cur.items == 2
    end, { tries = 300, interval = 10, message = "filtered rows never settled" })
    t:idle()
    expect(t:menu().items).to_equal({ " M mod.txt", "?? mo.txt" })
    t:feed("<Esc>")
  end)

  btv.test.it("opens the picked file", function(t)
    local dir = S.repo()
    S.write(dir, "mod.txt", "one\nTWO\nthree\n")
    open(t, dir, 1)
    t:feed("<CR>")
    t:wait_for(function()
      return btv.buf.name(0):match("mod%.txt$")
    end, { tries = 300, interval = 10, message = "mod.txt never opened" })
    expect(t:lines()).to_equal({ "one", "TWO", "three" })
  end)

  btv.test.it("says a deleted file cannot be opened instead of opening it", function(t)
    local dir = S.repo()
    btv.await(btv.fs.remove(btv.utils.joinpath(dir, "gone.txt")))
    local before = t:buf()
    open(t, dir, 1)
    t:feed("<CR>")
    expect(notice(t)).to_be("bemtvi-git: gone.txt is deleted; there is nothing to open")
    expect(t:buf()).to_be(before)
  end)

  btv.test.it("compares against the workspace's base and says so in the title", function(t)
    local dir = S.repo()
    S.git(dir, "checkout", "-q", "-b", "feature")
    S.write(dir, "mod.txt", "feature\n")
    S.git(dir, "commit", "-q", "-am", "feature work")
    btv.wso["git.base"] = "main"
    btv.wso["git.merge_base"] = true
    local m = open(t, dir, 1)
    expect(m.items).to_equal({ "M  mod.txt" })
    expect(m.title).to_be("Git Changes (vs merge base of main)")
    t:feed("<Esc>")
  end)

  btv.test.it("names a base that does not resolve", function(t)
    local dir = S.repo()
    btv.o["git.base"] = "origin/nope"
    t:cmd("cd " .. dir)
    t:cmd("GitChanges")
    expect(notice(t):find("origin/nope", 1, true) ~= nil).to_be(true)
    t:feed("<Esc>")
  end)

  btv.test.it("warns outside a repository", function(t)
    t:cmd("cd " .. btv.test.tempdir())
    t:cmd("GitChanges")
    expect(notice(t)).to_be("bemtvi-git: not inside a git repository")
    t:feed("<Esc>")
  end)
end)
