-- 云脚本基础框架入口。
-- 用法：require 'y3' 拿到 y3 表；基础模块放 y3/<模块>.lua，按 require 'y3.<模块>' 加载。
-- 本环境没有引擎级的 include / Class，类能力用 require 'y3.class'。

local y3 = {
    version = '0.1.0',
}

return y3
