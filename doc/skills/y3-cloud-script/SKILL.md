---
name: y3-cloud-script
description: >
  Y3 云脚本的 y3 框架用法：y3.client.rpc 通讯、handshake 握手、y3.await 异步、y3.timer 计时、
  y3.redis / y3.base64 / y3.json / y3.seri / y3.config / y3.develop。业务代码按这份写。

  ALWAYS use this skill when user mentions: 云脚本、cloud_script、y3.client、y3.client.rpc、
  y3.await、y3.timer、y3.redis、y3.config、y3.develop、Develop.Eval、y3.cloud、y3.cloud.run、
  Y3Cloud.Hello、Y3Cloud.Ready、云脚本握手、云脚本执行 Lua、cloud_script/main.lua。
---

# Y3 云脚本（y3 框架）

云脚本侧的业务代码**一律走 y3 库**：引擎原生接口（`RegisterEvent`、`Ms*`、`Timer`、`Log`、`redis`）只作为库的底层依赖，业务不直接调；底层细节、配额与排错见 `../cloud-script-native/SKILL.md`。

## 1. 目录与入口

```
<项目根>/cloud_script/
├── main.lua          # 只做 require 编排：local y3 = require 'y3'，再 require 业务模块
├── meta.lua          # 引擎 API 的类型声明，运行时不 require
├── core/             # 项目级基础设施（rpc 旧实现、env、archive 等）
├── game/             # 业务模块（推荐放这里）
├── dev/              # 开发自测与探针
└── y3/               # 云脚本基础库（submodule）
    ├── init.lua      # 装配全局 y3
    ├── client/       # y3.client：rpc、handshake
    ├── develop/      # y3.develop：eval
    ├── tools/        # 纯 Lua：class、await、serialization、utility
    └── util/         # 依赖引擎：json、redis、base64、timer
```

`require` 根目录是 `cloud_script/`，`require 'y3'` 解析到 `y3/init.lua`。

## 2. y3 库导览

| 模块 | 用途 |
|---|---|
| `y3.config.debug` | 是否放行调试能力，默认按 `MsIsProdEnv()` 推断（正式环境 false） |
| `y3.client.rpc` | 与客户端通讯：请求 / 应答 / 通知 / 广播 |
| `y3.client.handshake` | 握手：应答 `Y3Cloud.Hello`，推送 `Y3Cloud.Ready` |
| `y3.await` | 协程异步：`call` / `yield` / `sleep` / `waitAll`（sleep 的 waker 已接 `y3.timer`） |
| `y3.timer` | 定时器：`wait` / `loop` / `loop_count` / `clock`，返回带 `:remove()` 的对象 |
| `y3.redis` | 地图全局存档：`get` / `set` / `incr_by` 回调版 + `await.get/set/incr_by` 协程版 |
| `y3.json` | 封装 cjson：`encode` / `decode` |
| `y3.seri` | 二进制序列化：`encode` / `decode` |
| `y3.base64` | 封装内置 `MsBase64Encode` / `MsBase64Decode` |
| `y3.class` | 类工具；`init.lua` 同时注入全局 `Class` / `New` / `Extends` / `Delete` / `IsValid` / `Type` / `Alias` / `IsInstanceOf` |
| `y3.util` | 通用工具（`sortPairs`、`dump`、`inspect` 等），init 里已启用 `<close>` 与 `'{}' % args` 格式化 |
| `y3.develop.eval` | 云端执行 Lua（`Develop.Eval`），仅 `debug` 时放行 |

## 3. 通讯：y3.client.rpc

```lua
-- 云脚本
y3.client.rpc.register(method, function (role_id, data) return result end)
y3.client.rpc.request(player, method, data, function (suc, result, err) end)
y3.client.rpc.awaitRequest(player, method, data)   -- 协程内，返回 suc, result, err
y3.client.rpc.notify(player, method, data)
y3.client.rpc.broadcast(method, data)              -- 房间内已识别玩家逐个发送
```

- 传输事件 `$Y3Cloud`，报文 `{ i, m, d, e }`：`i+m` 请求、`i` 应答、`m` 通知；`d` 是 `base64(y3.seri)` 业务数据
- 成败只看 `e` 是否为 nil；超时默认 5 秒（`y3.client.rpc.timeout`）
- 单条消息上限 10240 字节：超限不发送并打 warn，请求回包超限会回 `e = 'payload_too_large'`
- handler 返回值即应答体；抛错会转成 `e`

客户端对应 `y3.cloud.rpc.*`（`request` / `awaitRequest` / `notify` / `register`）。

## 4. 握手

```lua
-- 云脚本：房间加载完成与玩家加入时自动推 Y3Cloud.Ready
y3.client.handshake.info()     -- { version = y3.version, debug = y3.config.debug }

-- 客户端
y3.cloud.ready                 -- 是否已握手
y3.cloud.version               -- 云脚本 y3 库版本
y3.cloud.debug                 -- 云脚本 debug 开关
y3.cloud.on_ready(cb)          -- 已握手立即回调
y3.cloud.request(cb)           -- 主动发 Y3Cloud.Hello
```

## 5. 异步与计时

```lua
y3.await.call(function ()
    y3.await.sleep(0.2)
    local ok, result, err = y3.client.rpc.awaitRequest(role_id, 'Client.Method', data)
end)

local timer = y3.timer.loop(0.1, function (t, count) end)
timer:remove()
```

- `y3.await.sleep` 精度约 10 ms（库内单脉冲推进）
- `y3.timer` 是自实现调度，不是引擎 `Timer` 对象；引擎 Timer 的回调会绑在创建它的协程上，业务不要直接用

## 6. Redis

```lua
y3.redis.set('k', 1, function (ok, value) end)   -- 回调版，cb 可省略
local ok, value = y3.redis.await.get('k')         -- 协程版
```

key 加业务前缀；多 key / 多步没有事务保证。

## 7. 调试

- `y3.develop.eval`：客户端 `y3.cloud.run(code, cb)` → 云脚本执行，返回第一个返回值；需 `y3.config.debug`
- 客户端控制台 `~` 前缀：先检查 `y3.cloud.ready`，再调用 `y3.cloud.run` 并回显结果或错误
- 日志用大写 `Log.info/warn/error`；客户端侧看 `[mlscript]` 转发，判据以 `cloud_script/script_log` 为准

## 8. 写业务的约束

- `main.lua` 只做 require 编排，业务放 `game/`
- 全局能力由 `y3/init.lua` 统一装配：新增库模块在那里挂 `y3.<name>`，模块自己挂全局，init 只 `require`
- 存档带 `schema_version`，解析失败不覆盖旧档
- base64 用 `y3.base64`；二进制跨端必须 base64（原样上行会丢非法 UTF-8、下行含 `\0` 会打断通道）
- 只 `include`/`require` 库与业务模块，不依赖本地文件与 C 模块

## 9. 参考

- 原生接口 / 配额 / 排错：`../cloud-script-native/SKILL.md`
- 引擎官方手册：`../cloud-script-native/references/CloudScript.md`
- 客户端库：`global_script/y3/doc/skills/y3-lib/SKILL.md`
