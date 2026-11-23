-- 云脚本 Base64：封装内置 MsBase64Encode / MsBase64Decode
---@class BASE64
local M = {}

---将字符串编码为 base64
---@param str string
---@return string
function M.encode(str)
    return MsBase64Encode(str)
end

---将 base64 解码为字符串；非法输入返回 nil
---@param base64 string
---@return string?
function M.decode(base64)
    return (MsBase64Decode(base64))
end

return M
