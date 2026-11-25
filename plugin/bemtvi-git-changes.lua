-- Auto-loaded when the plugin is on the runtimepath. Installs the picker, the command
-- and the options with their defaults so the plugin works without a config line;
-- setup() is idempotent, so a user's own require("bemtvi-git-changes").setup({...})
-- just re-applies with their options.
require("bemtvi-git-changes").setup({})
