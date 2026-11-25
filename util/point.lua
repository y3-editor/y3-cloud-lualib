-- 二维点：纯 Lua 值对象，位置相关逻辑共用；与客户端 Point 的常用接口对齐
-- 用法：y3.point.new(x, y)
---@class Point
---@field x number
---@field y number
local M = Class 'Point'

M.type = 'point'

---@param x number
---@param y number
---@return Point
function M.new(x, y)
    return New 'Point' (x, y)
end

---@param x number
---@param y number
function M:__init(x, y)
    self.x = x
    self.y = y
end

function M:__tostring()
    return ('{Point|%.3f,%.3f}'):format(self.x, self.y)
end

---@return number
function M:get_x()
    return self.x
end

---@return number
function M:get_y()
    return self.y
end

---@return Point
function M:get_point()
    return self
end

---@param other Point
---@return number
function M:get_distance_with(other)
    local dx, dy = other.x - self.x, other.y - self.y
    return math.sqrt(dx * dx + dy * dy)
end

---@param x number?
---@param y number?
---@return Point
function M:move(x, y)
    return New 'Point' (self.x + (x or 0), self.y + (y or 0))
end

return M
