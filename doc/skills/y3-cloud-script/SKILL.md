---
name: y3-cloud-script
description: >
  Y3 云脚本的 y3 框架用法：y3.client.rpc 通讯、handshake 握手、y3.await 异步、y3.timer 计时、
  y3.redis / y3.base64 / y3.json / y3.seri / y3.config / y3.develop、玩家存档（Player:get_save）。
  业务代码按这份写。

  ALWAYS use this skill when user mentions: 云脚本、cloud_script、y3.client、y3.client.rpc、
  y3.await、y3.timer、y3.redis、y3.config、y3.develop、$Develop.Eval、y3.cloud、y3.cloud.run、
  $Y3Cloud.Hello、$Y3Cloud.Reset、云脚本握手、云脚本执行 Lua、cloud_script/main.lua、玩家存档、
  get_save、MsSaveScriptArchive。
---

# Y3 云脚本（y3 框架）

云脚本侧的业务代码**一律走 y3 库**：引擎原生接口（`RegisterEvent`、`Ms*`、`Timer`、`Log`、`redis`）只作为库的底层依赖，业务不直接调；底层细节、配额与排错见 `../cloud-script-native/SKILL.md`。

## 1. 目录与入口

```
<项目根>/cloud_script/
├── main.lua          # 只做 include / require 编排
├── meta.lua          # 引擎 API 的类型声明，运行时不 require
├── game/             # 业务模块（推荐放这里）
├── dev/              # 开发自测与探针
└── y3/               # 云脚本基础库（submodule）
    ├── init.lua      # 装配全局 y3
    ├── client/       # y3.client：rpc、handshake、reload
    ├── develop/      # y3.develop：eval
    ├── game/         # y3.game：game.lua（环境判据 + 事件总线）、player/（含存档）、unit/、session.lua
    ├── tools/        # 纯 Lua（与客户端同名文件保持一致）：class、await、serialization、utility、attribute、gc、event、linked_table
    └── util/         # 依赖引擎：json、redis、base64、timer、trigger、point、reload
```

`require` 根目录是 `cloud_script/`，`require 'y3'` 解析到 `y3/init.lua`。

`.lua` 文件必须保存为 **UTF-8 无 BOM**：线上用 `load(src, name, 't')` 加载源码，BOM 会让它报 `unexpected symbol near '<\239>'`，表现为 `'<路径>' load failed`；本地 Mock 容忍 BOM，测不出来。

## 2. y3 库导览

| 模块 | 用途 |
|---|---|
| `y3.config.debug` | 是否放行调试能力，默认按 `MsIsProdEnv()` 推断（正式环境 false） |
| `y3.client.rpc` | 与客户端通讯：请求 / 应答 / 通知 / 广播 |
| `y3.client.handshake` | 握手：应答 `$Y3Cloud.Hello`（未就绪时挂起），就绪回调 |
| `y3.await` | 协程异步：`call` / `yield` / `sleep` / `waitAll`（sleep 的 waker 已接 `y3.timer`） |
| `y3.timer` | 定时器：`wait` / `loop` / `loop_count` / `clock`，返回带 `:remove()` 的对象 |
| `y3.point` | 二维点值对象：`y3.point(x, y)`（也支持 `y3.point.new(x, y)`），接口 `get_x` / `get_y` / `move` / `get_distance_with` |
| `y3.redis` | 地图全局存档：`get` / `set` / `incr_by` 回调版 + `await.get/set/incr_by` 协程版 |
| `y3.json` | 封装 cjson：`encode` / `decode` |
| `y3.seri` | 二进制序列化：`encode` / `decode` |
| `y3.base64` | 封装内置 `MsBase64Encode` / `MsBase64Decode` |
| `y3.attribute` | 属性系统：`create()` → `define` / `instance` / `set` / `add` / `get` / `modifier` / `event`，支持公式联动、上下限与 touched 记录 |
| `y3.player` | 玩家命名空间：静态接口 `y3.player.get(role_id)` / `y3.player.all()` / `y3.player.save_flush()` / `y3.player.save_all()`；实例方法在 `Player` 类上（含 `get_save()`） |
| `y3.unit` | 单位命名空间：`y3.unit.create(key, point, face, owner)` / `get` / `all`、`$Unit.Sync` 广播、`y3.unit.attr_define` 注册单位属性 |
| `y3.event` | 事件与触发器：`trigger` / `event` / `eventManager` / `customEvent`（对应全局类 `Trigger` / `Event` / `EventManager` / `CustomEvent`）；`Player`、`Unit` 已继承 `CustomEvent`，可 `obj:event_on` / `obj:event_notify` / `obj:event_dispatch` |
| `y3.gc` | 生命周期回收：`GCHost:bindGC(obj)` 把对象绑到宿主，宿主删除时一并删除；`y3.gc.host()` / `y3.gc.node(fn)` |
| `y3.game` | 游戏逻辑命名空间（`y3/game/game.lua`）：环境判据 `is_prod()` / `is_debug()` / `allow_test()`；事件总线 `event_on(name, fn)` / `event_notify(name, ...)` / `emit` / `clear_reloadable()`；握手完成派发 `游戏-初始化` |
| `y3.session` | 会话重置：`reset()` 清单位 / 玩家 / 挂起请求（**不清触发器与计时器**）；`$Y3Cloud.Reset` 处理，仅 `debug` |
| `y3.reload` | 热重载（`y3/util/reload.lua`）：`include` 加载的模块可重载，`reload()` 重新执行；`.rd` 触发 |
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

