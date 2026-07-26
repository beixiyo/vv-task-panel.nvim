-- Package-manager detection shared by providers and script signs

local M = {}

---@param package_dir string
---@return 'pnpm' | 'yarn' | 'bun' | 'npm'
function M.detect(package_dir)
  local dir = package_dir
  while dir and dir ~= '/' and dir ~= '' do
    if vim.uv.fs_stat(dir .. '/pnpm-lock.yaml') then return 'pnpm' end
    if vim.uv.fs_stat(dir .. '/bun.lockb') or vim.uv.fs_stat(dir .. '/bun.lock') then return 'bun' end
    if vim.uv.fs_stat(dir .. '/yarn.lock') then return 'yarn' end
    if vim.uv.fs_stat(dir .. '/package-lock.json') then return 'npm' end

    local parent = vim.fn.fnamemodify(dir, ':h')
    if parent == dir then break end
    dir = parent
  end
  return 'npm'
end

return M
