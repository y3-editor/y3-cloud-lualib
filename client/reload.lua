-- 热重载协议：客户端 `.rd` 触发，只有 include 加载的模块会重新执行

y3.client.rpc.register('$Y3Cloud.Reload', function ()
    if not y3.config.debug then
        Log.warn('y3.reload: reload ignored, debug=false')
        return
    end

    y3.client.handshake.new_session()
    y3.session.reset()
    y3.game.clear_reloadable()

    local names = y3.reload.reload()

    local failed = {}
    for i = 1, #names do
        if package.loaded[names[i]] == nil then
            failed[#failed + 1] = names[i]
        end
    end
    if #failed > 0 then
        Log.error('y3.reload: failed ' .. table.concat(failed, ', '))
        return
    end

    y3.client.handshake.set_ready(true)
    Log.info('y3.reload: reloaded ' .. #names .. ' modules')
end)
