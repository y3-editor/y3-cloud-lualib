-- 云脚本配置：y3.config
-- debug 默认按运行环境推断（正式环境为 false），业务可在入口加载后按需覆盖

---@class Y3Config
local M = {
    --- 是否允许调试能力（执行客户端下发的代码等）
    debug = not y3.game.is_prod(),
}

return M
