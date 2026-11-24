-- 云脚本状态查询：Develop.Stats，供客户端仪表盘拉取

local config = require 'y3.config'

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
    }
end

y3.client.rpc.register('Develop.Stats', on_stats)

y3.develop.stats = on_stats
