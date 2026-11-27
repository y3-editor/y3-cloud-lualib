-- 云端逻辑单位：创建 / 移除 / 属性变更按 100ms 合并广播，移动命令当场单独下发
-- 方法 Unit.GetAll：客户端拉全量；通知 Unit.Sync：{ create, remove, attribute, command }

---@class Unit.Data
---@field key integer 物编单位 key（py.UnitKey）
---@field x number
---@field y number
---@field face? number
---@field owner? integer 归属玩家 role_id

---@class Unit: CustomEvent, GCHost
local M = Class 'Unit'
Extends('Unit', 'CustomEvent')
Extends('Unit', 'GCHost')

---@type integer
M.uid = 0

-- 合并窗口（秒）
local FLUSH_INTERVAL = 0.1

local seq = 0

---@type table<integer, Unit>
local cache = {}

---@type table<integer, Unit>
local created = {}

---@type table<integer, true>
local removed = {}

local function flush()
    local create_list = created
    local remove_list = removed
    created = {}
    removed = {}
    local attribute = y3.unit.attr_drain()
    if not next(create_list) and not next(remove_list) and not next(attribute) then
        return
    end

    local payload = {}
    for uid, unit in pairs(create_list) do
        payload[uid] = unit:get_sync_data()
    end
    y3.client.rpc.broadcast('$Unit.Sync', {
        create = payload,
        remove = remove_list,
        attribute = attribute,
    })
end

---@param uid integer
---@param data Unit.Data
function M:__init(uid, data)
    self.uid = uid
    self.data = data
    self:update_pos(data.x, data.y)
end

---移除这个单位
function M:remove()
    self:mark_moving(false)
    cache[self.uid] = nil
    created[self.uid] = nil
    removed[self.uid] = true
end

---命令当场下发
---@param command table<string, any>
function M:push_command(command)
    if created[self.uid] then
        -- 单位还没同步给客户端，先补发创建，否则命令没有接收者
        flush()
    end
    y3.client.rpc.broadcast('$Unit.Sync', { command = { [self.uid] = command } })
end

---客户端表现所需的单位数据（位置取当前值）
---@return Unit.Data
function M:get_sync_data()
    local x, y = self:get_xy()
    return {
        key = self.data.key,
        x = x,
        y = y,
        face = self.data.face,
        owner = self.data.owner,
    }
end

---下达移动命令：客户端驱动 Y3 寻路，位置仍以客户端上报为准
---@param point Point 目标点
function M:move_to(point)
    local x, y = point:get_x(), point:get_y()
    self.target_pos = { x = x, y = y }
    self:mark_moving(true)
    self:push_command({ move_to = { x = x, y = y } })
end

---直接改位置，不经过寻路
---@param point Point 目标点
function M:teleport(point)
    local x, y = point:get_x(), point:get_y()
    self.target_pos = nil
    self:mark_moving(false)
    self:update_pos(x, y)
    self:push_command({ teleport = { x = x, y = y } })
end

---停步：落点用当前最优位置
function M:stop()
    local x, y = self:get_xy()
    self.target_pos = nil
    self:mark_moving(false)
    self:update_pos(x, y)
    self:push_command({ stop = true })
end

y3.timer.loop(FLUSH_INTERVAL, flush)

y3.client.rpc.register('$Unit.GetAll', function ()
    local units = {}
    for uid, unit in pairs(cache) do
        units[uid] = unit:get_sync_data()
    end
    return {
        units = units,
        attribute = y3.unit.attr_all(),
    }
end)

---创建云端逻辑单位
---@param key integer 物编单位 key（py.UnitKey）
---@param point Point 出生点
---@param face? number 朝向
---@param owner? integer 归属玩家 role_id
---@return Unit
function y3.unit.create(key, point, face, owner)
    seq = seq + 1
    local unit = New 'Unit' (seq, {
        key = key,
        x = point:get_x(),
        y = point:get_y(),
        face = face,
        owner = owner,
    })
    cache[unit.uid] = unit
    created[unit.uid] = unit
    removed[unit.uid] = nil
    return unit
end

---@param uid integer
---@return Unit?
function y3.unit.get(uid)
    return cache[uid]
end

---@return table<integer, Unit>
function y3.unit.all()
    return cache
end

---清空所有单位（会话重置用，不下发 remove）
function y3.unit.clear()
    for _, unit in pairs(cache) do
        unit:mark_moving(false)
    end
    cache = {}
    created = {}
    removed = {}
end
