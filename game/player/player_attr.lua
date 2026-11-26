-- 玩家属性：属性注册、属性实例、变更收集（由 player.lua 的 flush 统一广播）

---@class Player
local M = Class 'Player'

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

---取出本窗口内变化的属性，只留与旧值不同的
---@return table<integer, table<string, number>>
function y3.player.attr_drain()
    local touched = system:getTouched()
    if not touched then
        return {}
    end

    local players = {}
    local cache = y3.player.all()
    for instance, changed in pairs(touched) do
        local player = instance.customData
        if player and cache[player.role_id] == player then
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
    return players
end

---所有玩家的下发属性快照
---@return table<integer, table<string, number>>
function y3.player.attr_all()
    local players = {}
    for role_id, player in pairs(y3.player.all()) do
        local values = {}
        local inst = player:attr()
        for name in pairs(CLIENT_ATTRS) do
            values[name] = inst:get(name)
        end
        players[role_id] = values
    end
    return players
end

---注册玩家属性；必须在第一次创建属性实例之前调用
---定义后表示这个属性由云脚本进行权威计算，客户端只做显示功能。
---设置 to_client 后这个属性也会同步给客户端，默认会写入 Y3 的属性系统。
---如果这个属性引擎不关心（比如是某种货币），你也可以通过 `y3.cloud.player.set_attr_hook` 修改这个行为，这样省得在编辑器里新建这个属性。
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
