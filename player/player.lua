-- 云脚本玩家对象：按 role_id 缓存，包装 Ms* 玩家接口
-- 通知 Player.Sync：属性等方法变更广播给所有客户端；方法 Player.GetAll：客户端拉全量

---@class Player
local M = Class 'Player'

-- 属性相关的静态接口由 player-attr.lua 实现
---@class Player.API
---@field attr_drain fun(): table<integer, table<string, number>>
---@field attr_all fun(): table<integer, table<string, number>>
local API = y3.player

-- 合并窗口（秒）
local FLUSH_INTERVAL = 0.1

---@type table<integer, Player>
local cache = {}

---@param role_id integer
function M:__init(role_id)
    self.role_id = role_id
    self.exited = false
end

---@return integer
function M:get_id()
    return self.role_id
end

---玩家是否已退出房间
---@return boolean
function M:is_exited()
    return self.exited
end

---@return string?
function M:get_name()
    return MsGetPlayerName(self.role_id)
end

---@return integer?
function M:get_map_level()
    return MsGetPlayerMapLevel(self.role_id)
end

---@return integer?
function M:get_played_time()
    return MsGetPlayedTime(self.role_id)
end

---@return integer?
function M:get_played_count()
    return MsGetPlayedCount(self.role_id)
end

---@param item_id integer
---@return ItemInfo?
function M:get_item(item_id)
    return MsGetPlayerItem(self.role_id, item_id)
end

-- 返回成功只表示扣减已受理，实际数量由 `_item_info_changed` / `_consume_item_notify` 带出
---@param item_id integer
---@param count integer
---@return boolean ok
---@return integer|string err 失败时为整型错误码（见 `MlRoomErrorCode`）或 `'invalid_count'`
function M:try_consume_item(item_id, count)
    if type(count) ~= 'number' or count <= 0 or count % 1 ~= 0 then
        return false, 'invalid_count'
    end
    ---@type integer
    local code = MsTryConsumeItem(self.role_id, item_id, count)
    if code ~= 0 then
        return false, code
    end
    return true, 0
end

---@return string?
function M:get_archive()
    return MsGetScriptArchive(self.role_id)
end

---@param text string
---@return boolean
function M:save_archive(text)
    return MsSaveScriptArchive(self.role_id, text)
end

RegisterEvent('_roomloaded', function (_, _, _, player_guids)
    if type(player_guids) ~= 'table' then
        return
    end
    for _, role_id in ipairs(player_guids) do
        y3.player.get(role_id)
    end
end)

RegisterEvent('_playerexit', function (_, role_id)
    y3.player.get(role_id).exited = true
end)

RegisterEvent('_playerjoin', function (_, role_id)
    if role_id == -1 then
        return
    end
    y3.player.get(role_id).exited = false
end)

local function flush()
    local attribute = API.attr_drain()
    if not next(attribute) then
        return
    end
    y3.client.rpc.broadcast('Player.Sync', { attribute = attribute })
end

y3.timer.loop(FLUSH_INTERVAL, flush)

y3.client.rpc.register('Player.GetAll', function ()
    return { attribute = API.attr_all() }
end)

---取玩家对象，同一个 role_id 返回同一实例
---@param role_id integer
---@return Player
function y3.player.get(role_id)
    local player = cache[role_id]
    if not player then
        player = New 'Player' (role_id)
        cache[role_id] = player
    end
    return player
end

---已创建的玩家对象（含已退出的）
---@return table<integer, Player>
function y3.player.all()
    return cache
end
