---
name: y3-cloud-script
description: >
  Y3 云脚本的 y3 框架用法：y3.client.rpc 通讯、handshake 握手、y3.await 异步、y3.timer 计时、
  y3.redis / y3.base64 / y3.json / y3.seri / y3.config / y3.develop。业务代码按这份写。

  ALWAYS use this skill when user mentions: 云脚本、cloud_script、y3.client、y3.client.rpc、
  y3.await、y3.timer、y3.redis、y3.config、y3.develop、$Develop.Eval、y3.cloud、y3.cloud.run、
  $Y3Cloud.Hello、$Y3Cloud.Ready、云脚本握手、云脚本执行 Lua、cloud_script/main.lua。
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
    ├── player/       # y3.player：Player 对象、player-attr 属性与广播
    ├── unit/         # y3.unit：逻辑单位、unit-attr 属性与广播
    ├── tools/        # 纯 Lua（与客户端同名文件保持一致）：class、await、serialization、utility、attribute、gc、event、linked_table
    └── util/         # 依赖引擎：json、redis、base64、timer、trigger
```

`require` 根目录是 `cloud_script/`，`require 'y3'` 解析到 `y3/init.lua`。

## 2. y3 库导览

| 模块 | 用途 |
|---|---|
| `y3.config.debug` | 是否放行调试能力，默认按 `MsIsProdEnv()` 推断（正式环境 false） |
| `y3.client.rpc` | 与客户端通讯：请求 / 应答 / 通知 / 广播 |
| `y3.client.handshake` | 握手：应答 `$Y3Cloud.Hello`，推送 `$Y3Cloud.Ready` |
| `y3.await` | 协程异步：`call` / `yield` / `sleep` / `waitAll`（sleep 的 waker 已接 `y3.timer`） |
| `y3.timer` | 定时器：`wait` / `loop` / `loop_count` / `clock`，返回带 `:remove()` 的对象 |
| `y3.point` | 二维点值对象：`y3.point(x, y)`（也支持 `y3.point.new(x, y)`），接口 `get_x` / `get_y` / `move` / `get_distance_with` |
| `y3.redis` | 地图全局存档：`get` / `set` / `incr_by` 回调版 + `await.get/set/incr_by` 协程版 |
| `y3.json` | 封装 cjson：`encode` / `decode` |
| `y3.seri` | 二进制序列化：`encode` / `decode` |
| `y3.base64` | 封装内置 `MsBase64Encode` / `MsBase64Decode` |
| `y3.attribute` | 属性系统：`create()` → `define` / `instance` / `set` / `add` / `get` / `modifier` / `event`，支持公式联动、上下限与 touched 记录 |
| `y3.player` | 玩家命名空间：静态接口 `y3.player.get(role_id)` / `y3.player.all()`；实例方法在 `Player` 类上 |
| `y3.unit` | 单位命名空间：`y3.unit.create(key, point, face, owner)` / `get` / `all`、`$Unit.Sync` 广播、`y3.unit.attr_define` 注册单位属性 |
| `y3.event` | 事件与触发器：`trigger` / `event` / `eventManager` / `customEvent`（对应全局类 `Trigger` / `Event` / `EventManager` / `CustomEvent`）；`Player`、`Unit` 已继承 `CustomEvent`，可 `obj:event_on` / `obj:event_notify` / `obj:event_dispatch` |
| `y3.gc` | 生命周期回收：`GCHost:bindGC(obj)` 把对象绑到宿主，宿主删除时一并删除；`y3.gc.host()` / `y3.gc.node(fn)` |
| `y3.init` / `y3.on_init` | 初始化事件：模块加载期 `y3.on_init(fn)` 注册，入口末尾 `y3.init()` 按注册顺序执行（库级初始化用；业务启动改用下面的 `y3.game`） |
| `y3.game` | 工程级游戏事件（`cloud_script/core/game.lua`）：`on(name, fn)` / `emit(name, ...)`；`_roomloaded` 时触发 `游戏-初始化` |
| `y3.class` | 类工具；`init.lua` 同时注入全局 `Class` / `New` / `Extends` / `Delete` / `IsValid` / `Type` / `Alias` / `IsInstanceOf` |
| `y3.util` | 通用工具（`sortPairs`、`dump`、`inspect` 等），init 里已启用 `<close>` 与 `'{}' % args` 格式化 |
| `y3.develop.eval` | 云端执行 Lua（`$Develop.Eval`），仅 `debug` 时放行 |

## 3. 通讯：y3.client.rpc

```lua
-- 云脚本
y3.client.rpc.register(method, function (player, data) return result end)
y3.client.rpc.request(player, method, data, function (suc, result, err) end)
y3.client.rpc.awaitRequest(player, method, data)   -- 协程内，返回 suc, result, err
y3.client.rpc.notify(player, method, data)
y3.client.rpc.broadcast(method, data)              -- 一次发送，平台广播给全房间
```

- 传输事件 `$Y3Cloud`：报文整包 `base64(y3.seri)`，解出后是 `{ i, m, d, e }`（`i+m` 请求、`i` 应答、`m` 通知）；调用方直接把 `data` 交给库，不用自己序列化
- 外壳（实测）：引擎两个方向都自作主张 `json` 一次 —— **下行**（`MsSendMlEvent`）必须发 JSON 字符串字面量 `"base64"`，客户端拿到的是去引号的字符串；**上行**（`send_mlscript_msg`，meta 声明 `py.Table`，实测传 string 也通）直接发 base64 字符串，云端 `evalue` 会带首尾引号，需 `sub(2, -2)` 脱引号，并还原引擎转义出的 `\/` → `/`（base64 里常有 `/`，不还原会解码失败）。base64 字符集不含引号与转义，套引号安全
- 成败只看 `e` 是否为 nil；超时默认 5 秒（`y3.client.rpc.timeout`）
- 单条消息上限 10240 字节：超限不发送并打 warn，请求回包超限会回 `e = 'payload_too_large'`
- handler 返回值即应答体；抛错会转成 `e`
- `broadcast` 用 `role_id = 0` 发一次即可：平台下行本身就是全房间广播，客户端收到的逐条都是同一份；实测 `0` / `-1` 都被接受，`nil` 报错，且此时客户端事件参数 `player` 为 nil，归属只能看 payload

客户端对应 `y3.cloud.rpc.*`（`request` / `awaitRequest` / `notify` / `register`）。

## 4. 握手

```lua
-- 云脚本：房间加载完成与玩家加入时自动推 $Y3Cloud.Ready
y3.client.handshake.info()     -- { version = y3.version, debug = y3.config.debug }

