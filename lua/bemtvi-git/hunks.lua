-- bemtvi-git.hunks — added / changed / removed lines in every buffer, against the diff
-- base, as a gutter sign and a full-width line background.
--
-- The diff runs on the buffer's text as it is now, unsaved edits included: each
-- refresh hands `btv.git.diff_file` the buffer's content with the base, and the diff
-- itself runs off the editor tick (daemon-side in a remote session). A refresh is
-- debounced per buffer, and a reply that a newer refresh has overtaken is dropped.
--
-- Painting is a `btv.decor.provider`: it draws only the visible rows, from the hunks
-- cached for the buffer, so scrolling costs no diff.
--
-- What refreshes a buffer: reading it, entering or showing it, editing it, writing it,
-- and, for the buffers on screen, the plugin installing (lazy-loaded after they opened),
-- the editor regaining the focus (a commit or checkout made elsewhere moves the base) and
-- a change of the base options.

local status = require("bemtvi-git.status")

local M = {}

-- How long a burst of edits settles before the buffer is diffed again.
M.DEBOUNCE_MS = 100

local PREFIX = "bemtvi-git: "

-- buf -> { hunks = {...} | nil, seq = <latest request>, refresh = <debounced fn> }
local state = {}

-- buf -> true once the plugin has said why it cannot mark that buffer.
local told = {}

-- message -> true for each diff error already said. A set, not the last message: two
-- buffers failing differently would otherwise each say theirs again on every refresh.
-- Emptied when the base changes, so an error the new base gives too is said again.
local said = {}

-- Say `what` once per buffer: why the plugin leaves it unmarked.
local function tell_once(buf, what)
  if not told[buf] then
    told[buf] = true
    btv.notify(PREFIX .. what, btv.log.levels.WARN)
  end
end

local function buffer_state(buf)
  local s = state[buf]
  if not s then
    s = { seq = 0 }
    state[buf] = s
  end
  return s
end

-- The buffer's file and the bytes git would compare, or nil when the buffer is not one
-- the plugin marks (no file, a special buffer). Two kinds of file are skipped, and said
-- so once:
--
-- - one in an encoding other than UTF-8: its text here is UTF-8, its blob at the base
--   is not, so every non-ASCII line would read as changed;
-- - one with mac (CR) line endings: git splits lines on LF only, so to it the file is
--   one long line, and its hunks would not land on the buffer's rows.
local function buffer_source(buf)
  if not btv.buf.is_valid(buf) or btv.bo[buf].buftype ~= "" then
    return nil
  end
  local name = btv.buf.name(buf)
  if name == nil or name == "" then
    return nil
  end
  local enc = btv.bo[buf].fileencoding
  if enc ~= "" and enc ~= "utf-8" then
    tell_once(buf, "no change marks for " .. name .. ": its encoding is " .. enc .. ", not utf-8")
    return nil
  end
  local ff = btv.bo[buf].fileformat
  if ff == "mac" then
    tell_once(
      buf,
      "no change marks for " .. name .. ": its line endings are mac (CR), not unix or dos"
    )
    return nil
  end
  local lines = btv.buf.lines(buf, 0, -1)
  local eol = ff == "dos" and "\r\n" or "\n"
  local text = table.concat(lines, eol)
  if btv.bo[buf].endofline ~= false and #lines > 0 then
    text = text .. eol
  end
  if btv.bo[buf].bomb then
    text = "\239\187\191" .. text
  end
  return name, text
end

-- Drop everything kept for `buf`, and any refresh it has pending.
local function forget(buf)
  local s = state[buf]
  if s and s.refresh then
    s.refresh:cancel()
  end
  state[buf] = nil
  told[buf] = nil
end

-- Diff `buf` now and repaint it when the answer lands.
local refresh_now = btv.async(function(buf)
  if not btv.buf.is_valid(buf) then
    forget(buf) -- a late refresh of a buffer already gone: keep nothing for it
    return
  end
  local s = buffer_state(buf)
  s.seq = s.seq + 1
  local seq = s.seq
  local name, text = buffer_source(buf)
  if not name then
    s.hunks = nil
    btv.decor.invalidate({ buf = buf })
    return
  end
  local base = status.base()
  local ok, res = pcall(
    btv.await,
    btv.git.diff_file(name, name, { rev = base.rev, merge_base = base.merge_base, text = text })
  )
  if state[buf] ~= s or s.seq ~= seq then
    return -- overtaken by a newer refresh, or the buffer is gone
  end
  if ok then
    -- A git-ignored file (build output, a local `.env`) is not part of the repository's
    -- changes: marking it all added would only be noise.
    s.hunks = not res.ignored and res.hunks or nil
    s.ignored = res.ignored == true
  else
    s.hunks = nil
    s.ignored = nil
    -- Outside a repository there is simply nothing to mark. Anything else (a base that
    -- does not resolve) is said, once per distinct message.
    if not (type(res) == "table" and res.code == "ENOREPO") then
      local msg = type(res) == "table" and (res.message or res.code) or tostring(res)
      if not said[msg] then
        said[msg] = true
        btv.notify(PREFIX .. msg, btv.log.levels.ERROR)
      end
    end
  end
  if btv.buf.is_valid(buf) then
    btv.decor.invalidate({ buf = buf })
  end
end)

-- Schedule a debounced refresh of `buf`.
function M.refresh(buf)
  if buf == nil or buf == 0 then
    buf = btv.buf.current()
  end
  local s = buffer_state(buf)
  if not s.refresh then
    s.refresh = btv.utils.debounce(function()
      refresh_now(buf)
    end, M.DEBOUNCE_MS)
  end
  s.refresh()