客户端主动发起 `$Y3Cloud.Hello`，云端就绪后应答；未就绪（房间没加载完、会话重置中）的询问先挂起，就绪时补发。云端不再主动推 `Ready`。

```lua
-- 云脚本
y3.client.handshake.info()            -- { version = y3.version, debug = y3.config.debug }
y3.client.handshake.on_ready(fn)      -- 每个会话握手成功触发一次（main.lua 用来发「游戏-初始化」）
y3.client.handshake.set_ready(bool)   -- 就绪状态；补发挂起的应答
y3.client.handshake.new_session()     -- 开始新会话（重置），下一次握手会重新触发 on_ready

-- 客户端
y3.cloud.ready                 -- 是否已握手
y3.cloud.version               -- 云脚本 y3 库版本
y3.cloud.debug                 -- 云脚本 debug 开关
y3.cloud.on_ready(cb)          -- 每次握手都会回调（重连后要重新拉全量，别写成一次性）
y3.cloud.request(cb)           -- 主动发 $Y3Cloud.Hello，超时默认重试 2 次
y3.cloud.reset()               -- 通知云端重置会话（`.rr` 用），随后需重新握手
```

**`reset()` 不自己补握手，是设计**：它只把 `ready` 置 false 并发通知，然后等客户端重启后按正常流程主动握手。所以「调了 `reset()` 却一直卡在未握手」不是 bug —— 真实 `.rr` 会重启客户端，客户端重启后再走 `游戏-初始化` → `request()`。

RPC handler 在 `y3.await` 协程里执行，需要等待时直接 `y3.await.sleep()` / `y3.await.yield()`，返回值即应答（`$Y3Cloud.Hello` 就是这样挂在未就绪状态上等就绪的）。

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
player:get_save()             -- 存档表（同一玩家始终同一张表，首次访问时读档）

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

客户端对应 `y3.cloud.player`：收到全量与增量后逐项调用 `Player:set(name, value)` 写进 Y3；`y3.cloud.player.set_attr_hook(fn)` 注册钩子 `fn(player, name, value)`，钩子返回 true 时该属性不再写入 Y3（`y3.cloud.unit.set_attr_hook(fn)` 同理，签名是 `fn(unit, name, value)`）。客户端不缓存属性。

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

单位同步走同一条 `$Unit.Sync`：创建 / 移除 / 属性按 100 ms 窗口合并，命令当场单独下发：

