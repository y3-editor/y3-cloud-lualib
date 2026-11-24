-- 云端逻辑单位：创建 / 移除 / 属性变更，同一 tick 合成一条广播
-- 方法 Unit.GetAll：客户端拉全量；通知 Unit.Sync：{ create, remove, attribute }

---@class Unit.Data
---@field key integer 物编单位 key（py.UnitKey）
---@field x number
---@field y number
---@field face? number 朝向
---@field owner? integer 归属玩家 role_id

---@class Unit
---@field uid integer
---@field data Unit.Data
local M = Class 'Unit'

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

---@param uid integer
---@param data Unit.Data
function M:__init(uid, data)
    self.uid = uid
    self.data = data
end

---移除这个单位
function M:remove()
    cache[self.uid] = nil
    created[self.uid] = nil
    removed[self.uid] = true
end

local function flush()
    local create_list = created
    local remove_list = removed
    created = {}
    removed = {}
    local attribute = API.attr_drain()
    if not next(create_list) and not next(remove_list) and not next(attribute) then
        return
    end

    local payload = {}
    for uid, unit in pairs(create_list) do
        payload[uid] = unit.data
    end
    y3.client.rpc.broadcast('Unit.Sync', {
        create = payload,
        remove = remove_list,
        attribute = attribute,
    })
end

y3.timer.loop(FLUSH_INTERVAL, flush)

y3.client.rpc.register('Unit.GetAll', function ()
    local units = {}
    for uid, unit in pairs(cache) do
        units[uid] = unit.data
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