end

-- Refresh the buffers on screen. A hidden buffer is left alone: it is refreshed when it
-- is shown again (`BufEnter`, `BufWinEnter`), so this costs the buffers in view, not
-- every one open.
local function refresh_shown()
  local seen = {}
  for _, win in ipairs(btv.win.list()) do
    local buf = btv.win.buf(win)
    if buf and not seen[buf] then
      seen[buf] = true
      M.refresh(buf)
    end
  end
end

-- Refresh after the base options changed: the buffers on screen, and an error the old
-- base gave is said again if the new one gives it too.
function M.refresh_all()
  said = {}
  refresh_shown()
end

-- The cached hunks of `buf` (`{ old_start, old_count, new_start, new_count }` each, the
-- `btv.git.diff_file` shape), or nil when it has none to show.
function M.get(buf)
  local s = state[buf]
  return s and s.hunks
end

-- Whether the plugin holds any state for `buf` (for the specs: a buffer gone from the
-- editor must leave none behind).
function M._tracked(buf)
  return state[buf] ~= nil
end

-- Whether the last diff of `buf` found its file git-ignored: `true` / `false`, or nil
-- while unknown (not diffed yet, outside a repository, no file).
function M.is_ignored(buf)
  local s = state[buf]
  return s and s.ignored
end

-- The marks for rows `top`..`bot` (0-based, inclusive) of a buffer with `hunks`.
--
-- An added or changed line gets a sign and a line background. Removed lines have no
-- row of their own, so they are a sign alone, on the line below the removal (`‾`), or,
-- when the removal is at the end of the buffer, on the line above it (`_`).
function M.marks(hunks, top, bot, opts)
  opts = opts or {}
  local signs = opts.signs ~= false
  local lines = opts.lines ~= false
  local out = {}
  local function mark(row, sign, sign_hl, line_hl)
    if row < top or row > bot then
      return
    end
    local m = { row, 0 }
    if signs then
      m.sign_text = sign
      m.sign_hl_group = sign_hl
    end
    if lines and line_hl then
      m.line_hl_group = line_hl
    end
    if m.sign_text or m.line_hl_group then
      out[#out + 1] = m
    end
  end
  hunks = hunks or {}
  -- The hunks are in buffer order and do not overlap, so the first one that can reach
  -- `top` is found by bisection and the walk stops past `bot`: a paint costs the hunks
  -- on screen, not every hunk in the buffer. No hunk marks a row past
  -- `new_start + max(new_count, 1) - 1`, nor one before `new_start - 1`.
  local lo, hi = 1, #hunks + 1
  while lo < hi do
    local mid = (lo + hi) // 2
    local h = hunks[mid]
    if h.new_start + math.max(h.new_count, 1) - 1 < top then
      lo = mid + 1
    else
      hi = mid
    end
  end
  for i = lo, #hunks do
    local h = hunks[i]
    if h.new_start - 1 > bot then
      break
    end
    if h.new_count == 0 then
      -- `new_start` is the line before the removal (0 when it removed the top).
      local below = h.new_start -- 0-based row of the line after the removal
      if opts.line_count and below >= opts.line_count then
        mark(below - 1, "_", "GitChangesDeleteSign")
      else
        mark(below, "‾", "GitChangesDeleteSign")
      end
    else
      local add = h.old_count == 0
      -- Only the rows on screen: a huge hunk (a whole untracked file) costs a screenful.
      local first = math.max(h.new_start - 1, top)
      local last = math.min(h.new_start + h.new_count - 2, bot)
      for r = first, last do
        if add then
          mark(r, "▎", "GitChangesAddSign", "GitChangesAddLine")
        else
          mark(r, "▎", "GitChangesChangeSign", "GitChangesChangeLine")
        end
      end
    end
  end
  return out
end

local installed = false

function M.install()
  if installed then
    return
  end
  installed = true

  btv.decor.provider({
    name = "bemtvi-git.hunks",
    -- Only an ordinary buffer can have marks (see `buffer_source`): a terminal, a
    -- quickfix list or a view would cost a call and an empty publish on every repaint.
    bufs = { buftype = { "" } },
    on_range = function(ctx, publish)
      local hunks = M.get(ctx.buf)
      if not hunks then
        publish({})
        return
      end
      publish(M.marks(hunks, ctx.top, ctx.bot, {
        signs = btv.o["git.change_signs"],
        lines = btv.o["git.change_lines"],
        line_count = btv.buf.line_count(ctx.buf),
      }))
    end,
  })

  local events = { "BufReadPost", "BufNewFile", "BufEnter", "BufWinEnter", "BufWritePost" }
  for _, ev in ipairs(events) do
    btv.on(ev, function(a)
      M.refresh(a.buf)
    end)
  end
  for _, ev in ipairs({ "TextChanged", "TextChangedI" }) do
    btv.on(ev, function(a)
      M.refresh(a.buf)
    end)
  end
  -- A commit or checkout made elsewhere may have moved the base. An error already said
  -- (a base that does not resolve) is not said again on every return to the editor.
  btv.on("FocusGained", function()
    refresh_shown()
  end)
  btv.on("BufDelete", function(a)
    forget(a.buf)
  end)
  -- Installed late (a plugin lazy-loaded on `:GitChanges` or a key), the buffers already
  -- on screen had their read and display events before these handlers existed.
  refresh_shown()
end

-- Repaint every buffer with the cached hunks (a display option changed).
function M.repaint()
  for buf in pairs(state) do
    if btv.buf.is_valid(buf) then
      btv.decor.invalidate({ buf = buf })
    end
  end
end

return M