| 字段 | 内容 |
|---|---|
| `create` | `{ [uid] = { key, x, y, face, owner } }` |
| `remove` | `{ [uid] = true }` |
| `attribute` | `{ [uid] = { [属性名] = 值 } }` |
| `command` | `{ [uid] = { move_to = {x,y} } }` / `{ teleport = {...} }` / `{ stop = true }`，每次一条，按调用顺序到达 |

寻路段由客户端回传，协议 `$Unit.Pos.Report`（reporter → 云，notify）：

```lua
{ seq, start = { [uid] = true } }        -- 寻路开始（只作信号，起点由云端取上次结束的位置）
{ seq, units = { [uid] = { x, y } } }    -- 200 ms 采样，包含全部寻路中的云端单位
{ seq, stop  = { [uid] = { x, y } } }    -- 寻路结束
```

- 云端只接受一个 reporter（存活玩家中最小 `role_id`），1 s 心跳、3 s 超时重选，`seq` 单调去重
- `start` 只作信号：起点用云端当前（= 上次结束）位置
- 速度合理性校验是**可插拔**的：默认关闭；`y3.unit.set_speed_limit_provider(fn, on_violation)` 注册后，`fn(unit)` 返回该单位的速度上限（单位/秒，容差由 `fn` 自己乘入；返回 nil 表示跳过该单位），上报速度超过上限即丢弃并退回上一位置（每单位只 warn 一次），同时以 `on_violation(unit, speed, limit)` 回调外部做记录（每次异常都调，回调里抛错只 `Log.error`）。计算速度的采样窗口额外加 100 ms，避免边界落在帧上把正常移动误判成超速。**启用即接管位移**：所有传送必须由云脚本发起（`unit:teleport`），否则客户端本地瞬移会被判超速拉回
- 插值惰性求值：`get_pos(now?)` 返回 `Point`、`get_xy(now?)` 返回两个数，都用最近 3 个采样分段线性，超出最后采样时按最近速度沿目标方向外推；同一时刻结果缓存
- 采样超过 1 s 没有更新即视为已停步（`STALE_MOVING_MS`）：客户端重开（`.rr` / 重载游戏）后会断上报，不这样处理云端会一直认为单位在寻路
- 位置误差上界 ≈ `移动速度 × 采样间隔`（1000 速 / 200 ms ≈ 2 身位），依赖位置的判定要留容差；精确命中仍由客户端算

## 9. 玩家存档

```lua
local save = player:get_save()   -- 一张 Lua 表；同一玩家始终同一张表
save.金币 = (save.金币 or 0) + 100
save.bag = save.bag or {}
save.bag[1001] = true
```

- 表就常驻内存，改字段**不触发写档**；只有 `玩家-退出` / `游戏-房间结束` / 会话重置前才序列化
- **本地模拟服务额外每 5 秒定期保存一次**（`!y3.game.is_prod()` 时启用）：关客户端时 mock 进程会随之退出（日志里是 `read error` → `stop cost: ~34ms` → `exiting`），来不及触发 `_playerexit`，不靠定期保存就测不出「关客户端后还在」。线上不需要，`_playerleave` 后 3 分钟会自动触发 `_playerexit`
- 定期保存用 `y3.player.save_flush()`（写档但**保留**标记）；`y3.player.save_all()` 写完会清标记，只在会话重置 / 房间结束用
- 序列化用 `y3.seri`（二进制），不用 JSON：体积小、无 `cjson` 稀疏数组限制，seri 保证新版本能解旧版本数据（反向不保证）
- **二进制直存，不包 base64**：已实测 `MsSaveScriptArchive` / `MsGetScriptArchive` 会原样保留非 UTF-8 字节 —— 写入 0x00–0xFF 全 256 字节，读回逐字节一致（同进程与重启进程后都验证过），所以省掉 base64 的 33% 开销
- 结构与版本号由业务自定，库不校验、不补默认值、不迁移；建议自己记 `save.schema_version`
- 槽位复用（`role_id` 被新玩家占用）时**原地清空同一张表**再灌入，业务缓存的引用不会失效
- 读档解析失败 → 该玩家**整局不写档**（`Log.warn` 一次），避免空表覆盖旧档
- `y3.player.save_all()` 写档全部未冻结玩家并清缓存，`游戏-房间结束` 与 `y3.session.reset()` 自动调
- 上限 1 MB（`MsSaveScriptArchive` 超限返回 false）；读写都是**同步**调用，没有回调
- 退出日志的第三段是 `ok` / `fail` / `skip`（`skip` = 这局没读过档，无需写）
- 本地产物 `cloud_script/mls_archive/<role_id>.json` 的 `script_data_b64` 解 base64 后就是 **seri 二进制原文**（mock 自己 base64 一层），再 `y3.seri.decode` 即可核对

