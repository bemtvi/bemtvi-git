-- Auto-loaded when the plugin is on the runtimepath. Installs the picker, the command
-- and the options with their defaults so the plugin works without a config line. A
-- user's own require("bemtvi-git").setup({...}) wins whichever runs first: before this
-- script (an `init.lua` with the plugin on the runtimepath), this skips the auto-setup;
-- after it (a `btv.plugins` config), setup() is idempotent and re-applies their options.
require("bemtvi-git")._autoload()
