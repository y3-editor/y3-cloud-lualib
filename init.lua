-- 云脚本基础框架入口。
-- 用法：require 'y3' 拿到全局 y3 表；模块放 y3/<目录>/<模块>.lua，按 require 'y3.<目录>.<模块>' 加载。
-- util/ 放依赖引擎接口的工具，tools/ 放纯 Lua 工具。

---@class Y3
y3 = {}

y3.version = '0.1.0'

y3.config = require 'y3.config'

y3.class = require 'y3.tools.class'

Class        = y3.class.declare
New          = y3.class.new
Extends      = y3.class.extends
Delete       = y3.class.delete
IsValid      = y3.class.isValid
Type         = y3.class.type
Alias        = y3.class.alias
IsInstanceOf = y3.class.isInstanceOf

y3.util = require 'y3.tools.utility'
y3.util.enableCloseFunction()
y3.util.enableFormatString()

y3.seri   = require 'y3.tools.serialization'
y3.await  = require 'y3.tools.await'
y3.base64 = require 'y3.util.base64'
y3.json   = require 'y3.util.json'
y3.redis  = require 'y3.util.redis'
y3.timer  = require 'y3.util.timer'

y3.attribute = require 'y3.tools.attribute'

y3.gc = require 'y3.tools.gc'

y3.linked_table = require 'y3.tools.linked_table'

-- 事件系统：Event / Trigger / EventManager / CustomEvent
y3.event = {
    trigger      = require 'y3.util.trigger',
    event        = require 'y3.tools.event',
    eventManager = require 'y3.tools.event_manager',
    customEvent  = require 'y3.tools.custom_event',
}

y3.await.setSleepWaker(function (time, callback)
    y3.timer.wait(time, callback)
end)

require 'y3.client'

require 'y3.player'

require 'y3.unit'

require 'y3.develop'

-- 初始化事件：业务在模块加载阶段注册，入口文件最后调 y3.init() 统一触发
local init_callbacks = {}
local inited = false

---注册初始化回调；`y3.init()` 之后注册的立即执行
---@param callback fun()
function y3.on_init(callback)
    if inited then
        xpcall(callback, Log.error)
        return
    end
    init_callbacks[#init_callbacks + 1] = callback
end

---触发初始化，按注册顺序执行所有回调；重复调用无副作用
function y3.init()
    if inited then
        return
    end
    inited = true

    local list = init_callbacks
    init_callbacks = {}
    for i = 1, #list do
        xpcall(list[i], Log.error)
    end
end

return y3