-- 客户端
y3.cloud.ready                 -- 是否已握手
y3.cloud.version               -- 云脚本 y3 库版本
y3.cloud.debug                 -- 云脚本 debug 开关
y3.cloud.on_ready(cb)          -- 已握手立即回调
y3.cloud.request(cb)           -- 主动发 $Y3Cloud.Hello
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

## 7. 玩家

```lua
local player = y3.player.get(role_id)   -- 同一 role_id 返回同一实例

player:get_id()               -- role_id
player:get_name()             -- string?，玩家或房间不存在时为 nil
player:get_map_level()        -- integer?
player:get_played_time()      -- 秒，integer?
player:get_played_count()     -- integer?
player:get_item(item_id)      -- ItemInfo?（stack_cnt / can_use / expired_time / max_stack_cnt）
player:try_consume_item(item_id, count)   -- ok, err；err 为 MlRoomErrorCode 或 'invalid_count'
player:get_archive()          -- 存档字符串，无存档为 nil
player:save_archive(text)     -- boolean

-- 属性（先注册再使用；注册放在 cloud_script/config.lua）
y3.player.attr_define('金币', 0, 99999999, true)   -- name, min, max, to_client
player:attr_get('金币')       -- number
player:attr_set('金币', 100)
player:attr_add('金币', 50)
local mod = player:attr_modify('金币', 100)   -- Attribute.Modifier：mod:update(v) 改值，mod:remove() 扣回
```

`Player` 有 `get_id()`，可直接当 `y3.client.rpc.*` 的 player 参数。`try_consume_item` 返回成功只表示扣减已受理，新数量以 `_item_info_changed` / `_consume_item_notify` 为准；`player:is_exited()` 由 `_playerexit` / `_playerjoin` 维护，实例常驻不回收。

属性变更由属性系统的 `getTouched()` 收集，`y3.timer.loop(0.1)` 每 100 ms 把窗口内所有变化过的玩家合成**一条** `$Player.Sync`（`modifier` 的 update / remove 同样被收集），单位侧同理由 `$Unit.Sync` 承担：

| 方法 | 方向 | 报文 |
|---|---|---|
| `$Player.GetAll` | 客户端 → 云 | 无 data，应答 `{ attribute = { [role_id] = { ['金币'] = 100 } } }` |
| `$Player.Sync` | 云 → 客户端（广播，`role_id = 0`） | `{ attribute = { [role_id] = { ['金币'] = 100 } } }`，只含 touched 且当前值与旧值不同的属性 |

新增的玩家同步数据也挂进同一个 `$Player.Sync` 报文（新增字段），不要再另开协议。

客户端对应 `y3.cloud.player`：收到全量与增量后逐项调用 `Player:set(name, value)` 写进 Y3；`y3.cloud.player.set_player_hook(fn)` 注册钩子 `fn(player, name, value)`，钩子返回 true 时该属性不再写入 Y3。客户端不缓存属性。

