# 仅使用已有工具；在隔离 HOME/工作目录前解析
# 这些可选源码覆盖项仅在显式指定时转发
if [ -n "${VV_ICONS:-}" ]; then
  vv_test_dependency VV_ICONS vv-icons.nvim lua/vv-icons/init.lua
fi
if [ -n "${VV_BUFFERLINE:-}" ]; then
  vv_test_dependency VV_BUFFERLINE vv-bufferline.nvim lua/vv-bufferline/init.lua
fi
# 在 HOME 隔离前查询本机已安装的真实 Rust bin，避免把依赖 HOME 的 rustup proxy 带入 child
if [ -z "${VV_TEST_TOOLCHAIN_BIN:-}" ] && command -v rustup >/dev/null 2>&1; then
  vv_cargo=$(rustup which cargo 2>/dev/null || :)
  if [ -n "$vv_cargo" ]; then
    VV_TEST_TOOLCHAIN_BIN=$(dirname -- "$vv_cargo")
  fi
fi

if [ -n "${VV_TEST_TOOLCHAIN_BIN:-}" ]; then
  vv_test_path VV_TEST_TOOLCHAIN_BIN "$VV_TEST_TOOLCHAIN_BIN" cargo rustc
  PATH="$VV_TEST_TOOLCHAIN_BIN:$PATH"
  export PATH
fi