## 10. 调试与热重载

- `y3.develop.eval`：客户端 `y3.cloud.run(code, cb)` → 云脚本执行，返回第一个返回值；需 `y3.config.debug`
- 客户端控制台 `~` 前缀：先检查 `y3.cloud.ready`，再调用 `y3.cloud.run` 并回显结果或错误
- 日志用大写 `Log.info/warn/error`；`Log.info` 经引擎 runtime 注入客户端 `log.info`（日志里表现为 `[ info][[string "<python>"]:5]: [mlscript]: [.\文件:行]:...`），再走 `y3.develop.helper.print` 到开发助手终端；`warn` **不转发**，判据以 `cloud_script/script_log` 为准（链路细节见 cloud-script-native 调试章节）

### 热重载（`.rd`）

客户端 `.rd` 会同时重载客户端脚本与云脚本业务模块；云脚本侧需 `y3.config.debug`。

- **参与重载**：用 `include` 加载的模块（`config` / `core.*` / `game.*` / `dev.*`）；`require` 的模块不参与
- **库不重载**：`y3/**` 全部保持 `require`（加载期注册引擎事件、常驻计时器、属性系统），改库要重启游戏
- **新增文件不用重启**：只要被某个 `include` 模块 `include`/`require` 到，`.rd` 后即生效；**改 `main.lua` 的加载列表**才需要重启
- **订阅去重**：`y3.game:event_on` 记录注册者模块，重载前 `y3.game.clear_reloadable()` 注销它们，重载后模块重新注册——业务订阅不要放在 `require` 的模块里（不会被清，重启前一直有效，但重载后模块自己再订阅一次就重复了）
- **属性**：`config` 每次重载都会重新 `attr_define`，属性系统支持重复定义（覆盖旧定义并丢弃编译结果），所以改上下限也能生效
- **时序**：重载会先作废握手、清会话（单位 / 玩家 / 挂起请求；**触发器与计时器不动**，`.rr` 也不动，见下）
- 与 `.rr` 的分工：只改云脚本用 `.rd`（客户端不用重启）；改客户端用 `.rr`（顺带通知云端重置会话）；两边都改用 `.rr` 后再 `.rd`

### 会话重置（`.rr` / `$Y3Cloud.Reset`）

**只清运行时数据，不清订阅**：

| 清 | 不清 |
|---|---|
| 单位（含位置缓存）、玩家对象、RPC 挂起请求 | 触发器 / `event_on` 订阅、计时器、属性定义、存档缓存 |

原因：触发器和计时器都是**模块加载期**注册的长期设施，`.rr` 只重置会话、**不重新执行模块**，清掉就没有人再注册回来——表现为「`.rr` 后英雄不创建、存档不打印」，但云脚本本身还在跑（仪表盘正常、握手也通）。

重置完云端停在**未就绪**，等客户端重启后主动握手；重连上才会再派发一次「游戏-初始化」。所以手动调 `reset()` 而不重启客户端时，会一直停在未就绪——这是预期行为，不是漏了自愈。

**「玩家-加入」不补发**：重置会清空玩家对象，之后由 `y3.player.get()`（RPC 派发、业务主动取）**惰性重建**，不派发事件。所以「每局」（进房 + 每次会话重置后）都要跑的初始化逻辑必须挂 `游戏-初始化` 并自己遍历 `y3.player.all()`；只挂 `玩家-加入` 的代码在 `.rr` 后会静默不执行——这是最容易踩的坑。

