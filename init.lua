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
    Trigger     = require 'y3.tools.trigger',
    Event       = require 'y3.tools.event',
    EventManager = require 'y3.tools.event_manager',
    CustomEvent = require 'y3.tools.custom_event',
}

y3.await.setSleepWaker(function (time, callback)
    y3.timer.wait(time, callback)
end)

require 'y3.client'

require 'y3.player'

require 'y3.unit'

require 'y3.develop'

return y3
