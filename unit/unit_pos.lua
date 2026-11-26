-- 单位位置：寻路段采样上报与惰性插值
-- 通知 Unit.Pos.Report（客户端 reporter → 云）：{ seq, start?, move?, stop? }

---@class Unit
local M = Class 'Unit'

-- 客户端上报速度校验：上报速度超过速度上限即判为非法采样
-- 上限由外部通过 y3.unit.set_speed_limit_provider 提供（容差自己乘进去），不设置时不做速度校验

-- 计算速度时的采样余量（毫秒）：容忍上报与引擎帧的错位，避免边界落在帧上把正常移动判成超速
local SPEED_WINDOW_MS = 100

-- 采样过期阈值（毫秒）：客户端重开（.rr / 重载游戏）后不会再上报，长于该值没有新采样即视为已停止，
-- 否则云端会一直认为单位在寻路
local STALE_MOVING_MS = 1000

---@type table<integer, true>
local warned_speed = {}

---@type fun(unit: Unit): number??
local speed_limit_provider

---@type fun(unit: Unit, speed: number, limit: number)?
local speed_violation

---启用后云脚本会监控单位移动速度是否合法，但也意味着所有的传送功能也得由云脚本发起。
---你需要在回调中传入一个合法的移动速度（考虑到网络延迟可以略大一些）。
---当发生异常移速时会尝试将单位拉回（当然作弊者可以屏蔽掉拉回）。
---第二个回调会在移速异常时调用，你可以用来做记录。
---@param callback fun(unit: Unit): number?? 返回该单位的速度上限（单位/秒，容差自行乘入），返回 nil 表示该单位不校验
---@param on_violation? fun(unit: Unit, speed: number, limit: number) 移速异常时的回调
function y3.unit.set_speed_limit_provider(callback, on_violation)
    speed_limit_provider = callback
    speed_violation = on_violation
end

---记录当前位置与时间：唯一的位置写入点，同时作为速度校验的基准
---@param x number
---@param y number
---@param now? integer 毫秒，缺省用 y3.timer.clock()
function M:update_pos(x, y, now)
    local new_pos = { x = x, y = y, t = now or y3.timer.clock() }
    self.last_pos = self.current_pos or new_pos
    self.current_pos = new_pos
    self._pos_cache = nil
end

---客户端上报速度（单位/秒），无基准或时间差为 0 时返回 nil
---@param x number
---@param y number
---@param now integer
---@return number?
function M:get_client_speed(x, y, now)
    local last = self.last_pos
    if not last then
        return nil
    end
    local dt = (now + SPEED_WINDOW_MS - last.t) / 1000
    if dt <= 0 then
        return nil
    end
    local dx, dy = x - last.x, y - last.y
    return math.sqrt(dx * dx + dy * dy) / dt
end

---校验上报位置：合法则更新基准，不合法退回上一个位置
---@param x number
---@param y number
---@param now integer
---@return boolean
function M:accept_pos(x, y, now)
    local limit = speed_limit_provider and speed_limit_provider(self)
    if not limit then
        self:update_pos(x, y, now)
        return true
    end

    local speed = self:get_client_speed(x, y, now)
    if speed == nil then
        self:update_pos(x, y, now)
        return true
    end

    if speed > limit then
        if not warned_speed[self.uid] then
            warned_speed[self.uid] = true
            Log.warn('y3.unit.pos: report rejected, uid={} speed={%.1f} limit={%.1f}' % {
                tostring(self.uid), speed, limit
            })
        end
        if speed_violation then
            xpcall(speed_violation, Log.error, self, speed, limit)
        end
        self:teleport(y3.point(self.current_pos.x, self.current_pos.y))
        return false
    end

    self:update_pos(x, y, now)
    return true
end

---@param is_moving boolean
function M:mark_moving(is_moving)
    self._is_moving = is_moving
    self._pos_cache = nil
    if not is_moving then
        self.last_pos = self.current_pos
        warned_speed[self.uid] = nil
    end
end

---@return boolean
function M:is_moving()
    return self._is_moving == true
end

---@param player Player
---@param data any
local function on_report(player, data)
    local now = y3.timer.clock()

    local start_list = data.start
    if start_list then
        -- start 只是"开始寻路"的信号，起点用云端当前（= 上次结束）位置，并把基准时间刷新到 now
        for _, uid in ipairs(start_list) do
            local unit = y3.unit.get(uid)
            if unit then
                unit:mark_moving(true)
                unit:get_xy(now)
            end
        end
    end

    local move_list = data.move
    if move_list then
        for uid, pos in pairs(move_list) do
            local unit = y3.unit.get(uid)
            if unit then
                unit:accept_pos(pos.x, pos.y, now)
            end
        end
    end

    local stop_list = data.stop
    if stop_list then
        for uid, pos in pairs(stop_list) do
            local unit = y3.unit.get(uid)
            if unit then
                unit:accept_pos(pos.x, pos.y, now)
                unit:mark_moving(false)
            end
        end
    end
end

y3.client.rpc.register('$Unit.Pos.Report', on_report)

---当前最优位置：移动中在 last_pos → current_pos 之间插值，静止用 current_pos
---@param now? integer 毫秒时刻，缺省用 y3.timer.clock()
---@return Point
function M:get_pos(now)
    local x, y = self:get_xy(now)
    return y3.point(x, y)
end

---当前最优位置的坐标（性能敏感处用这个，免去建对象）
---@param now? integer 毫秒时刻，缺省用 y3.timer.clock()
---@return number x
---@return number y
function M:get_xy(now)
    now = now or y3.timer.clock()

    local cur = self.current_pos
    if not cur then
        return self.data.x, self.data.y
    end

    -- 长时间没有新采样：客户端可能已重开，寻路状态不可信，落定为停步
    if self._is_moving and now - cur.t > STALE_MOVING_MS then
        self:mark_moving(false)
    end

    local cache = self._pos_cache
    if cache then
        return cache.x, cache.y
    end

    local x, y = cur.x, cur.y
    local last = self.last_pos
    if self._is_moving and last and now > last.t and now < cur.t then
        local span = cur.t - last.t
        local k = span > 0 and (now - last.t) / span or 1
        x = last.x + (cur.x - last.x) * k
        y = last.y + (cur.y - last.y) * k
    end

    self._pos_cache = { x = x, y = y }
    return x, y
end

-- 调试绘制：勾选了「显示单位位置」的玩家
local DEBUG_INTERVAL = 0.2

---@type table<integer, true>
local debug_viewers = {}

---@type table<integer, { x: number, y: number, face: number }>
local debug_last = {}

local debug_need_full = false

local function debug_flush()
    if not next(debug_viewers) then
        return
    end

    local units = {}
    for uid, unit in pairs(y3.unit.all()) do
        local x, y = unit:get_xy()
        local face = unit.data.face or 0
        local last = debug_last[uid]
        if debug_need_full or not last or last.x ~= x or last.y ~= y or last.face ~= face then
            units[uid] = { x = x, y = y, face = face }
            debug_last[uid] = { x = x, y = y, face = face }
        end
    end
    debug_need_full = false

    if next(units) then
        y3.client.rpc.broadcast('$Unit.Pos.Debug', { units = units })
    end
end

y3.timer.loop(DEBUG_INTERVAL, debug_flush)

y3.client.rpc.register('$Unit.DebugPos', function (player, data)
    local enable = type(data) == 'table' and data.enable
    if enable then
        debug_viewers[player:get_id()] = true
        debug_need_full = true
    else
        debug_viewers[player:get_id()] = nil
    end
end)
