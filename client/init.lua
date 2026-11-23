-- 通讯层命名空间：功能按模块挂在 y3.client.<name> 下
-- 当前实现：y3.client.rpc（请求 / 应答 / 通知 / 广播）

---@class Client
local M = {}

M.rpc = require 'y3.client.rpc'

return M
