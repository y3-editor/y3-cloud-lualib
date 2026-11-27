---@class Player
local M = Class 'Player'

---@type table<integer, table>
local saves = {}
---@type table<integer, boolean>
local loaded = {}
---@type table<integer, boolean>
local frozen = {}
---@type table<integer, boolean>
local broken = {}

---@param role_id integer
---@return boolean
local function write(role_id)
    if not loaded[role_id] or frozen[role_id] then
        return true
    end
    if broken[role_id] then
        return false
    end

    local ok, encoded = pcall(y3.seri.encode, saves[role_id])
    if not ok then
        Log.warn('save: encode failed, role=' .. tostring(role_id))
        return false
    end
    if not MsSaveScriptArchive(role_id, encoded) then
        Log.warn('save: write failed, role=' .. tostring(role_id))
        return false
    end
    return true
end

---@param role_id integer
local function read(role_id)
    if loaded[role_id] and not frozen[role_id] then
        return
    end

    loaded[role_id] = true
    frozen[role_id] = nil
    broken[role_id] = nil

    local data = saves[role_id]
    if data then
        for k in pairs(data) do
            data[k] = nil
        end
    end

    local raw = MsGetScriptArchive(role_id)
    if raw == nil or raw == '' then
        saves[role_id] = data or {}
        return
    end

    local ok, decoded = pcall(y3.seri.decode, raw)
    if not ok or type(decoded) ~= 'table' then
        Log.warn('save: invalid archive, no write performed, role=' .. tostring(role_id))
        broken[role_id] = true
        saves[role_id] = data or {}
        return
    end

    if data then
        for k, v in pairs(decoded) do
            data[k] = v
        end
    else
        saves[role_id] = decoded
    end
end

---取该玩家的存档表，直接改字段即可；同一个玩家始终返回同一张表
---@return table
function M:get_save()
    if not loaded[self.role_id] then
        read(self.role_id)
    end
    return saves[self.role_id]
end

---写档所有未冻结的存档并清空标记
function y3.player.save_all()
    for role_id in pairs(saves) do
        write(role_id)
    end
    loaded = {}
    frozen = {}
    broken = {}
end

y3.game:event_on('玩家-加入', function (_, player)
    local role_id = player.role_id
    if frozen[role_id] then
        Log.info('save: role reused, role=' .. tostring(role_id))
    end
    read(role_id)
end)

y3.game:event_on('玩家-退出', function (_, player)
    local role_id = player.role_id
    local result = 'skip'
    if loaded[role_id] then
        result = write(role_id) and 'ok' or 'fail'
    end
    frozen[role_id] = true
    Log.info('save: player exit, role=' .. tostring(role_id) .. ', ' .. result)
end)

y3.game:event_on('游戏-房间结束', function ()
    y3.player.save_all()
end)