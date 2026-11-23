-- 云脚本定时器：封装内置 Timer，语义对齐客户端 y3.ltimer
-- 时间单位统一为秒（内部换算成整数毫秒，最小 1 ms）；回调收到 (timer, 次数)

---@class CloudTimer
---@field id integer 引擎定时器 id
---@field time number 间隔秒数
---@field count integer 已触发次数
---@field max_count integer 触发上限，0 为无限
---@field removed boolean 是否已取消
---@field on_timer fun(timer: CloudTimer, count: integer)
local CloudTimer = Class 'CloudTimer'

---@param time number 秒
---@param count integer 触发次数，0 表示无限
---@param on_timer fun(timer: CloudTimer, count: integer)
function CloudTimer:__init(time, count, on_timer)
    self.time = time
    self.max_count = count
    self.count = 0
    self.removed = false
    self.on_timer = on_timer

    local interval = math.max(1, math.floor(time * 1000 + 0.5))
    self.id = Timer.new_timer(interval, function ()
        return self:run()
    end)
end

---@return boolean 是否继续触发
function CloudTimer:run()
    if self.removed then
        return false
    end

    self.count = self.count + 1
    local ok, err = pcall(self.on_timer, self, self.count)
    if not ok then
        Log.error('y3.timer: callback error, ' .. tostring(err))
    end

    if self.removed then
        return false
    end
    if self.max_count > 0 and self.count >= self.max_count then
        self:remove()
        return false
    end
    return true
end

---取消定时器；可从回调内部调用
function CloudTimer:remove()
    if self.removed then
        return
    end
    self.removed = true
    Timer.cancel_timer(self.id)
end

---@class CloudTimers
local M = {}

---等待 time 秒后触发一次
---@param time number 秒
---@param on_timer fun(timer: CloudTimer, count: integer)
---@return CloudTimer
function M.wait(time, on_timer)
    return New 'CloudTimer' (time, 1, on_timer)
end

---每 time 秒触发一次，直到 remove
---@param time number 秒
---@param on_timer fun(timer: CloudTimer, count: integer)
---@return CloudTimer
function M.loop(time, on_timer)
    return New 'CloudTimer' (time, 0, on_timer)
end

---每 time 秒触发一次，共 count 次
---@param time number 秒
---@param count integer 次数
---@param on_timer fun(timer: CloudTimer, count: integer)
---@return CloudTimer
function M.loop_count(time, count, on_timer)
    return New 'CloudTimer' (time, count, on_timer)
end

return M
