-- setup(): option defaults, validation, idempotence.

local expect = btv.test.expect

btv.test.describe("setup", function()
  btv.test.it("defines the diff-base options with their defaults", function()
    require("bemtvi-git-changes").setup({})
    expect(btv.o["gitchanges.base"]).to_be("HEAD")
    expect(btv.o["gitchanges.merge_base"]).to_be(false)
  end)

  btv.test.it("takes new defaults, and a value set through btv.o still wins", function()
    btv.o["gitchanges.merge_base"] = false
    require("bemtvi-git-changes").setup({ base = "main", merge_base = true })
    expect(btv.o["gitchanges.base"]).to_be("main")
    expect(btv.o["gitchanges.merge_base"]).to_be(false)
    require("bemtvi-git-changes").setup({})
  end)

  btv.test.it("rejects an unknown or mistyped option", function()
    local ok, err = pcall(require("bemtvi-git-changes").setup, { bse = "main" })
    expect(ok).to_be(false)
    expect(err:find("unknown option 'bse'", 1, true) ~= nil).to_be(true)
    ok, err = pcall(require("bemtvi-git-changes").setup, { merge_base = "yes" })
    expect(ok).to_be(false)
    expect(err:find("merge_base must be a boolean", 1, true) ~= nil).to_be(true)
  end)
end)
