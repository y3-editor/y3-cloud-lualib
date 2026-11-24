-- 云脚本客户端通讯层入口：y3.client
-- 功能模块自己挂到 y3.client 上：rpc（请求 / 应答 / 通知 / 广播）、handshake（握手）

---@class Client
y3.client = {}

require 'y3.client.rpc'
require 'y3.client.handshake'
