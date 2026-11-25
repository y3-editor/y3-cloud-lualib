-- 云端逻辑单位：创建 / 移除 / 移动命令 / 属性变更，同一 tick 合成一条广播
-- 方法 Unit.GetAll：客户端拉全量；通知 Unit.Sync：{ create, remove, attribute, command }

---@class Unit.Data
---@field key integer 物编单位 key（py.UnitKey）
---@field x number 出生点
---@field y number
---@field face? number 朝向
---@field owner? integer 归属玩家 role_id

---@class Unit: CustomEvent, GCHost
---@field uid integer
---@field data Unit.Data
---@field current_pos? { x: number, y: number, t: integer } 最新位置与时刻
---@field last_pos? { x: number, y: number, t: integer } 上一个位置与时刻
---@field _is_moving? boolean 是否在寻路
---@field target_pos? { x: number, y: number } move_to 下发的目标点
---@field _pos_cache? { x: number, y: number }
local M = Class 'Unit'
Extends('Unit', 'CustomEvent')
Extends('Unit', 'GCHost')

-- 属性相关的静态接口由 unit-attr.lua 实现
---@class Unit.API
---@field attr_drain fun(): table<integer, table<string, number>>
---@field attr_all fun(): table<integer, table<string, number>>
local API = y3.unit

-- 合并窗口（秒）
local FLUSH_INTERVAL = 0.1

local seq = 0

---@type table<integer, Unit>
local cache = {}

---@type table<integer, Unit>
local created = {}

---@type table<integer, true>
local removed = {}

---@type table<integer, table<string, any>>
local commands = {}

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
    commands[self.uid] = nil
    removed[self.uid] = true
end

---@param command table<string, any>
function M:push_command(command)
    commands[self.uid] = command
end

---客户端表现所需的单位数据（位置取当前值）
---@return Unit.Data
function M:get_sync_data()
    local x, y = self:get_pos()
    return {
        key = self.data.key,
        x = x,
        y = y,
        face = self.data.face,
        owner = self.data.owner,
    }
end

---下达移动命令：客户端驱动 Y3 寻路，位置仍以客户端上报为准
---@param x number
---@param y number
function M:move_to(x, y)
    self.target_pos = { x = x, y = y }
    self:mark_moving(true)
    self:push_command({ move_to = { x = x, y = y } })
end

---直接改位置，不经过寻路
---@param x number
---@param y number
function M:teleport(x, y)
    self.target_pos = nil
    self:update_pos(x, y)
    self:push_command({ teleport = { x = x, y = y } })
end

---停步：落点用当前最优位置
function M:stop()
    local x, y = self:get_pos()
    self.target_pos = nil
    self:mark_moving(false)
    self:update_pos(x, y)
    self:push_command({ stop = true })
end

local function flush()
    local create_list = created
    local remove_list = removed
    local command_list = commands
    created = {}
    removed = {}
    commands = {}
    local attribute = API.attr_drain()
    if not next(create_list) and not next(remove_list) and not next(attribute) and not next(command_list) then
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
        command = command_list,
    })
end

y3.timer.loop(FLUSH_INTERVAL, flush)

y3.client.rpc.register('$Unit.GetAll', function ()
    local units = {}
    for uid, unit in pairs(cache) do
        units[uid] = unit:get_sync_data()
    end
    return {
        units = units,
        attribute = API.attr_all(),
    }
end)

---创建云端逻辑单位
---@param key integer 物编单位 key（py.UnitKey）
---@param x number
---@param y number
---@param face? number 朝向
---@param owner? integer 归属玩家 role_id
---@return Unit
function y3.unit.create(key, x, y, face, owner)
    seq = seq + 1
    local unit = New 'Unit' (seq, {
        key = key,
        x = x,
        y = y,
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
