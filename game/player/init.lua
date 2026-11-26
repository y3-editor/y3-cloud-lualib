-- 玩家命名空间：y3.player
-- 功能模块自己挂到 y3.player 上：Player（Ms* 接口封装）、player_attr（属性定义与广播）

---@class Player.API
y3.player = {}

require 'y3.game.player.player'
require 'y3.game.player.player_attr'
