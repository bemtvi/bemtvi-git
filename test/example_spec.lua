-- The runnable demo in examples/init.lua: source it, then press the keys its notes tell
-- a reader to press, in a throwaway repo, so the demo cannot rot.

local here = btv.utils.dirname(debug.getinfo(1, "S").source:sub(2))
local root = btv.utils.dirname(here)
local S = dofile(btv.utils.joinpath(here, "support.lua"))

dofile(btv.utils.joinpath(root, "examples", "init.lua"))

local expect = btv.test.expect

local function sign(t, row)
  return ((t:decor(row) or {}).sign or ""):gsub("%s", "")
end

btv.test.describe("examples/init.lua", function()
  btv.test.it("1: marks follow the edits the notes describe", function(t)
    local dir = S.repo()
    local path = S.write(dir, "README.md", "one\ntwo\nthree\nfour\n")
    S.git(dir, "add", "README.md")
    S.git(dir, "commit", "-q", "-m", "readme")
    t:cmd("edit " .. path)
    t:feed("ggOhello<Esc>")
    t:wait_for(function()
      return sign(t, 1) == "▎" and t:decor(1).line_bg
    end, { tries = 300, interval = 10, message = "no added mark" })
    t:feed("jx")
    t:wait_for(function()
      return sign(t, 2) == "▎"
    end, { tries = 300, interval = 10, message = "no changed mark" })
    t:feed("jjdd")
    t:wait_for(function()
      return sign(t, 4) == "‾"
    end, { tries = 300, interval = 10, message = "no removed mark" })
  end)

  btv.test.it("2 and 3: <Space>gc lists the change, <Space>gb / gB move the base", function(t)
    local dir = S.repo()
    S.write(dir, "mod.txt", "changed\n")
    S.git(dir, "commit", "-q", "-am", "second")
    t:cmd("cd " .. dir)

    t:feed("<Space>gc")
    local m = t:wait_for(function()
      return t:menu()
    end, { tries = 300, interval = 10, message = "the picker never opened" })
    expect(m.title).to_be("Git Changes (vs HEAD)")
    t:feed("<Esc>")

    t:feed("<Space>gb")
    expect(btv.o["git.base"]).to_be("HEAD~1")
    t:feed("<Space>gc")
    m = t:wait_for(function()
      local cur = t:menu()
      return cur and #cur.items == 1 and cur
    end, { tries = 300, interval = 10, message = "the commit never listed" })
    expect(m.items).to_equal({ "M  mod.txt" })
    t:feed("<Esc>")

    t:feed("<Space>gB")
    expect(btv.o["git.base"]).to_be("HEAD")
  end)
end)
