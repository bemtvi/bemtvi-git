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
-- What refreshes a buffer: reading it, entering it, editing it, writing it, the editor
-- regaining the focus (a commit or checkout made elsewhere moves the base), and a change
-- of the base options.

local status = require("bemtvi-git.status")

local M = {}

-- How long a burst of edits settles before the buffer is diffed again.
M.DEBOUNCE_MS = 100

local PREFIX = "bemtvi-git: "

-- buf -> { hunks = {...} | nil, seq = <latest request>, refresh = <debounced fn> }
local state = {}

-- buf -> true once the plugin has said why it cannot mark that buffer.
local told = {}

local function buffer_state(buf)
  local s = state[buf]
  if not s then
    s = { seq = 0 }
    state[buf] = s
  end
  return s
end

-- The buffer's file and the bytes git would compare, or nil when the buffer is not one
-- the plugin marks (no file, a special buffer). A buffer whose file is in an encoding
-- other than UTF-8 is skipped and said so once: its text here is UTF-8, its blob at the
-- base is not, so every non-ASCII line would read as changed.
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
    if not told[buf] then
      told[buf] = true
      btv.notify(
        PREFIX .. "no change marks for " .. name .. ": its encoding is " .. enc .. ", not utf-8",
        btv.log.levels.WARN
      )
    end
    return nil
  end
  local lines = btv.buf.lines(buf, 0, -1)
  local eol = btv.bo[buf].fileformat == "dos" and "\r\n" or "\n"
  local text = table.concat(lines, eol)
  if btv.bo[buf].endofline ~= false and #lines > 0 then
    text = text .. eol
  end
  if btv.bo[buf].bomb then
    text = "\239\187\191" .. text
  end
  return name, text
end

-- Diff `buf` now and repaint it when the answer lands.
local refresh_now = btv.async(function(buf)
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
      if M._last_error ~= msg then
        M._last_error = msg
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

-- Refresh every loaded buffer (the base or the repository moved under all of them).
function M.refresh_all()
  M._last_error = nil
  for _, buf in ipairs(btv.buf.list()) do
    M.refresh(buf)
  end
end

local function forget(buf)
  local s = state[buf]
  if s and s.refresh then
    s.refresh:cancel()
  end
  state[buf] = nil
  told[buf] = nil
end

-- The cached hunks of `buf` (`{ old_start, old_count, new_start, new_count }` each, the
-- `btv.git.diff_file` shape), or nil when it has none to show.
function M.get(buf)
  local s = state[buf]
  return s and s.hunks
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
  for _, h in ipairs(hunks or {}) do
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
      for r = h.new_start - 1, h.new_start + h.new_count - 2 do
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

  for _, ev in ipairs({ "BufReadPost", "BufNewFile", "BufEnter", "BufWritePost" }) do
    btv.on(ev, function(a)
      M.refresh(a.buf)
    end)
  end
  for _, ev in ipairs({ "TextChanged", "TextChangedI" }) do
    btv.on(ev, function(a)
      M.refresh(a.buf)
    end)
  end
  btv.on("FocusGained", function()
    M.refresh_all()
  end)
  btv.on("BufDelete", function(a)
    forget(a.buf)
  end)
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