`to_client` 为 true 的属性会 `recordTouch` 并进入全量与增量下发；为 false 的只留在云端。属性系统在首次 `system:instance()` 时才编译，所以 `attr_define` 必须在创建第一个玩家属性实例之前调用（放在 `cloud_script/config.lua`，由 `main.lua` 早于业务 require）。`exited` 只表示背后的用户退出，玩家属性照常计算与广播。

## 8. 单位

```lua
local unit = y3.unit.create(134224145, y3.point(100, 200), 0, role_id)   -- key, point, face, owner
unit:move_to(y3.point(300, 200))    -- 下发移动命令，客户端驱动 Y3 寻路
unit:teleport(y3.point(500, 500))   -- 云权威位移，不经过寻路
unit:stop()
unit:get_pos()            -- 当前最优位置，返回 Point（寻路中按采样插值）
unit:get_xy()             -- 同一位置的坐标，返回 x, y 两个数（性能敏感处用这个）
```

单位的所有同步都走同一条 `$Unit.Sync`（100 ms 窗口合并）：

| 字段 | 内容 |
|---|---|
| `create` | `{ [uid] = { key, x, y, face, owner } }` |
| `remove` | `{ [uid] = true }` |
| `attribute` | `{ [uid] = { [属性名] = 值 } }` |
| `command` | `{ [uid] = { move_to = {x,y} } }` / `{ teleport = {...} }` / `{ stop = true }` |

寻路段由客户端回传，协议 `$Unit.Pos.Report`（reporter → 云，notify）：

```lua
{ seq, start = { [uid] = true } }        -- 寻路开始（只作信号，起点由云端取上次结束的位置）
{ seq, units = { [uid] = { x, y } } }    -- 200 ms 采样，包含全部寻路中的云端单位
{ seq, stop  = { [uid] = { x, y } } }    -- 寻路结束
```

- 云端只接受一个 reporter（存活玩家中最小 `role_id`），1 s 心跳、3 s 超时重选，`seq` 单调去重
- `start` 只作信号：起点用云端当前（= 上次结束）位置
- 速度合理性校验是**可插拔**的：默认关闭；`y3.unit.set_speed_limit_provider(fn)` 注册后，`fn(unit)` 返回该单位的速度上限（单位/秒，容差由 `fn` 自己乘入；返回 nil 表示跳过该单位），上报速度超过上限即丢弃并退回上一位置（每单位只 warn 一次）。计算速度的采样窗口额外加 100 ms，避免边界落在帧上把正常移动误判成超速
- 插值惰性求值：`get_pos(now?)` 返回 `Point`、`get_xy(now?)` 返回两个数，都用最近 3 个采样分段线性，超出最后采样时按最近速度沿目标方向外推；同一时刻结果缓存
- 位置误差上界 ≈ `移动速度 × 采样间隔`（1000 速 / 200 ms ≈ 2 身位），依赖位置的判定要留容差；精确命中仍由客户端算

## 9. 调试

- `y3.develop.eval`：客户端 `y3.cloud.run(code, cb)` → 云脚本执行，返回第一个返回值；需 `y3.config.debug`
- 客户端控制台 `~` 前缀：先检查 `y3.cloud.ready`，再调用 `y3.cloud.run` 并回显结果或错误
- 日志用大写 `Log.info/warn/error`；`Log.info` 经引擎 runtime 注入客户端 `log.info`（日志里表现为 `[ info][[string "<python>"]:5]: [mlscript]: [.\文件:行]:...`），再走 `y3.develop.helper.print` 到开发助手终端；`warn` **不转发**，判据以 `cloud_script/script_log` 为准（链路细节见 cloud-script-native 调试章节）

## 10. 写业务的约束

- `main.lua` 只做 require 编排，业务放 `game/`
- 全局能力由 `y3/init.lua` 统一装配：新增库模块在那里挂 `y3.<name>`，模块自己挂全局，init 只 `require`
- 启动逻辑挂在工程级事件上：`main.lua` 在 `_roomloaded` 时 `y3.game.emit('游戏-初始化')`，业务模块用 `y3.game.on('游戏-初始化', fn)` 注册；不要在 require 期间直接建单位、发消息。`y3.on_init` 仍在库里，只用于与房间无关的库级初始化
- 存档带 `schema_version`，解析失败不覆盖旧档
- 回调一律兜底：事件 / 定时器 / RPC 处理器统一用 `xpcall(fn, Log.error, ...)`，单个回调抛错不许打哑后续事件；业务新写的事件回调、`y3.timer.*` 回调照此处理
- base64 用 `y3.base64`；二进制跨端必须 base64（原样上行会丢非法 UTF-8、下行含 `\0` 会打断通道）
- 只 `include`/`require` 库与业务模块，不依赖本地文件与 C 模块

## 11. 参考

- 原生接口 / 配额 / 排错：`../cloud-script-native/SKILL.md`
- 引擎官方手册：`../cloud-script-native/references/CloudScript.md`
- 客户端库：`global_script/y3/doc/skills/y3-lib/SKILL.md`
