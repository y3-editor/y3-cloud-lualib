-- 执行客户端下发的 Lua：y3.develop.eval
-- 方法名 Develop.Eval；仅 y3.config.debug 为 true 时可用

local config = require 'y3.config'

local MAX_CODE_BYTES = 4096
local PREVIEW_BYTES = 256

local KEYWORDS = {
    ['and'] = true, ['break'] = true, ['do'] = true, ['else'] = true, ['elseif'] = true,
    ['end'] = true, ['for'] = true, ['function'] = true, ['if'] = true, ['in'] = true,
    ['local'] = true, ['or'] = true, ['repeat'] = true, ['return'] = true, ['then'] = true,
    ['until'] = true, ['while'] = true,
}

---编译代码：不是语句关键字开头时先尝试按表达式编译，支持不写 return
---@param code string
---@return function? chunk
---@return string? err
local function wrap_code(code)
    local first_token = code:match('^%s*([%w_]+)')
    if not first_token or not KEYWORDS[first_token] then
        local chunk = load('return ' .. code, '=cloud-eval', 't')
        if chunk then
            return chunk
        end
    end

    local chunk, err = load(code, '=cloud-eval', 't')
    if chunk then
        return chunk
    end
    return nil, err
end

---@param code string
---@return string
local function preview(code)
    if #code <= PREVIEW_BYTES then
        return code
    end
    return code:sub(1, PREVIEW_BYTES) .. '...'
end

---执行任意 Lua 代码，返回值数组原样回传（不做 tostring）
---@param role_id integer
---@param data any
---@return table|nil
---@return string|nil
local function on_eval(role_id, data)
    if not config.debug then
        Log.warn('y3.develop.eval: disabled, role=' .. tostring(role_id))
        return nil, 'eval_disabled'
    end

    local code = data and data.code
    if type(code) ~= 'string' or #code == 0 then
        return nil, 'invalid_code'
    end
    if #code > MAX_CODE_BYTES then
        return nil, 'code_too_large'
    end

    Log.info('y3.develop.eval: role=' .. tostring(role_id) .. ' code=' .. preview(code))

    local chunk, load_err = wrap_code(code)
    if not chunk then
        Log.warn('y3.develop.eval: load error, ' .. tostring(load_err))
        return nil, 'load_error: ' .. tostring(load_err)
    end

    local packed = table.pack(pcall(chunk))
    if not packed[1] then
        Log.warn('y3.develop.eval: run error, ' .. tostring(packed[2]))
        return nil, 'run_error: ' .. tostring(packed[2])
    end

    Log.info('y3.develop.eval: ok')
    return packed[2]
end

y3.client.rpc.register('Develop.Eval', on_eval)

y3.develop.eval = on_eval