```lua
-- 每局初始化：进房与 .rr 后都会跑
y3.game:event_on('游戏-初始化', function ()
    for _, player in pairs(y3.player.all()) do
        local save = player:get_save()
        save.visits = (save.visits or 0) + 1
    end
end)

-- 只关心「真实进房」时才挂这个（.rr 后不触发）
y3.game:event_on('玩家-加入', function (_, player) end)
```

热重载时的订阅去重是另一套机制：`y3.game:event_on` 记录注册者模块，重载前 `clear_reloadable()` 只注销那些**属于将被重载模块**的订阅，重载后模块自己重新注册。

## 11. 写业务的约束

- `main.lua` 只做 require / include 编排，业务放 `game/`
- 全局能力由 `y3/init.lua` 统一装配：新增库模块在那里挂 `y3.<name>`，模块自己挂全局，init 只 `require`
- 启动逻辑挂在工程事件上：库在客户端握手完成时 `y3.game:event_notify('游戏-初始化')`，业务用 `y3.game:event_on('游戏-初始化', fn)` 订阅；不要在加载期直接建单位、发消息
- 工程事件由库统一派发，业务不直接监听引擎事件：`游戏-初始化`、`游戏-房间结束`（`(reason)`，`reason` 为 `UnsafeMemory` / `UnsafeCostTime` / `UnsafeTimeout` / `DeleteRoom` 或平台原因）、`玩家-加入`（`(player)`）、`玩家-退出`（`(player, reason)`，`reason` 为 `CLIENT_GIVE_UP` / `CONNECTION_LOST` / `kick by server` 等；派发前已置 `player.exited = true`）
- ⚠️ `event_on` 回调的**第一个参数是 `Trigger`**（`fun(trg, ...)`），事件参数从第二个开始。漏掉它就等于把 `trg` 当业务参数：`function (player)` 拿到的是 trigger，读 `player.role_id` 得 nil → `table index is nil`。一律写成 `function (_, player)`
- 存档走 `Player:get_save()` 拿表，别自己再包一层 `set`/`get`；解析失败不覆盖旧档
- 回调一律兜底：事件 / 定时器 / RPC 处理器统一用 `xpcall(fn, Log.error, ...)`，单个回调抛错不许打哑后续事件；业务新写的事件回调、`y3.timer.*` 回调照此处理
- base64 用 `y3.base64`；二进制跨端必须 base64（原样上行会丢非法 UTF-8、下行含 `\0` 会打断通道）
- 给命名空间补接口直接写 `function y3.unit.xxx()`（赋值到命名空间的字段，如 `y3/game/unit/unit_attr.lua`）；**不要**先 `local API = y3.unit` 再 `function API.xxx()`——对类引用赋值会触发 LuaLS `inject-field`，只能在赋值处再补一遍 `---@class Unit.API` 才不报。跨文件的命名空间类（`Unit.API`）只在 `y3/game/unit/init.lua` 声明一次
- 类型标注跟着实现走，**不写多余的 `---@field`**：实例字段由 `self.x = ...` 赋值自动推导（`Unit` 的 `current_pos` / `is_moving` / `target_pos` 都靠这个，别手写）；**类上的函数更不必写**——`function M:xxx()` / `function y3.player.xxx()` 定义一次，签名和返回类型就推导出来了，`---@field xxx fun(...)` 只是复述（`CloudTimer.on_timer`、`Player.API.attr_drain` 这类重复声明都已删）。签名用 `---@param` / `---@return`。只有推导不出来的才写：纯数据形状（`Unit.Data` 这种只由表字面量构造、无实现可推）；需要明确非空类型时用 `---@type integer` + `M.uid = 0` 在类文件里声明一次
- 只 `include`/`require` 库与业务模块，不依赖本地文件与 C 模块

## 12. 参考

- 原生接口 / 配额 / 排错：`../cloud-script-native/SKILL.md`
- 引擎官方手册：`../cloud-script-native/references/CloudScript.md`
- 客户端库：`global_script/y3/doc/skills/y3-lib/SKILL.md`
