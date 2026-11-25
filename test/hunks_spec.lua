-- Change marks: added / changed / removed lines in a buffer, against the diff base, as a
-- gutter sign and a line background. Driven with real keys on a file in a real repo.

local here = btv.utils.dirname(debug.getinfo(1, "S").source:sub(2))
local S = dofile(btv.utils.joinpath(here, "support.lua"))
local hunks = require("bemtvi-git.hunks")

require("bemtvi-git").setup({})

local expect = btv.test.expect

-- "<sign><bg>" per screen row for the first `n` rows: the sign glyph (or "."), then "#"
-- when the row is tinted full width (or "."). E.g. { "..", "▎#", "‾." }.
local function marks(t, n)
  local out = {}
  for row = 1, n do
    local d = t:decor(row) or {}
    out[row] = (d.sign or "."):gsub("%s", "") .. (d.line_bg and "#" or ".")
  end
  return out
end

-- Wait until the first `#want` rows read `want`.
local function expect_marks(t, want, what)
  local got
  local ok = pcall(function()
    t:wait_for(function()
      got = marks(t, #want)
      return table.concat(got, "|") == table.concat(want, "|")
    end, { tries = 300, interval = 10 })
  end)
  if not ok then
    expect(got).to_equal(want) -- fails with the last frame seen, naming `what`
    error(what)
  end
end

-- A repo whose `f.txt` holds lines a..e, opened in the editor.
local function open_repo_file(t)
  local dir = S.repo()
  local path = S.write(dir, "f.txt", "a\nb\nc\nd\ne\n")
  S.git(dir, "add", "f.txt")
  S.git(dir, "commit", "-q", "-m", "f")
  t:cmd("edit " .. path)
  return dir, path
end

btv.test.describe("change marks", function()
  btv.test.before_each(function()
    btv.o["git.base"] = nil
    btv.o["git.merge_base"] = nil
    btv.o["git.change_signs"] = nil
    btv.o["git.change_lines"] = nil
  end)

  btv.test.it("follow unsaved edits: changed, added and removed lines", function(t)
    open_repo_file(t)
    expect_marks(t, { "..", "..", "..", "..", ".." }, "a clean file has no marks")

    t:feed("jcwB<Esc>") -- change line 2
    expect_marks(t, { "..", "▎#", "..", "..", ".." }, "a changed line")

    t:feed("Goadded<Esc>") -- add a sixth line
    expect_marks(t, { "..", "▎#", "..", "..", "..", "▎#" }, "an added line")

    t:feed("4Gdd") -- remove line 4: the line now below the gap carries the removal
    expect_marks(t, { "..", "▎#", "..", "‾.", "▎#" }, "a removal")
  end)

  btv.test.it("mark a removal at the top on the new first line", function(t)
    open_repo_file(t)
    t:feed("ggdd")
    expect_marks(t, { "‾.", "..", "..", ".." }, "a removal at the top")
  end)

  btv.test.it("mark a removal at the end of the buffer on the line above it", function(t)
    open_repo_file(t)
    t:feed("Gdd")
    expect_marks(t, { "..", "..", "..", "_." }, "a removal at the end")
  end)

  btv.test.it("tell added from changed lines by their colour", function(t)
    open_repo_file(t)
    t:feed("jcwB<Esc>Goadded<Esc>")
    expect_marks(t, { "..", "▎#", "..", "..", "..", "▎#" }, "both marks")
    local buf = t:buf()
    local by_row = {}
    for _, m in ipairs(hunks.marks(hunks.get(buf), 0, 10, { line_count = 6 })) do
      by_row[m[1]] = m.sign_hl_group .. "/" .. tostring(m.line_hl_group)
    end
    expect(by_row[1]).to_be("GitChangesChangeSign/GitChangesChangeLine")
    expect(by_row[5]).to_be("GitChangesAddSign/GitChangesAddLine")
  end)

  btv.test.it("compare against git.base, and repaint when it changes", function(t)
    local dir, path = open_repo_file(t)
    S.write(dir, "f.txt", "a\nB\nc\nd\ne\n")
    S.git(dir, "commit", "-q", "-am", "edit b")
    t:cmd("edit! " .. path)
    expect_marks(t, { "..", "..", "..", "..", ".." }, "clean against HEAD")

    btv.o["git.base"] = "HEAD~1"
    expect_marks(t, { "..", "▎#", "..", "..", ".." }, "the committed change, against HEAD~1")
    btv.wso["git.base"] = "HEAD"
    expect_marks(t, { "..", "..", "..", "..", ".." }, "a workspace override wins")
    btv.wso["git.base"] = nil
  end)

  btv.test.it("catch up with a commit made elsewhere when the focus comes back", function(t)
    local dir = open_repo_file(t)
    t:feed("jcwB<Esc>:w<CR>")
    expect_marks(t, { "..", "▎#", "..", "..", ".." }, "the saved change")
    S.git(dir, "commit", "-q", "-am", "commit it outside")
    btv.autocmd.exec("FocusGained", {})
    expect_marks(t, { "..", "..", "..", "..", ".." }, "committed: nothing changed against HEAD")
  end)

  btv.test.it("drop the signs or the backgrounds on request", function(t)
    open_repo_file(t)
    t:feed("jcwB<Esc>")
    expect_marks(t, { "..", "▎#" }, "both")
    btv.o["git.change_lines"] = false
    expect_marks(t, { "..", "▎." }, "signs only")
    btv.o["git.change_lines"] = true
    btv.o["git.change_signs"] = false
    expect_marks(t, { "..", ".#" }, "backgrounds only")
  end)

  btv.test.it("mark a file opened by a relative name", function(t)
    local dir = open_repo_file(t)
    t:cmd("bwipeout!")
    t:cmd("cd " .. dir)
    t:cmd("edit f.txt")
    t:feed("jcwB<Esc>")
    expect_marks(t, { "..", "▎#", "..", "..", ".." }, "a changed line in f.txt")
  end)

  btv.test.it("mark nothing in a file outside a repository", function(t)
    local dir = btv.test.tempdir()
    local path = S.write(dir, "loose.txt", "x\ny\n")
    t:cmd("edit " .. path)
    t:feed("ccchanged<Esc>")
    t:idle()
    expect(hunks.get(t:buf())).to_be_nil()
    expect(marks(t, 2)).to_equal({ "..", ".." })
  end)

  btv.test.it("mark an untracked file as all added", function(t)
    local dir = S.repo()
    local path = S.write(dir, "new.txt", "one\ntwo\n")
    t:cmd("edit " .. path)
    expect_marks(t, { "▎#", "▎#" }, "every line is new")
  end)
end)

btv.test.describe("hunks.marks", function()
  btv.test.it("draws only the rows asked for", function()
    local h = { { old_start = 0, old_count = 0, new_start = 3, new_count = 4 } }
    local rows = {}
    for _, m in ipairs(hunks.marks(h, 3, 4, { line_count = 10 })) do
      rows[#rows + 1] = m[1]
    end
    expect(rows).to_equal({ 3, 4 })
  end)
end)
