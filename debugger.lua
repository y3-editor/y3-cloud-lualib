-- 本地云脚本调试器：调试器目录与端口由 Y3 开发助手在启动前写入 script_log/
-- 只起监听、不等调试器，业务继续执行；调试器事件循环靠 50ms 定时器驱动

local UPDATE_INTERVAL_MS = 50

---@param name string
---@return any
local function read(name)
    local ok, value = pcall(require, 'script_log.' .. name)
    if not ok then
        return nil
    end
    return value
end

local function start()
    local path = read('debugger_path')
    if type(path) ~= 'string' then
        return
    end
    local port = read('debugger_port')
    if type(port) ~= 'number' then
        return
    end

    local file = path .. '/script/debugger.lua'
    local LDBG = dofile(file)
    LDBG:start('127.0.0.1:' .. port)
    if not LDBG then
        return
    end

    -- 关闭调试器自带的自动更新，改用定时器驱动
    LDBG:event('autoUpdate', false)
    Timer.new_timer(UPDATE_INTERVAL_MS, function ()
        LDBG:event('update')
        return true
    end)
end

pcall(start)
