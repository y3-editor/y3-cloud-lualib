-- 握手：告知客户端云脚本可用性与 y3 库版本
-- 方法 Y3Cloud.Hello：客户端主动询问；通知 Y3Cloud.Ready：房间加载 / 玩家加入时推送


---@return { version: string, debug: boolean }
local function info()
    return {
        version = y3.version,
        debug = y3.config.debug,
    }
end

y3.client.rpc.register('$Y3Cloud.Hello', function ()
    return info()
end)

---@param role_id integer?
local function push(role_id)
    if role_id then
        y3.client.rpc.notify(role_id, '$Y3Cloud.Ready', info())
    else
        y3.client.rpc.broadcast('$Y3Cloud.Ready', info())
    end
end

RegisterEvent('_roomloaded', function ()
    xpcall(push, Log.error, nil)
end)

RegisterEvent('_playerjoin', function (_, role_id)
    if role_id ~= -1 then
        xpcall(push, Log.error, role_id)
    end
end)

---@class Client.Handshake
y3.client.handshake = {
    info = info,
}
