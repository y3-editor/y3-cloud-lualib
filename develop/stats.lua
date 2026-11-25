-- 云脚本状态查询：$Develop.Stats，供客户端仪表盘拉取
-- 帧耗时来源：MsGetScriptRunStat()
--   room_cur_last_tick_ms 每帧耗时：10 ms 采一次，用于最近 1 秒平均
--   room_cur_max_tick_ms  累计最大耗时：取相邻采样的增量，落在 10 秒窗口内的最大值即最近 10 秒最大耗时
-- 暂停/求值期间墙钟照走，会出现秒级离群值，超过阈值直接丢弃

local config = require 'y3.config'

local SAMPLE_INTERVAL = 0.01
local AVG_WINDOW_MS = 1000
local MAX_WINDOW_MS = 10000
local PAUSE_THRESHOLD_MS = 1000

---@type { t: integer, ms: number }[]
local tick_samples = {}

---@type { t: integer, ms: number }[]
local peak_samples = {}

---@type number?
local last_max

local function push(list, now, ms, window)
    list[#list + 1] = { t = now, ms = ms }
    while list[1] and now - list[1].t > window do
        table.remove(list, 1)
    end
end

local function sample()
    local stat = MsGetScriptRunStat()
    if type(stat) ~= 'table' then
        return
    end
    local now = y3.timer.clock()

    local last = stat.room_cur_last_tick_ms
    if type(last) == 'number' and last < PAUSE_THRESHOLD_MS then
        push(tick_samples, now, last, AVG_WINDOW_MS)
    end

    local max = stat.room_cur_max_tick_ms
    if type(max) == 'number' then
        if last_max and max >= last_max then
            local delta = max - last_max
            if delta > 0 and delta < PAUSE_THRESHOLD_MS then
                push(peak_samples, now, delta, MAX_WINDOW_MS)
            end
        elseif last_max and max < last_max then
            -- 计数被重置（切房间等），以新值为基准
            peak_samples = {}
        end
        last_max = max
    end
end

y3.timer.loop(SAMPLE_INTERVAL, sample)

---最近 1 秒平均耗时
---@return number?
local function tick_avg()
    local sum = 0
    for _, item in ipairs(tick_samples) do
        sum = sum + item.ms
    end
    return #tick_samples > 0 and sum / #tick_samples or nil
end

---最近 10 秒最大耗时
---@return number?
local function tick_max()
    local max
    for _, item in ipairs(peak_samples) do
        if max == nil or item.ms > max then
            max = item.ms
        end
    end
    return max
end

---@return table|nil
---@return string|nil
local function on_stats()
    if not config.debug then
        return nil, 'stats_disabled'
    end

    return {
        time = MsGetRoomGameTime(),
        mem_kb = collectgarbage('count'),
        players = MsGetRoomPlayerCount(),
        tick_avg_1s = tick_avg(),
        tick_max_10s = tick_max(),
    }
end

y3.client.rpc.register('$Develop.Stats', on_stats)

y3.develop.stats = on_stats
