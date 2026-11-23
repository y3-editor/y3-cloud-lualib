-- Redis：模块加载时取一次客户端，所有接口都作用于它
-- 回调版：y3.redis.get(key, cb) / set(key, value, cb) / incr_by(key, n, cb)，cb 可省略
-- 协程版：y3.redis.await.get(key) / set(key, value) / incr_by(key, n)，必须在协程内调用

local client = redis.get_redis_client()

local function noop() end

---@class Redis
local M = {}

---@param key string
---@param callback? fun(is_success: boolean, ret_val: any)
function M.get(key, callback)
    return client:Get(key, callback or noop)
end

---@param key string
---@param value string|number
---@param callback? fun(is_success: boolean, ret_val: any)
function M.set(key, value, callback)
    return client:Set(key, value, callback or noop)
end

---@param key string
---@param increment integer
---@param callback? fun(is_success: boolean, ret_val: any)
function M.incr_by(key, increment, callback)
    return client:IncrBy(key, increment, callback or noop)
end

---@class RedisAwait
local Await = {}

---@async
---@param key string
---@return boolean is_success
---@return any ret_val
function Await.get(key)
    return client:Get(key)
end

---@async
---@param key string
---@param value string|number
---@return boolean is_success
---@return any ret_val
function Await.set(key, value)
    return client:Set(key, value)
end

---@async
---@param key string
---@param increment integer
---@return boolean is_success
---@return any ret_val
function Await.incr_by(key, increment)
    return client:IncrBy(key, increment)
end

M.await = Await

return M
