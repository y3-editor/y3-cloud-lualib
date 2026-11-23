-- 云脚本基础框架入口。
-- 用法：require 'y3' 拿到 y3 表；基础模块放 y3/<模块>.lua，用 y3.require('rpc') 按需加载。
-- 云脚本环境只有 require 加载链，没有 include / Class / 项目自定义全局。

local y3 = {
    version = '0.1.0',
}

---按需加载本库模块：y3.require('rpc') -> require('y3.rpc')
---@param name string 模块名（相对 y3/ 目录，不带 .lua）
---@return any
function y3.require(name)
    return require('y3.' .. name)
end

return y3
