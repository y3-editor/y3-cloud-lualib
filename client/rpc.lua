-- 请求 / 应答 / 通知 / 广播：y3.client.rpc
-- 报文（d = base64(y3.seri)）：
--   请求 { i: integer, m: string, d: string? }
--   应答 { i: integer, d: string?, e: string? }
--   通知 { m: string, d: string? }

local json = y3.json

---@class Client.Rpc
local M = {
    EVENT = '$Y3Cloud',
    timeout = 5,
}

---@alias PlayerRef integer|{ get_id: fun(self: any): integer }

local seq = 0

---@type table<integer, { callback: fun(suc: boolean, data: any, err: string?)?, timer_id: integer? }>
local pending = {}

---@type table<string, fun(role_id: integer, data: any): any, string?>
local handlers = {}

---@type table<integer, true>
local players = {}

---@return integer
local function next_id()
    seq = seq + 1
    if seq > 0x7FFFFFFF then
        seq = 1
    end
    return seq
end

---@param player PlayerRef
---@return integer?
local function to_role_id(player)
    if type(player) == 'number' then
        return player
    end
    if type(player) == 'table' and player.get_id then
        return player:get_id()
    end
    return nil
end

---@param data any
---@return string?
local function pack(data)
    if data == nil then
        return nil
    end

    local ok, text = pcall(y3.seri.encode, data)
    if not ok then
        Log.warn('y3.client.rpc: encode failed, ' .. tostring(text))
        return nil
    end

    return y3.base64.encode(text)
end

---@param raw any
---@return any
local function unpack_data(raw)
    if type(raw) ~= 'string' then
        return raw
    end

    local text = y3.base64.decode(raw)
    if text == nil then
        Log.warn('y3.client.rpc: base64 decode failed')
        return nil
    end

    local ok, value = pcall(y3.seri.decode, text)
    if not ok then
        Log.warn('y3.client.rpc: decode failed, ' .. tostring(value))
        return nil
    end
    return value
end

---@param role_id integer
---@param payload table
---@return boolean
local function send(role_id, payload)
    if payload.d ~= nil then
        payload.d = pack(payload.d)
        if payload.d == nil then
            return false
        end
    end

    local ok, text = pcall(json.encode, payload)
    if not ok then
        Log.warn('y3.client.rpc: encode failed, method=' .. tostring(payload.m) .. ', ' .. tostring(text))
        return false
    end

    local code = MsSendMlEvent(role_id, M.EVENT, text)
    if code ~= 0 then
        Log.warn('y3.client.rpc: send failed, code=' .. tostring(code) .. ', method=' .. tostring(payload.m))
        return false
    end
    return true
end

---@param id integer
---@param err string?
---@param data any
local function settle(id, err, data)
    local entry = pending[id]
    if not entry then
        return
    end
    pending[id] = nil
    if entry.timer_id then
        Timer.cancel_timer(entry.timer_id)
    end
    if entry.callback then
        entry.callback(err == nil, data, err)
    end
end

---@param role_id integer
---@param method string
---@param data any
---@return any result
---@return string? err
local function dispatch(role_id, method, data)
    local handler = handlers[method]
    if not handler then
        Log.warn('y3.client.rpc: no handler, method=' .. tostring(method))
        return nil, 'no_handler'
    end

    local ok, result, err = pcall(handler, role_id, data)
    if not ok then
        Log.warn('y3.client.rpc: handler error, method=' .. tostring(method) .. ', ' .. tostring(result))
        return nil, tostring(result)
    end
    return result, err
end

---@param role_id integer
---@param payload table
local function on_payload(role_id, payload)
    local id = payload.i
    local method = payload.m
    local body = unpack_data(payload.d)
    if id ~= nil and method ~= nil then        -- 请求
        local result, err = dispatch(role_id, method, body)
        send(role_id, { i = id, d = result, e = err })
    elseif id ~= nil then                      -- 应答
        settle(id, payload.e, body)
    elseif method ~= nil then                  -- 通知
        dispatch(role_id, method, body)
    end
end

---@param role_id integer
---@param evalue string
local function on_message(role_id, evalue)
    players[role_id] = true

    local ok, payload = pcall(json.decode, evalue)
    if not ok or type(payload) ~= 'table' then
        Log.warn('y3.client.rpc: invalid payload, role=' .. tostring(role_id))
        return
    end

    on_payload(role_id, payload)
end

RegisterEvent(M.EVENT, function (_, role_id, _, evalue)
    on_message(role_id, evalue)
end)

RegisterEvent('_roomloaded', function (_, _, _, player_guids)
    local ok, err = pcall(function ()
        ---@cast player_guids table
        for _, role_id in ipairs(player_guids) do
            players[role_id] = true
        end
    end)
    if not ok then
        Log.warn('y3.client.rpc: player_guids invalid, ' .. tostring(err))
    end
end)

RegisterEvent('_playerjoin', function (_, role_id)
    players[role_id] = true
end)

RegisterEvent('_playerexit', function (_, role_id)
    players[role_id] = nil
end)

---注册客户端请求 / 通知的处理函数；handler(role_id, data) 的返回值作为请求应答
---@param method string
---@param callback fun(role_id: integer, data: any): any, string?
function M.register(method, callback)
    handlers[method] = callback
end

---向客户端发起请求，callback(suc, data, err)
---@param player PlayerRef
---@param method string
---@param data any
---@param callback? fun(suc: boolean, data: any, err: string?)
---@return integer 请求 id
function M.request(player, method, data, callback)
    local role_id = to_role_id(player)
    if role_id == nil then
        Log.warn('y3.client.rpc: invalid player, method=' .. tostring(method))
        return 0
    end

    local id = next_id()
    local entry = { callback = callback }
    pending[id] = entry
    entry.timer_id = Timer.new_timer(M.timeout * 1000, function ()
        settle(id, 'timeout')
        return false
    end)

    if not send(role_id, { i = id, m = method, d = data }) then
        settle(id, 'send_failed')
    end
    return id
end

---向单个客户端发通知
---@param player PlayerRef
---@param method string
---@param data any
---@return boolean
function M.notify(player, method, data)
    local role_id = to_role_id(player)
    if role_id == nil then
        Log.warn('y3.client.rpc: invalid player, method=' .. tostring(method))
        return false
    end
    return send(role_id, { m = method, d = data })
end

---向房间内所有已识别的客户端发通知
---@param method string
---@param data any
---@return integer 实际发送的客户端数
function M.broadcast(method, data)
    local count = 0
    for role_id in pairs(players) do
        if send(role_id, { m = method, d = data }) then
            count = count + 1
        end
    end
    return count
end

---等待客户端应答（必须在协程中调用），返回 suc, data, err
---@async
---@param player PlayerRef
---@param method string
---@param data any
---@return boolean suc
---@return any data
---@return string? err
function M.awaitRequest(player, method, data)
    return y3.await.yield(function (resume)
        M.request(player, method, data, resume)
    end)
end

return M
