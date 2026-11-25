-- setup(): option defaults, validation, idempotence.

local expect = btv.test.expect

local here = btv.utils.dirname(debug.getinfo(1, "S").source:sub(2))
local root = btv.utils.dirname(here)

btv.test.describe("setup", function()
  btv.test.it("defines the diff-base options with their defaults", function()
    require("bemtvi-git").setup({})
    expect(btv.o["git.base"]).to_be("HEAD")
    expect(btv.o["git.merge_base"]).to_be(false)
  end)

  btv.test.it("takes new defaults, and a value set through btv.o still wins", function()
    btv.o["git.merge_base"] = false
    require("bemtvi-git").setup({ base = "main", merge_base = true })
    expect(btv.o["git.base"]).to_be("main")
    expect(btv.o["git.merge_base"]).to_be(false)
    require("bemtvi-git").setup({})
  end)

  btv.test.it("rejects an unknown or mistyped option", function()
    local ok, err = pcall(require("bemtvi-git").setup, { bse = "main" })
    expect(ok).to_be(false)
    expect(err:find("unknown option 'bse'", 1, true) ~= nil).to_be(true)
    ok, err = pcall(require("bemtvi-git").setup, { merge_base = "yes" })
    expect(ok).to_be(false)
    expect(err:find("merge_base must be a boolean", 1, true) ~= nil).to_be(true)
  end)

  btv.test.it("keeps the user's options when the plugin/ script runs after init.lua", function()
    -- An unmanaged plugin's `plugin/` scripts are sourced after `init.lua`, so the
    -- user's own setup() has already run by the time the auto-setup does.
    btv.o["git.base"] = nil
    require("bemtvi-git").setup({ base = "main", change_lines = false })
    dofile(btv.utils.joinpath(root, "plugin", "bemtvi-git.lua"))
    expect(btv.o["git.base"]).to_be("main")
    expect(btv.o["git.change_lines"]).to_be(false)
    require("bemtvi-git").setup({})
  end)
end)
