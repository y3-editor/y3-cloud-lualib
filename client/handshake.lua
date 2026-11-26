-- 握手：客户端主动询问，云端就绪后应答；未就绪的询问先挂起，就绪时统一补发
-- 就绪回调每个会话触发一次，会话由 y3.client.handshake.new_session() 开始

---@class Client.Handshake
local M = {}

---@type boolean 房间已加载且不在重置中
local ready = false

---@type fun()[] 就绪后唤醒的挂起询问
local waiting = {}

local epoch = 0
local fired_epoch = -1

---@type fun()[]
local ready_callbacks = {}

---@return { version: string, debug: boolean }
local function info()
    return {
        version = y3.version,
        debug = y3.config.debug,
    }
end

local function fire_ready()
    if fired_epoch == epoch then
        return
    end
    fired_epoch = epoch

    local list = ready_callbacks
    for i = 1, #list do
        xpcall(list[i], Log.error)
    end
end

local function flush_waiting()
    local list = waiting
    if #list == 0 then
        return
    end
    waiting = {}
    for i = 1, #list do
        list[i]()
    end
    fire_ready()
end

---设置就绪状态；就绪时补发挂起的应答
---@param value boolean
function M.set_ready(value)
    ready = value
    if not ready then
        return
    end
    flush_waiting()
end

---@return boolean
function M.is_ready()
    return ready
end

---开始新会话：置为未就绪并重置触发标记；挂起的询问答 not_ready，由客户端重试
function M.new_session()
    ready = false
    epoch = epoch + 1

    local list = waiting
    waiting = {}
    for i = 1, #list do
        list[i]()
    end
end

---登记就绪回调，每个会话触发一次
---@param callback fun()
function M.on_ready(callback)
    ready_callbacks[#ready_callbacks + 1] = callback
end

M.info = info

y3.client.rpc.register('$Y3Cloud.Hello', function ()
    if not ready then
        -- 未就绪：挂起协程，等到就绪再应答
        y3.await.yield(function (resume)
            waiting[#waiting + 1] = resume
        end)
        if not ready then
            return nil, 'not_ready'
        end
    end
    fire_ready()
    return info()
end)

RegisterEvent('_roomloaded', function ()
    xpcall(M.set_ready, Log.error, true)
end)

y3.client.handshake = M
