-- 请求 / 应答 / 通知 / 广播：y3.client.rpc
-- 报文 = base64(y3.seri)；上行收引擎带引号的字符串（脱引号），下行发 JSON 字符串字面量

---@class Client.Rpc
local M = {
    timeout = 5,
}

local EVENT = '$Y3Cloud'

-- 官方限制：事件名最长 32 字节，单条消息最长 10240 字节
local MAX_EVENT_BYTES = 32
local MAX_MESSAGE_BYTES = 10240

if #EVENT > MAX_EVENT_BYTES then
    Log.warn('y3.client.rpc: event name too long, bytes=' .. #EVENT)
end

---@alias PlayerRef integer|{ get_id: fun(self: any): integer }

local seq = 0

---@type table<integer, { callback: fun(suc: boolean, data: any, err: string?)?, timer_id: integer? }>
local pending = {}

---@type table<string, fun(player: Player, data: any): any, string?>
local handlers = {}

-- 平台下行本身会广播给房间内所有客户端，role_id 只是消息携带的目标玩家。
-- 实测：0 与 -1 都能被接受，nil 报错；客户端侧收到时事件参数 player 为 nil。
local BROADCAST_ROLE_ID = 0

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

---@param payload table
---@return string?
local function pack_payload(payload)
    local ok, text = pcall(y3.seri.encode, payload)
    if not ok then
        Log.warn('y3.client.rpc: encode failed, ' .. tostring(text))
        return nil
    end
    return y3.base64.encode(text)
end

---@param raw string
---@return table?
local function unpack_payload(raw)
    -- 引擎会把上行内容再 json.encode 一次，其中的 '/' 被转义成 '\/'，还原后才能解 base64
    raw = raw:gsub('\\/', '/')
    local text = y3.base64.decode(raw)
    if text == nil then
        Log.warn('y3.client.rpc: base64 decode failed, len=' .. #raw .. ', head=' .. raw:sub(1, 80))
        return nil
    end

    local ok, payload = pcall(y3.seri.decode, text)
    if not ok or type(payload) ~= 'table' then
        Log.warn('y3.client.rpc: decode failed, ' .. tostring(payload))
        return nil
    end
    return payload
end

---@param role_id integer
---@param payload table
---@return boolean ok
---@return string? err
local function send(role_id, payload)
    local text = pack_payload(payload)
    if text == nil then
        return false, 'encode_failed'
    end

    -- 下行发 JSON 字符串字面量，客户端事件数据会被解成去掉引号的字符串
    local body = '"' .. text .. '"'
    if #body > MAX_MESSAGE_BYTES then
        Log.warn('y3.client.rpc: payload too large, method=' .. tostring(payload.m) .. ', bytes=' .. #body)
        return false, 'too_large'
    end

    local code = MsSendMlEvent(role_id, EVENT, body)
    if code ~= 0 then
        Log.warn('y3.client.rpc: send failed, code=' .. tostring(code) .. ', method=' .. tostring(payload.m))
        return false, 'send_failed'
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
        xpcall(entry.callback, Log.error, err == nil, data, err)
    end
end

---@param role_id integer
---@param id integer
---@param result any
---@param err string?
local function respond(role_id, id, result, err)
    local ok, send_err = send(role_id, { i = id, d = result, e = err })
    if not ok and send_err == 'too_large' then
        send(role_id, { i = id, e = 'payload_too_large' })
    end
end

---handler 在协程内执行，可以用 y3.await 等待；有 id 表示请求，return 值作为应答
---@param role_id integer
---@param method string
---@param data any
---@param id? integer
local function dispatch(role_id, method, data, id)
    local handler = handlers[method]
    if not handler then
        Log.warn('y3.client.rpc: no handler, method=' .. tostring(method))
        if id ~= nil then
            respond(role_id, id, nil, 'no_handler')
        end
        return
    end

    local player = y3.player.get(role_id)
    y3.await.call(function ()
        local ok, result, err = xpcall(handler, Log.error, player, data, id)
        if id == nil then
            return
        end
        if not ok then
            respond(role_id, id, nil, tostring(result))
            return
        end
        respond(role_id, id, result, err)
    end)
end

---@param role_id integer
---@param payload table
local function on_payload(role_id, payload)
    local id = payload.i
    local method = payload.m
    local body = payload.d
    if id ~= nil and method ~= nil then        -- 请求
        dispatch(role_id, method, body, id)
    elseif id ~= nil then                      -- 应答
        settle(id, payload.e, body)
    elseif method ~= nil then                  -- 通知
        dispatch(role_id, method, body)
    end
end

---@param role_id integer
---@param evalue string 客户端发的字符串会被引擎 json.encode 一次，首尾带引号
local function on_message(role_id, evalue)
    if type(evalue) ~= 'string' or evalue:sub(1, 1) ~= '"' or evalue:sub(-1) ~= '"' then
        Log.warn('y3.client.rpc: invalid message, role=' .. tostring(role_id) .. ', data=' .. tostring(evalue))
        return
    end

    local payload = unpack_payload(evalue:sub(2, -2))
    if payload == nil then
        Log.warn('y3.client.rpc: invalid message, role=' .. tostring(role_id))
        return
    end
    on_payload(role_id, payload)
end

RegisterEvent(EVENT, function (_, role_id, _, evalue)
    xpcall(on_message, Log.error, role_id, evalue)
end)

---注册客户端请求 / 通知的处理函数；handler 在协程内执行，返回值作为请求应答
---@param method string
---@param callback fun(player: Player, data: any, id: integer?): any, string?
function M.register(method, callback)
    handlers[method] = callback
end

---丢弃所有等待应答的请求（会话重置用）
function M.clear_session()
    local snapshot = {}
    for id in pairs(pending) do
        snapshot[#snapshot + 1] = id
    end
    for i = 1, #snapshot do
        settle(snapshot[i], 'reset')
    end
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

    local ok, send_err = send(role_id, { i = id, m = method, d = data })
    if not ok then
        settle(id, send_err or 'send_failed')
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

---向房间内所有客户端发通知：一次发送，由平台广播
---@param method string
---@param data any
---@return boolean
function M.broadcast(method, data)
    return send(BROADCAST_ROLE_ID, { m = method, d = data })
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

y3.client.rpc = M
