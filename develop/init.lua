-- 开发 / 调试能力命名空间：y3.develop
-- eval 模块在加载时向 y3.client.rpc 注册 Develop.Eval

---@class Develop
local M = {}

M.eval = require 'y3.develop.eval'

return M
