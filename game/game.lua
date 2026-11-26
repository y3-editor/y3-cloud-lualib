-- 游戏级接口：运行环境判据 + 工程事件总线（继承 CustomEvent）

---@class Game: CustomEvent
local M = Class 'Game'
Extends('Game', 'CustomEvent')

---当前是否为正式环境；接口不可用时按正式环境处理（fail-closed）
---@return boolean
function M.is_prod()
    if type(MsIsProdEnv) ~= 'function' then
        return true
    end
    return MsIsProdEnv() == true
end

---是否允许调试能力（执行客户端下发的代码、GM 通道、调试探针等）
---@return boolean
function M.is_debug()
    return y3.config.debug == true
end

---测试设施（GM 通道 / 调试探针 / 示例自测）是否放行：仅非正式环境可用
---@return boolean
function M.allow_test()
    return not M.is_prod()
end

---@class Game.Subscription
---@field trg Trigger
---@field owner string? 注册者所在的 include 模块；热重载时按它注销

---@type Game.Subscription[]
local subscriptions = {}

local CustomEventClass = Class 'CustomEvent'

---订阅工程事件；重载后由 clear_reloadable 注销，模块重新注册
function M:event_on(...)
    local trg = CustomEventClass.event_on(self, ...)
    subscriptions[#subscriptions + 1] = {
        trg = trg,
        owner = y3.reload.getCurrentIncludeName(),
    }
    return trg
end

---触发工程事件（通知模式，回调按注册顺序执行）
---@param event_name string
---@param ... any
function M:emit(event_name, ...)
    self:event_notify(event_name, ...)
end

---注销由 include 模块注册的订阅；热重载前调用，重载后模块会重新注册
function M.clear_reloadable()
    local kept = {}
    for i = 1, #subscriptions do
        local item = subscriptions[i]
        if item.owner then
            Delete(item.trg)
        else
            kept[#kept + 1] = item
        end
    end
    subscriptions = kept
end

return M
