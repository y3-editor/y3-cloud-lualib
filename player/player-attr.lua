-- 玩家属性：属性注册、属性实例、变更广播
-- 方法 Player.Attr.GetAll：客户端拉全房间玩家属性；通知 Player.Attr.Sync：变更广播给所有客户端

---@class Player
local M = Class 'Player'

-- 变更合并窗口（秒）。窗口内的改动合成一次广播，控制下行量
local FLUSH_INTERVAL = 0.1

local system = y3.attribute.create()

---@type table<string, true>
local CLIENT_ATTRS = {}

---属性实例，首次访问时按已注册的属性建
---@return Attribute.Instance
function M:attr()
    local inst = self.attr_instance
    if inst then
        return inst
    end
    inst = system:instance(self)
    self.attr_instance = inst
    return inst
end

---@param name string
---@return number
function M:attr_get(name)
    return self:attr():get(name)
end

---@param name string
---@param value number
function M:attr_set(name, value)
    self:attr():set(name, value)
end

---@param name string
---@param value number
function M:attr_add(name, value)
    self:attr():add(name, value)
end

-- 持有加成：撤销用 `modifier:remove()`，改值用 `modifier:update(value)`
---@param name string
---@param value number
---@return Attribute.Modifier
function M:attr_modify(name, value)
    return self:attr():modifier(name, value)
end

---@param player Player
---@return table<string, number>
local function collect(player)
    local values = {}
    local inst = player:attr()
    for name in pairs(CLIENT_ATTRS) do
        values[name] = inst:get(name)
    end
    return values
end

local function flush()
    local touched = system:getTouched()
    if not touched then
        return
    end

    local players = {}
    for instance, changed in pairs(touched) do
        local player = instance.customData
        if player then
            local values = {}
            for name, old in pairs(changed) do
                local value = instance:get(name)
                if value ~= old then
                    values[name] = value
                end
            end
            if next(values) then
                players[player.role_id] = values
            end
        end
    end
    if next(players) then
        y3.client.rpc.broadcast('Player.Attr.Sync', { players = players })
    end
end

y3.timer.loop(FLUSH_INTERVAL, flush)

y3.client.rpc.register('Player.Attr.GetAll', function ()
    local players = {}
    for role_id, player in pairs(y3.player.all()) do
        players[role_id] = collect(player)
    end
    return { players = players }
end)

---注册玩家属性；必须在第一次创建属性实例之前调用
---@param name string 属性名
---@param min? number|string 下限，可填另一个属性名做联动
---@param max? number|string 上限，可填另一个属性名做联动
---@param to_client? boolean 是否随广播同步给客户端
---@return Attribute.Define
function y3.player.attr_define(name, min, max, to_client)
    local define = system:define(name, true, min, max)
    if to_client then
        CLIENT_ATTRS[name] = true
        define:recordTouch()
    end
    return define
end