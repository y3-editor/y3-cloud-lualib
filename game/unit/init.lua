-- 单位命名空间：y3.unit
-- 功能模块自己挂到 y3.unit 上：Unit（云端逻辑单位与广播）、unit_attr（属性）、unit_pos（位置上报与插值）

---@class Unit.API
y3.unit = {}

require 'y3.game.unit.unit'
require 'y3.game.unit.unit_attr'
require 'y3.game.unit.unit_pos'
