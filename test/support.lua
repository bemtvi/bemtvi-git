-- Shared fixtures for the specs: throwaway git repositories built with the `git` CLI,
-- isolated from the host's git config (identity, signing, default branch). Loaded with
-- `dofile` from each spec; the runner only sources `*_spec.lua`.

local S = {}

local ENV = {
  GIT_CONFIG_GLOBAL = "/dev/null",
  GIT_CONFIG_NOSYSTEM = "1",
  GIT_AUTHOR_NAME = "bemtvi test",
  GIT_AUTHOR_EMAIL = "test@bemtvi",
  GIT_COMMITTER_NAME = "bemtvi test",
  GIT_COMMITTER_EMAIL = "test@bemtvi",
}

-- Run `git ...` in `dir`; fail the test loud on a non-zero exit.
function S.git(dir, ...)
  local r = btv.await(btv.run({ cmd = "git", args = { ... }, cwd = dir, env = ENV }))
  if r.code ~= 0 then
    error(("git %s failed: %s"):format(table.concat({ ... }, " "), r.stderr), 0)
  end
  return r.stdout
end

-- Write `text` to `dir/rel`, creating parent directories.
function S.write(dir, rel, text)
  local path = btv.utils.joinpath(dir, rel)
  local parent = btv.utils.dirname(path)
  btv.await(btv.fs.mkdir(parent, { recursive = true }))
  btv.await(btv.fs.write(path, text))
  return path
end

-- Set `dir/rel`'s modification time to `stamp` (`touch -t` format, `YYYYMMDDhhmm`).
function S.touch(dir, rel, stamp)
  local r = btv.await(btv.run({ cmd = "touch", args = { "-t", stamp, rel }, cwd = dir }))
  if r.code ~= 0 then
    error("touch failed: " .. r.stderr, 0)
  end
end

-- A repository on `main` with three committed files.
function S.repo()
  local dir = btv.test.tempdir()
  S.git(dir, "init", "-q", "-b", "main")
  S.write(dir, "keep.txt", "keep\n")
  S.write(dir, "mod.txt", "one\ntwo\nthree\n")
  S.write(dir, "gone.txt", "bye\n")
  S.git(dir, "add", "-A")
  S.git(dir, "commit", "-q", "-m", "init")
  return dir
end

return S
