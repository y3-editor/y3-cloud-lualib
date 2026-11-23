-- JSON：封装引擎提供的 cjson
local json = require 'cjson'

---@class JSON
local M = {}

---@param data any
---@return string
function M.encode(data)
    return json.encode(data)
end

---@param text string
---@return any
function M.decode(text)
    return json.decode(text)
end

return M
