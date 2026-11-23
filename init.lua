-- 云脚本基础框架入口。
-- 用法：require 'y3' 拿到全局 y3 表；模块放 y3/<目录>/<模块>.lua，按 require 'y3.<目录>.<模块>' 加载。
-- util/ 放依赖引擎接口的工具，tools/ 放纯 Lua 工具。

y3 = y3 or {}

y3.version = '0.1.0'

y3.seri   = require 'y3.tools.serialization'
y3.base64 = require 'y3.util.base64'

return y3
