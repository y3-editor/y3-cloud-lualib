-- 会话重置：调试模式下把云脚本清回初始状态，等客户端重新握手后重新触发「游戏-初始化」

---@class Game.Session
local M = {}

---清空本会话的运行时状态；库内部常驻资源、触发器、计时器与属性定义都保留
function M.reset()
    y3.unit.clear()
    y3.unit.clear_pos()
    y3.player.save_all()
    y3.player.clear()
    y3.client.rpc.clear_session()
end

y3.client.rpc.register('$Y3Cloud.Reset', function ()
    if not y3.config.debug then
        Log.warn('y3.session: reset ignored, debug=false')
        return
    end

    y3.client.handshake.new_session()
    M.reset()
    y3.client.handshake.set_ready(true)
    Log.info('y3.session: session reset, waiting for handshake')
end)

y3.session = M

return M
