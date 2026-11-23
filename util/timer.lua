-- 云脚本定时器：参考客户端 y3.ltimer 自实现调度
-- 引擎 Timer 的回调会绑在「创建它的协程」上，业务里在协程内建 Timer 会互相干扰，
-- 所以这里只在入口加载时（主线程）建一个脉冲定时器，用它推进所有业务定时器。
-- 时间单位对外是秒，内部按脉冲累加毫秒。

local TICK_MS = 10

---@class CloudTimer
---@field time_ms integer 间隔毫秒
---@field count integer 已触发次数
---@field max_count integer 触发上限，0 为无限
---@field removed boolean 是否已取消
---@field last_ms integer 上次触发时刻
---@field on_timer fun(timer: CloudTimer, count: integer)
local CloudTimer = Class 'CloudTimer'

---@type CloudTimer[]
local timers = {}

local now_ms = 0

---@param time number 秒
---@param count integer 触发次数，0 表示无限
---@param on_timer fun(timer: CloudTimer, count: integer)
function CloudTimer:__init(time, count, on_timer)
    self.time_ms = math.max(1, math.floor(time * 1000 + 0.5))
    self.max_count = count
    self.count = 0
    self.removed = false
    self.last_ms = now_ms
    self.on_timer = on_timer

    timers[#timers + 1] = self
end

---@param current_ms integer
---@return boolean 是否继续保留
function CloudTimer:update(current_ms)
    if self.removed then
        return false
    end

    if current_ms - self.last_ms < self.time_ms then
        return true
    end

    self.last_ms = current_ms
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

    for i = #timers, 1, -1 do
        if timers[i] == self then
            table.remove(timers, i)
            break
        end
    end
end

local function tick()
    now_ms = now_ms + TICK_MS

    local snapshot = {}
    for i = 1, #timers do
        snapshot[i] = timers[i]
    end

    for i = 1, #snapshot do
        snapshot[i]:update(now_ms)
    end
    return true
end

Timer.new_timer(TICK_MS, tick)

---@class CloudTimers
local M = {}

---当前调度时刻（毫秒）
---@return integer
function M.clock()
    return now_ms
end

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
