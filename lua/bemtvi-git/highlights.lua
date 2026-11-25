-- bemtvi-git.highlights — the plugin's colours, derived from the active theme.
--
-- Every group is installed with `btv.hl.fallback`, so a colorscheme (or the user) that
-- defines one keeps it, and the defaults are re-derived from `btv.hl.palette()` on every
-- `ColorScheme` so they follow a theme switch.

local M = {}

-- defaults() -> `name -> spec` for the active theme.
function M.defaults()
  local p = btv.hl.palette()
  return {
    -- Picker rows, one per kind of change.
    GitChangesAdded = { fg = p.green },
    GitChangesModified = { fg = p.blue },
    GitChangesDeleted = { fg = p.red },
    GitChangesRenamed = { fg = p.purple },
    GitChangesConflict = { fg = p.orange, bold = true },
    GitChangesUntracked = { fg = p.yellow },
  }
end

function M.apply()
  for name, spec in pairs(M.defaults()) do
    btv.hl.fallback(name, spec)
  end
end

-- The picker row group for a kind.
local ROW = {
  added = "GitChangesAdded",
  modified = "GitChangesModified",
  deleted = "GitChangesDeleted",
  renamed = "GitChangesRenamed",
  conflict = "GitChangesConflict",
  untracked = "GitChangesUntracked",
}

function M.row(kind)
  return ROW[kind]
end

return M
