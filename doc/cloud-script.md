# Y3 云脚本开发

> 本文是云脚本开发规范与实测结论的归档文档（原编辑器 skill 文档）。引擎官方 API 手册见同目录 `CloudScript.md`。

云脚本在**云脚本服务**中处理玩家请求、查询玩家与道具信息、读写存档，并把结果发回客户端。

**云脚本不是地图脚本**，也不是项目脚本：不放在 `maps/<地图名>/script/`，也不放在 `global_script/`；运行环境里**没有 `y3.*` 框架、没有项目自己的 `ac.*` 封装、没有 `Class`、没有 `include`**，加载模块一律用 `require`，日志用大写的 `Log`（不是地图脚本里的 `log`）。

---

## 0. 目录位置

`cloud_script/` 位于**项目根目录**（与 `global_script/`、`maps/` 同级），**不要**放进 `global_script/`（那是地图脚本，走 `include` 加载链）。

```
<项目根目录>/
├── cloud_script/
│   ├── main.lua             # 唯一入口，只做 require 编排
│   ├── meta.lua             # 仅 IDE 类型提示，运行时不要 require
│   ├── core/                # 基础能力（rpc / log / env / archive 等，按需）
│   ├── game/                # 业务模块
│   ├── excel/               # 云脚本专用导表产物
│   ├── util/                # 通用工具（纯 Lua 实现）
│   ├── dev/                 # 开发自测（echo / rpc 示例 / 调试探针）
│   ├── dump/                # 产物：调试转储，不提交、打包排除
│   ├── mls_archive/         # 产物：本地存档测试数据
│   ├── mls_log/             # 产物：云脚本服务日志
│   └── script_log/          # 产物：脚本日志（Log 输出）
├── global_script/           # 地图脚本根（入口 global_main.lua）
└── maps/<地图名>/script/    # 地图侧脚本目录
```

约定建议：

- 根目录只留 `main.lua` 与 `meta.lua`，其余进子目录
- 发布打包必须**排除日志与产物目录**：`mls_log/`、`script_log/`、`dump/`
- 新建 Y3 项目默认**没有** `cloud_script/`，需从官方示例项目复制基础结构后替换业务代码

## 1. 入口与 require 规则

```lua
local json = require 'cjson'    -- 服务提供
require 'core.rpc'              -- 自己的模块按目录写
require 'game.xxx'
```

- require 根目录是 `cloud_script/`，不写 `.lua` 后缀：`cloud_script/core/rpc.lua` → `require 'core.rpc'`
- 路径区分大小写，必须与实际文件名一致
- `main.lua` 保留为唯一入口；`meta.lua` 只用于补全/静态检查，**不要**在入口中加载

**require 的搜索根（实测，本地 Mock 与线上同构）**：`package.path` 只有 `<cloud_script 落点>/lua/?.lua`、`<落点>/?.lua`、`../share/lua/5.4/?.lua`（另加 CWD 的 `./?.lua`），即 **`cloud_script/` 根内可 require，根外一律 `module not found`**（不会向上跳目录）。

- 结论：**云脚本读不到 `global_script/excel/` 的配表**。要用配表就让导表工具额外产出一份放到 `cloud_script/` 根，再 `require("<表名>")`
- 语言为 **Lua 5.4**：`load` 可用，**`loadstring` 已不存在**
- **不能 load 本地 lua54 生成的 bytecode**：`load(string.dump(fn))` 报 `bad binary format (float format mismatch)`——云端只 `load` 源码文本 `load(src, name, 't')`；需要 bytecode 的场景（如下发给客户端执行）才用构建机 dump，且必须由**客户端**去 load
- **改已有文件内容不用重启**（本地 Mock 直接映射目录）；**新增文件、或改 `main.lua` 的 require 列表要重启**；已加载模块有 require 缓存，同进程内改文件不重读（`package.loaded['<模块>'] = nil` 再 require）

迁移清单（对齐官方「新项目初始化与文件迁移」）：

| 示例项目里的文件 | 必要性 | 说明 |
|---|---|---|
| `cloud_script/main.lua` | **必需** | 唯一入口；保留基础 require、删掉示例测试模块的加载行，再加自己的业务模块 |
| `cloud_script/meta.lua` | 推荐 | 为 `RegisterEvent` / `Ms*` / `redis` / `Log` / `Timer` 提供类型提示；运行时不要 `require`。示例工程的清单常是**部分清单**，新增 API 调用后要顺手补声明，完整签名以官方《云脚本参考项目》的 `meta.lua` / `ms_api.lua` 为准 |
| `cloud_script/com_api.lua` | 按需 | 示例通用字符串工具，只有仍被 require 才复制 |
| `cloud_script/ms_api.lua` | 按需 | `LogInfo` / `LogWarn` / `LogClient` 等测试封装；正式业务不需要就删掉（`LogClient` 上线前必须移除或禁用） |
| `cloud_script/dao/*.lua` | 按需 | 示例的玩家/房间数据对象，复制后必须改成自己的数据模型 |
| `cloud_script/testcase/*.lua` | 测试专用 | **生产入口不要加载** |
| `cloud_script/game_entry.lua` | 不需要 | 历史兼容文件，不会被自动加载 |
| `dump/` `mls_archive/` `mls_log/` `script_log/` | **不迁移** | 运行/测试产物 |

迁移后验证顺序：① 确认 `main.lua` 里每个 require 都能在 `cloud_script/` 下找到；② 用 Y3 开发助手起本地模拟服务（**先不要开多开模式**）；③ 云脚本日志里确认入口与监听器已加载（`xxx: listener ready`）；④ 再从客户端发一次测试事件。

### meta.lua 写法约定（硬规则）

所有 `---@meta` 文件都按这个写法，**不要**用「重复 `---@class`」「往表里塞空函数」「赋 nil」去消 `missing-fields`：

```lua
---@class Redis
redis = {}

---@return RedisClient
function redis.get_redis_client() end
```

| 场景 | 写法 |
|---|---|
| 全局表/命名空间 | `---@class X` 只写一次 → `X = {}` → 需要补能力就写函数定义 |
| 表上的函数 | **显式函数定义** `function X.f(a, b) end` + 上方 `---@param` / `---@return`；**不要**用 `---@field f fun(...)` |
| 函数有重载 | 才用 `---@type fun(...)` 多行叠加或 `---@overload` |
| 实例方法（类） | `---@class C` + `local C = {}` + `function C:m(...) end` |
| 常量/枚举表 | `---@class E` + `---@field` 作文档，**直接给值** |

补充：`---@meta` 文件运行时不加载，但**不要**给全局赋 `nil` 或塞空函数；改这类文件**只改目标块**（避免整文件重排把 diff 变成噪音）。

---

## 2. 两端通信契约

客户端与云脚本是**两个运行环境**，不共享 Lua 变量。

```
[客户端 global_script/（地图脚本根）]
  y3.game.send_mlscript_msg("事件名", {表})        -- 上行，只支持基本类型
        ↓
[云脚本 cloud_script/]
  RegisterEvent("事件名", function(event_idx, role_id, event_name, evalue) ... end)
  MsSendMlEvent(role_id, "回复事件名", 编码后的字符串)  -- 下行
        ↓
[客户端] y3.game:event("玩家-收到云脚本消息", function(trg, data) ... end)
```

最小双端骨架：

```lua
-- cloud_script/tutorial_hello.lua
local json = require("cjson")
RegisterEvent("GuideHello", function(event_idx, role_id, event_name, evalue)
    local ok, request = pcall(json.decode, evalue)
    if not ok or type(request) ~= "table" then
        Log.warn("GuideHello: invalid JSON object")
        return
    end
    local response = json.encode({ msg = "Hello from cloud" })
    local code = MsSendMlEvent(role_id, "GuideHelloReply", response)
    if code ~= 0 then
        Log.warn("GuideHello: send failed, code=" .. tostring(code))
        return
    end
    Log.info("GuideHello: reply submitted, role=" .. tostring(role_id))
end)
Log.info("GuideHello: listener ready")
-- main.lua 中加：require("tutorial_hello")
```

```lua
-- 地图脚本侧（global_script/ 下任意被加载的文件）
y3.game:event("玩家-收到云脚本消息", function(trg, data)
    if data.mlscript_event_name ~= "GuideHelloReply" then return end
    local response = data.mlscript_event_data
    if response == nil then return end
    print(tostring(response.msg))
end)

y3.game:event("键盘-按下", "SPACE", function()
    y3.game.send_mlscript_msg("GuideHello", { msg = "Hello from client" })
end)
```

### 易错点（必读）

| 项 | 事实 |
|---|---|
| 上行参数 | 只支持整数/浮点数、布尔、字符串、表；传玩家对象等会在发送时序列化失败。要带玩家信息就传 `data.player:get_id()` |
| 上行编码 | 客户端接口直接收 Lua 表，**不要**多做一次编码 |
| 云脚本侧 `evalue` | 是字符串，需 `json.decode` |
| 客户端侧 `mlscript_event_data` | Y3 已封装为可按字段访问的对象，无须解码，**不能**假定 `type()` 是 table |
| 下行广播 | 消息广播给房间内**所有**客户端（同步帧下各端拿到同一份事件，含目标玩家字段）；客户端必须按事件里的玩家字段过滤：`if data.player:get_id() ~= 本机玩家:get_id() then return end` |
| 下行回调的上下文 | **同步帧**，不是本地帧：① 可直接写全局逻辑（造单位 / 发奖 / 改属性），不必过 `y3.sync.send`；② 挂**单位挂点**的场景 UI 必须 `y3.ltimer.wait_frame(1, ...)` 切本机帧再建，否则状态全对但**不渲染且无报错**；③ 同步上下文遍历用 `y3.util.sortPairs`，不用 `pairs`；④ 不要依赖"哪条先到"的时序差异做判定 |
| 两端关联 | 官方**不提供**：上行无返回值 / 无回调，下行事件无 msg_id / 无 ack，`MsSendMlEvent` 的 `code == 0` 只代表已入队。要请求-响应语义就自造——payload 里塞自造 id（如 `seq`），收端按事件名 + 玩家 + id 三重过滤，并自己配超时清理 |
| 上行重复发送（**待确认**） | 若在同步上下文里裸调 `send_mlscript_msg`，各端可能各发一条 → 云脚本收到重复请求（重复扣费/发奖）。接入多端业务前先实测确认 |
| 自定义事件名 | 不要以 `_` 开头，该前缀是系统事件；上行名与下行名互相独立，引擎与服务都不校验两者关系 |
| 两端日志函数不同 | 云脚本用 `Log.info/warn/error`；地图脚本用 `log.*`（`y3` 封装），混用会直接报错 |

ECA 等价写法：发送用【游戏 - 发送云脚本自定义消息】（字符串事件名 + 表数据）；接收监听【游戏 - 收到云脚本自定义消息】（云脚本数据表 / 事件名 / 目标玩家）。

### 玩家标识

| 标识 | 来源 | 含义 |
|---|---|---|
| `role_id` | 玩家相关或自定义事件的回调参数 | **局内玩家 ID**，对局开始按槽位分配，一局内不变，不保证连续；可直接作为房间内 key |
| `plat_aid` | `_playerjoin` 附加参数里的 JSON 字符串 `{"plat_aid":"<用户唯一ID>"}` | **用户唯一 ID**，跨局稳定 |
| `data.player:get_id()` | 客户端 Player 对象 | 数值等于回调的 `role_id`，仅作自检，不能单独作为身份依据 |
| `player_guids` | `_roomloaded` 附加参数 | 本局局内玩家 ID 序列（`userdata`，非 table） |

- 处理请求直接用回调给的 `role_id`
- 房间级事件（`_roomloaded` / `_roomover` / `_localmodeloaded`）的 `role_id` 是 `-1`，直接传给玩家接口不会作用于任何玩家
- `player_guids` 可用 `ipairs` 遍历，**不要**直接交给 JSON 编码
- 生命周期顺序：断线先 `_playerleave`，3 分钟后 `_playerexit`；`_playerreconnect` 只清除断线状态，不撤销已发生的退出

---

## 3. API 与返回值约定

### 先看返回值约定（最重要）

| 接口类别 | 判断方式 |
|---|---|
| 查询玩家/房间信息 | 检查是否返回 `nil` |
| 保存玩家存档 | 判断 boolean |
| 发送消息、消耗道具 | `code == 0` |
| Redis | 先看第一个返回值，再校验第二个值是结果还是错误文本 |

`0` 和空字符串在 Lua 里都是真值，`if MsTryConsumeItem(...) then` 判断不了成功。

**`json.encode` 会因「稀疏数组」整体失败（实测）**：表里只有数字键、且**最大键 > 数组长度 + 10** 时，lua-cjson 直接抛 `excessively sparse array`，`pcall(json.encode, ...)` 返回 false ⇒ 写档整体失败（表现为 `MsSaveScriptArchive` 根本没被调用）。

- 典型翻车：`unlocked[37] = true`（只有 37 一个键）→ 每次落档都失败；`unlocked[7]` 反而侥幸通过（7 < 0 + 10）
- 连带约束：读档时**不要**做「数字键归一」（把 `"7"` 转成 `7`）——转了下次保存又变稀疏数组
- **设计规则（硬性）**：只有「长度由代码固定且必然填满」的序列才用数组，其余**一律字符串 key**（以 id / 类型 / 名称为键的映射）。判据：*这张表的长度是不是代码写死且每次填满？*

### 事件

```lua
local event_idx = RegisterEvent(event_name, callback)
UnRegisterEvent(event_idx)
```

回调公共参数依次为 `event_idx, role_id, event_name`，后接各事件附加参数。

| 事件 | 用途 / 附加参数 |
|---|---|
| `_roomloaded` | 房间加载完成；`player_guids`；`role_id` 为 -1 |
| `_roomover` | 房间结束；`reason: string`（`UnsafeMemory` / `UnsafeCostTime` / `UnsafeTimeout` / `DeleteRoom` 或平台原因）；`role_id` 为 -1 |
| `_playerexit` | 玩家退出；`reason`：主动退出 `CLIENT_GIVE_UP`、断线超时 `CONNECTION_LOST`、被踢 `kick by server` |
| `_playerleave` | 玩家断线（早于同一次断线的 `_playerexit`）；`reason` 固定 `player disconnect` |
| `_playerreconnect` | 断线重连；`reason` 固定 `player reconnect` |
| `_playerjoin` | **玩家存档加载完成、该玩家的云脚本数据可用时**触发（首次进房，以及房间已运行时补加载完成）；附加参数是 JSON 字符串 `{"plat_aid":"<用户唯一ID>"}`——这是「能开始读该玩家存档」的最早时机，也是拿 `plat_aid` 的唯一来源 |
| `_item_info_changed` | 道具信息变化（扣减生效后）；`store_id, before_cnt, after_cnt`（integer） |
| `_obtain_item_notify` | 玩家**购买**道具时；`store_id, before_cnt, after_cnt` |
| `_consume_item_notify` | 道具**消耗**扣减生效后；`store_id, before_cnt, after_cnt` |
| `_localmodeloaded` | 本地模拟服务的房间加载；`role_id` 为 -1 |
| 业务自定义名称 | 接收客户端上行消息；`evalue: string`，单条上限 10 KB |

### 玩家查询

| 接口 | 返回 | 注意 |
|---|---|---|
| `MsGetPlayerName(role_id)` | string / nil | 玩家或房间不存在返回 nil |
| `MsGetPlayerMapLevel(role_id)` | integer / nil | 本地模拟服务固定为 1 |
| `MsGetPlayedTime(role_id)` | integer / nil | 秒；本地固定 0 |
| `MsGetPlayedCount(role_id)` | integer / nil | 本地固定 1 |
| `MsGetPlayerItem(role_id, goods_id)` | ItemInfo / nil | `goods_id` 是编辑器道具 ID |

`ItemInfo`：`stack_cnt`（当前数量）、`can_use`（消耗型 true，时限型 false）、`expired_time`（Unix 秒，无过期为 -1）、`max_stack_cnt`。

查询失败时不要对 `nil` 做字符串拼接或数值计算。

### 存档

| 接口 | 参数 | 返回 |
|---|---|---|
| `MsGetScriptArchive(role_id)` | integer | 存档字符串；**首次无存档和玩家不存在都返回 nil** |
| `MsSaveScriptArchive(role_id, data)` | integer, string | boolean |

- 自行用 JSON 定义字段结构和版本；解析失败时不要把旧存档替换为空档
- 上限 1,048,576 字节；超限返回 false 并写云脚本日志
- **本地测试**：本地模拟服务**支持存档读写**，落盘在 `cloud_script/mls_archive/<role_id>.json`，结构为 `{"saved_at": <unix 秒>, "script_data_b64": "<业务字符串的 Base64>"}`。实测链路：本地 Mock **会触发 `_playerjoin`**（本地 `plat_aid` 是伪造值，形如 `{"plat_aid":"1"}`）→ 首次 `MsGetScriptArchive` 返回 `nil` 建新档 → `MsSaveScriptArchive` 返回 `true` → **重启游戏后读回（跨进程持久化成立）**。官方声明本地事件集合／返回值／限制／存档数据都可能与线上不同 ⇒ 本地跑通只代表流程可用，线上仍需在测试环境复核
- **写档要有专用测试玩家**，并带 `schema_version` / 计数边界做兼容与迁移保护
- **可直接观察的产物**：`mls_archive/<role_id>.json` 的 `script_data_b64` 解码即可核对业务字段

**别与引擎侧 `y3.save_data` 混用（两套存档）**：

| | 云脚本存档（本节） | 引擎侧平台存档 `y3.save_data` |
|---|---|---|
| 接口 | `MsGetScriptArchive` / `MsSaveScriptArchive`（云脚本环境全局函数） | `y3.save_data.load_*/save_*/add_*`、`Player:get_save_data_*`（`y3/util/save_data.lua`） |
| 数据形态 | 一个**字符串**（自定 schema，通常 JSON），全由业务解释 | **槽位制** + 类型化（bool / integer / real / string / table），`slot: integer` |
| 权威方 | 云脚本服务（客户端无法自读自写） | 引擎；底层是 `Role.set_save_data_*` / `Role.upload_save_data`，**属同步 API，只能在同步上下文调用** |
| 上传/落库 | 退出房间约 3 秒 / 房间结束自动保存 | 调 `y3.save_data.upload_save_data(player)` 显式上传 |
| 适用 | 需要服务端权威、防作弊的业务数据 | 引擎侧便捷的小型玩家数据 |

建议：玩家存档与 Redis 全局存档的结构、字段、以及**每个区域的存储占用预估**登记到项目自己的存档文档，改档与代码同笔提交。

### 道具消耗

```lua
local code = MsTryConsumeItem(role_id, item_store_id, cnt)   -- cnt 应为正整数
```

错误码：`0 OK` / `2 RoomNotExist` / `3 PlayerNotExist` / `12 ItemNotExisted` / `13 ItemNotEnough` / `14 ItemNotUse`。运行时**不保证**提供带这些名称的全局枚举，可直接比整数或自定义局部常量；未列出的码按失败处理。

**扣减是异步生效的**：同一次回调里查询仍是旧数量，实际结果以 `_item_info_changed` / `_consume_item_notify` 的 `before_cnt`/`after_cnt` 为准，不要在同一个回调里立即按新数量发奖。

### 房间信息（无参数，单位秒）

`MsGetRoomLoadedTs()` / `MsGetRoomGameTime()` / `MsGetRoomPlayerCount()` → integer / nil（房间不存在为 nil）。
游戏时长用 `MsGetRoomGameTime`，定时用 `Timer`；秒值不要直接当 `Timer.new_timer` 的毫秒间隔。

### 下行消息

```lua
local code = MsSendMlEvent(role_id, event_name, event_msg)
```

- `event_name` 最长 32 字节，`event_msg` 最长 10,240 字节（长度等于上限可通过）
- 事件名超限返回 `4`，消息超限返回 `6`，超限消息不进入发送队列
- 返回 `0` 只表示已被接受入队，不代表客户端已收到并处理
- `role_id` 只是消息携带的目标玩家，消息仍广播给全房间
- 发 JSON 时按**编码后**的字符串检查长度（`#` 得到字节数，中文占多字节）

`MsEnd(role_id, reason)` 已废弃，不要在新代码或测试中调用。

### 地图全局存档（Redis）

```lua
local client = redis.get_redis_client()   -- 当前地图共享一份跨房间数据
client:Get(key, callback)
client:Set(key, value, callback)          -- value: string 或可转字符串的数字
client:IncrBy(key, increment, callback)   -- increment: integer
```

回调接收两个返回值：

| 情况 | 第一返回值 | 第二返回值 |
|---|---|---|
| 正常响应 | `true` | Set 为状态文本（如 "OK"）/ Get 为存储字符串或 nil / IncrBy 为递增后的整数 |
| 连接或传输失败 | `false` | 错误文本 |
| Redis 返回协议错误 | `true` | 错误文本 |

- 省略回调时调用**必须位于协程内**（`coroutine.create` + `coroutine.resume`），普通事件回调中直接 `local ok, v = client:Get(key)` 会报错
- `coroutine.resume` 成功只说明本次恢复没立即报错，不能代替后续每个操作的结果判断
- 只开放这三个方法，不支持 pub/sub、Lua script
- **可用模块**：本地 Mock 里只有 `cjson`；`mime` / `base64` / `mime.core` / `crypto` / `socket` / `lfs` / `pb` **全部 require 不到**。base64 用内置全局函数 `MsBase64Encode` / `MsBase64Decode`（见下）；加解密一类能力仍需自带纯 Lua 实现（客户端侧相反：有引擎提供的 `y3.base64` / `y3_crypto`）
- **单 value 大小**（本地 Mock 实测）：64 KB / 192 KB / 512 KB / 1 MB / 2 MB 的字符串均可 `Set` 并原样回读；官方只说「大小与总容量暂不承诺」→ 可以按「整段 JSON 单 key 原子覆盖」设计，但建议单 key 控在 200 KB 以内
- 单条 `IncrBy` 原子（跨房间适用），但多 key/多步操作**没有事务保证**，结果不明确时重试可能重复递增

### GM 协议设计建议（可选）

若项目需要 GM 通道，建议统一约定（这是设计建议，不是引擎规定）：

- 需要 GM 权限的协议（RPC 方法名与自定义事件名都算）一律加统一前缀（如 `GM.`）；业务协议不带该前缀
- 鉴权集中在一处实现，handler 入口第一段就校验，**校验失败不读任何存档 / Redis**
- 口令常量只出现在鉴权模块，`MUST NOT` 记入口令内容 / 长度 / 片段
- 环境判据用官方 `MsIsProdEnv()`；测试设施（GM 通道、`Debug.Eval` 探针、示例自测）只在非正式环境放行
- handler 需要等 Redis 回调才知道结果的，走自定义事件而非 `rpc.register`（RPC 要求同步返回）

### base64（内置全局函数，2026-11-23 实测）

```lua
local b64 = MsBase64Encode(raw)          -- string -> string，单个返回值
local raw, err = MsBase64Decode(b64)     -- 成功 string；失败 nil, "invalid base64 input"
```

| 项 | 实测行为 |
|---|---|
| 位置 | 云脚本环境**全局函数**，不需要 require；`require('base64' / 'mime' / 'mime.core' / 'crypto' / 'y3.base64')` 全部 module not found |
| 编码 | 标准字符表 + `=` 填充；数字入参会被当字符串（`MsBase64Encode(123)` → `MTIz`）；`nil` / table 抛 `bad argument #1 ... (string expected)` |
| 解码严格度 | **只接受规范填充**：缺填充（`YQ`）、半填充（`YQ=`）、带空格/换行、多余填充（`aGVsbG8==`）、URL-safe（`-`/`_`）、非法字符一律返回 `nil, "invalid base64 input"`，不抛错 |
| 二进制 | 0x00–0xFF 全字节、NUL、0xFF 均能精确往返 |
| 规模 | 1 MB 原文（编码 1,398,104 字节）往返正确，无内建长度限制迹象 |
| 封装 | 云脚本侧统一用 `y3.base64`（`y3/util/base64.lua`，内部就是 `MsBase64*`） |

用法约束：解码结果是 `nil` 必须当失败处理（不可能用返回值判断真假）；带空白/换行的外部 base64 要先自行剔除空白再交给 `MsBase64Decode`。

### JSON、日志、定时器

```lua
local json = require("cjson")   -- 不要写 cjson = {}
json.encode(value)              -- 可能失败
json.decode(text)               -- 外部输入用 pcall 捕获，再检查结构

Log.trace / debug / info / warn / error / critical (text)   -- 无需写 Log = {}

local timer_id = Timer.new_timer(ms, function(id)
    return count < 3            -- true 继续，false 停止
end)
Timer.cancel_timer(timer_id)
```

- `ms` 必须是**整数毫秒**，最小 1 ms；传 0 按 1 ms 处理；负数返回定时器 ID `0`；传浮点数报参数错误且不创建
- `null`、空数组与空对象的转换规则未明确

---

## 4. 运行限制与配额

### 启动方式决定连接的服务

| 启动方式 | 云脚本服务 |
|---|---|
| 编辑器内启动 | 本地模拟服务 |
| 独立进程启动 | 本地模拟服务 |
| 本地多开 | 线上测试环境 |
| 正式上线 | 正式环境 |

本地模拟服务的事件集合、返回值、资源限制和存档数据都可能与线上不同：本地缺少某事件**不能**推断线上不触发；日志/内存限制在本地不生效，线上都执行。
同一地图房间共享一份全局存档，测试数据会残留——用专用测试账号和带业务前缀的 key。

### 环境判据

**判断当前环境用官方接口 `MsIsProdEnv()`**（正式环境返回 `true`）——**所有测试设施**（GM 通道、调试探针、示例自测）都只在非正式环境放行；业务接口不受此限。**接口不可用时按正式环境处理**（fail-closed），并把判据收敛到一个模块里，不要在业务里各自另写。

> 历史做法（**已废弃**）：用 `os.getenv` 存在性当"本地"旁证（官方明示「不要依赖 `os`」）。

### 线上平台限制

- 业务入口不应依赖 `os`
- 上传内容以 `cloud_script` 为根、`main.lua` 为入口；线上 require **不搜索** C 模块和文件系统中的 Lua 文件
- os 可用：`clock`、`date`、`difftime`、`time`；线上**不存在**：`execute`、`exit`、`getenv`、`remove`、`rename`、`setlocale`、`tmpname`

### 资源与消息

| 项目 | 限制 |
|---|---|
| 单房间内存 | 50 MB（52,428,800 字节），按当前房间 Lua VM 的 GC 内存统计 |
| 客户端→云脚本单条上行 | 10 KB（10,240 字节），在客户端/战斗服侧检查，云脚本服务不校验上行长度与事件名 |
| 云脚本→客户端事件名 | 最长 32 字节 |
| 云脚本→客户端消息 | 最长 10,240 字节 |
| 上行内容含内嵌 `\0` | 实测**不截断**，引擎把表编码成 JSON 时转义成 `\u0000`；非法 UTF-8 字节（如 `0xFF`）则**静默丢弃**（云端收不到、无报错） |
| 下行内容含内嵌 `\0` | 实测**不能用**——`MsSendMlEvent` 返回 `0`（入队成功）但客户端收不到，且之后云端不再处理任何上行请求（疑似通道/房间 tick 被打坏） |
| 发送频率 | 上下行单玩家、单房间均无限制 |

**跨端传二进制一律 base64**：上行 NUL 虽被 JSON 转义，但下行 NUL 直接致命、非法 UTF-8 双向都不可靠。

事件先进入房间事件列表，每个 tick 按顺序处理，处理期间新增的事件留到下一批；下行按房间累积，在 tick 中批量发送。

### 执行与内存上限（线上）

- 内存超限**不是**拒绝分配：tick 之后检查，超过阈值即结束房间 → 不要长期积累大对象
- 单次事件回调执行量上限默认按 Lua 字节码指令计数，**10,000,000** 条，超限抛执行超时错误
- 整个 tick 结束后还会检查耗时：单次 tick 达 **5000 ms**，或耗时超过 500 ms 的 tick 累计达 **10 次**，都会结束房间
- `main.lua` 启动阶段同样受执行量上限约束，入口加载失败会记录错误并停止

### 存档限制

| 项目 | 规则 |
|---|---|
| 单份玩家存档 | 1,048,576 字节（1 MB） |
| 读写频率 | 无限制 |
| 写入后可读性 | 同一房间内保存成功后，后续读取直接读到新值，不需等落库 |
| 保存时机 | 玩家退出房间后约 3 秒保存并移出房间；断线本身不触发保存；房间结束时保存全部在线玩家 |
| 并发写入 | 同一账号同一时间只能运行一个对局 |

Redis：key 长度与数量无限制；value 为字符串或可转字符串的数字，调用频率无限制；正式环境不设过期，线上测试环境一天未访问后过期（`Set`、`IncrBy` 刷新）；**没有删除接口**，重置用 `Set(key, 初始值)`。

**本地模拟服务的 Redis 不跨进程持久化**：本地 Mock 的 Redis 与该次云脚本进程同生命周期，`killGame` 后重启读回是 `nil`。因此「写 Redis → 下局再生效」这类流程**本地不能靠重启验证**，要在同一进程内触发读取逻辑等价验证；线上 Redis 才具跨房间/跨进程持久性。

### 日志限制（线上生效）

| 项目 | 规则 |
|---|---|
| 频率统计范围 | 每房间共用计数器，所有日志级别与 `print` 合计，按固定秒窗口，换秒清零 |
| 频率上限 | 每秒 100 条；同一房间同一秒第 101 条起直接丢弃（不写脚本日志、不转发客户端） |
| 单条大小 | 最多 2048 字节，超出截断，末尾三字节替换为 `...`；截断按字节执行，可能截开 UTF-8 字符 |

### 定时器

- 最小间隔 1 ms；触发方式为回调可能在同一 tick 内集中执行，不保证按毫秒均匀触发
- 数量无硬性上限，但过多会推高内存和 CPU，最终可能导致房间关闭
- 房间结束进入约 5000 ms 的结束阶段，期间定时器和已返回的异步回调仍可能执行

---

## 5. 调试与排错

### 本地模拟云脚本服务怎么起来

由 Y3 开发助手随游戏启动带起（`mls_log` 出现 `[MockMls] starting`、`script_log` 出现各模块 `listener ready`）。**它与任何调试器 / 调试开关都没有因果关系**，也不需要"每个工程启用过一次"。没起来时：先确认助手侧的本地云脚本服务处于运行状态、重开游戏观察；别去怀疑 RPC / 业务代码。

**判据（别用秒数）**：进程起来后会**先加载游戏**，之后**客户端 Lua 与云脚本同时开始**——所以「Mock 起来没起来」要看**客户端 Lua 是否已经在跑**（客户端调试器附加成功即视为已在跑）。客户端还在加载时，云端本来就还没开始，零新增属正常（实测间隔可达数十秒）。**客户端已在跑而云端仍零新增，才是真没起来**。

**观测技巧**：云脚本的 `Log.info` 会**转发到客户端日志**，客户端侧以 `[mlscript]: [.\file.lua:4]Demo.Notify role=1, n=1` 的形式出现——单端调试时客户端日志里能同时看到两端输出。但**转发不是全级别**：实测 `Log.warn` **不进客户端日志**，所以用 warn 打的探针在客户端日志里看不到。判定结论：**警告 / 错误一律以 `script_log` 为准**；反过来「客户端有 log、云端 `script_log` 零新增」才是云脚本服务没起来。

**探针通道**：可自建一个「执行任意 Lua 并返回结果」的调试 RPC（如 `dev/debug_eval.lua`），客户端用 GM 命令触发，输入与结果都经 `Log` 落日志。

- 放行闸门 fail-closed：非正式环境才放行；正式环境回 `{ code = -12, message = "eval_disabled" }`
- 上行放 Lua 源码字符串，限长（如 4096 字节）；返回 `{ ok = true, values = {...} }` 或 `{ ok = false, stage = 'load'|'run'|'env', error = "..." }`
- ⚠️ **任意代码执行**：正式上线前必须删掉 `main.lua` 里对该模块的 `require`

### 按现象排查

| 现象 | 优先检查 |
|---|---|
| 启动后 `mls_log` / `script_log` 零新增 | **先看客户端 Lua 是否已经在跑**——进程刚起来时游戏还在加载。客户端已在跑而云端仍零新增才是真没起来 → 确认助手侧本地云脚本服务在运行、重开游戏 |
| 没有 `listener ready` 日志 | 入口是否加载了模块；是否有语法或模块加载错误 |
| 客户端发消息后云脚本无响应 | 事件名是否完全一致；是否在游戏就绪后触发；是否连了预期服务 |
| 云脚本有日志，客户端无结果 | 下行返回码、消息名、编码后字节数、客户端监听器是否已注册 |
| 下行返回 4 或 6 | 事件名 / 消息是否超 10,240 字节 |
| JSON 解码失败 | 云脚本是否收到字符串；客户端是否多做了一次编码；结构是否符合约定 |
| Redis 提示不能在当前上下文调用 | 改用回调形式，或把省略回调的调用放进协程 |
| Redis 返回成功但数据不对 | 第二个返回值是否其实是错误文本 |
| 定时器没有输出 | 模块是否加载；是否刚创建就取消；回调是否已返回 false；单位是否为毫秒 |
| 地图等级、时长等数据固定 | 是否在用本地模拟服务（本地有固定返回值） |
| 日志缺行或结尾被截断 | 是否超每秒 100 条；单条是否超 2048 字节 |
| 房间被结束 | 检查内存占用，以及单次回调和单 tick 的执行时长 |
| 一次回调里循环大量「读档 + 写档」后**中途没了下文**（无报错、无结果） | 触到**单次回调的字节码 / 单 tick 预算**：实测批量结算约 1200 次即被掐断。**掐断不损坏存档**（每次写档是原子的），但批量操作要**分块**（≤1000 次/块） |

### 本地产物位置（相对项目根目录）

| 内容 | 路径 |
|---|---|
| 系统日志 | `cloud_script/mls_log` |
| 脚本日志（Log 输出） | `cloud_script/script_log` |
| 本地存档（Base64） | `cloud_script/mls_archive` |
| 崩溃转储 | `cloud_script/dump` |

线上环境的日志不会写到这里。

---

## 6. 常见任务模板

每个模板放独立模块（`cloud_script/tutorial_xxx.lua`），在 `main.lua` 里 `require` 一次；示例自带局部变量，**不要依赖示例工程的 `LogInfo` / `LogClient` 等辅助函数**。

### 查询玩家信息

```lua
RegisterEvent("GuideProfile", function (event_idx, role_id, event_name, evalue)
    local name  = MsGetPlayerName(role_id)
    local level = MsGetPlayerMapLevel(role_id)
    if name == nil or level == nil then
        Log.warn("GuideProfile: player or room unavailable")
        return
    end
    Log.info("GuideProfile: name=" .. name .. ", level=" .. tostring(level))
end)
```
客户端触发：`y3.game.send_mlscript_msg("GuideProfile", {})`。本地模拟服务的地图等级固定为 1，**不能**用这个结果验证正式等级。

### 读写玩家存档（含 schema 与类型校验）

```lua
local json = require("cjson")

RegisterEvent("GuideVisit", function (event_idx, role_id, event_name, evalue)
    if type(role_id) ~= "number" or role_id < 0 then
        Log.warn("GuideVisit: invalid role; no write performed")
        return
    end

    local raw = MsGetScriptArchive(role_id)
    local archive
    if raw == nil or raw == "" then
        archive = { schema_version = 1, visits = 0 }        -- 首次无存档：nil 与空串都当空档
    else
        local ok, decoded = pcall(json.decode, raw)
        if not ok or type(decoded) ~= "table" then
            Log.warn("GuideVisit: invalid archive; no write performed")   -- 解析失败别把旧档换掉
            return
        end
        archive = decoded
    end

    local visits = archive.visits
    if archive.schema_version ~= 1 or type(visits) ~= "number" or visits ~= visits
        or visits < 0 or visits % 1 ~= 0 or visits >= 1000000 then
        Log.warn("GuideVisit: unsupported archive data; no write performed")
        return
    end

    archive.visits = visits + 1
    local encode_ok, encoded = pcall(json.encode, archive)
    if not encode_ok then
        Log.warn("GuideVisit: encode failed")
        return
    end
    if not MsSaveScriptArchive(role_id, encoded) then
        Log.warn("GuideVisit: save failed")                 -- false：超 1MB / 房间或玩家不存在
        return
    end
    Log.info("GuideVisit: save reported success, visits=" .. archive.visits)
end)
```

### 读写地图全局存档（Redis）：回调写法 vs 协程写法

```lua
-- 回调写法（推荐先用这个：下一步只能放在上一步成功的回调里）
RegisterEvent("GuideRedis", function (event_idx, role_id, event_name, evalue)
    local client = redis.get_redis_client()
    local key = "tutorial:redis:counter:v1"
    client:Set(key, 100, function (set_ok)
        if not set_ok then Log.warn("GuideRedis: Set failed") return end
        client:Get(key, function (get_ok, get_value)
            if not get_ok then Log.warn("GuideRedis: Get failed") return end
            Log.info("GuideRedis: before=" .. tostring(get_value))
            client:IncrBy(key, 2, function (incr_ok)
                if not incr_ok then Log.warn("GuideRedis: IncrBy failed") return end
                client:Get(key, function (final_ok, final_value)
                    if not final_ok then Log.warn("GuideRedis: final Get failed") return end
                    Log.info("GuideRedis: after=" .. tostring(final_value))
                end)
            end)
        end)
    end)
end)
```

```lua
-- 协程写法：省略回调时必须包在协程里（普通事件回调里直接取返回值会报错）
RegisterEvent("GuideRedis", function ()
    local co = coroutine.create(function ()
        local client = redis.get_redis_client()
        local key = "tutorial:redis:counter:v1"
        local set_ok = client:Set(key, 100)
        if not set_ok then Log.warn("GuideRedis: Set failed") return end
        local get_ok, get_value = client:Get(key)
        if not get_ok then Log.warn("GuideRedis: Get failed") return end
        Log.info("GuideRedis: before=" .. tostring(get_value))
        local incr_ok = client:IncrBy(key, 2)
        if not incr_ok then Log.warn("GuideRedis: IncrBy failed") return end
        local final_ok, final_value = client:Get(key)
        if not final_ok then Log.warn("GuideRedis: final Get failed") return end
        Log.info("GuideRedis: after=" .. tostring(final_value))
    end)
    local resume_ok = coroutine.resume(co)
    if not resume_ok then Log.warn("GuideRedis: start failed") end
end)
```
`coroutine.resume` 成功**只说明本次恢复没立即报错**，不能代替后续每个 Redis 操作的结果判断。业务用稳定、带业务前缀的 key；多 key / 多步没有事务保证。

### 会自行停止的定时器（以及取消）

```lua
-- 回调返回 true 继续、false 停止；间隔必须是整数毫秒（最小 1ms）
local count = 0
Timer.new_timer(1000, function (id)
    count = count + 1
    Log.info("GuideTimer: tick=" .. count)
    return count < 3
end)

-- 需要业务主动取消时（这里演示"在房间结束时取消"的位置，不要创建后立刻取消）
local timer_id = Timer.new_timer(1000, function ()
    Log.info("GuideTimer: running")
    return true
end)
RegisterEvent("_roomover", function ()
    Timer.cancel_timer(timer_id)
end)
```

### 查询并尝试消耗道具

```lua
-- 道具 ID 与数量由云脚本业务决定，不要直接信任客户端提交的扣减参数
local function try_consume(role_id, item_id, count)
    if type(count) ~= "number" or count ~= count or count <= 0 or count == math.huge or count % 1 ~= 0 then
        return false, "invalid_count"
    end
    local item = MsGetPlayerItem(role_id, item_id)
    if item == nil then
        return false, "item_unavailable"
    end
    if not item.can_use or item.stack_cnt < count then
        return false, "item_not_usable_or_not_enough"
    end
    local code = MsTryConsumeItem(role_id, item_id, count)
    if code ~= 0 then
        return false, code
    end
    return true, code
end
```
返回 `true` 只表示扣减接口报告成功，**扣减异步生效**：同一次回调里查到的还是旧数量，实际结果以 `_item_info_changed` / `_consume_item_notify` 的 `before_cnt`/`after_cnt` 为准。

---

## 附 A. 官方文档与示例项目

官方教程附带《云脚本参考项目》压缩包（含 `cloud_script/main.lua`、`meta.lua`、`com_api.lua`、`ms_api.lua`、`dao/`、`testcase/`），建议以本地多开运行、连接线上测试环境。新项目接入时先复制基础结构，再替换示例业务代码，并删除示例测试模块的加载行。

- 官方文档：https://163.com/y3/docs/guides/FunctionManual/CloudScript（**地址本身是对的，不要改**）。⚠️ 曾实测该地址 404 且整站导航里搜不到「云脚本」条目——**经确认为文档站临时故障**。**本地副本已入库：同目录 `CloudScript.md`**（源文档 md，含 API 参考 / 运行限制与配额 / 调试与排错），**改云脚本接口前先查它**；官网恢复后只需确认是否有增量
- **照文档抄示例时注意入口位置差异**：官方教程假设客户端入口是 `maps/<地图名>/script/main.lua`；若项目把地图脚本根放在 `global_script/`（入口 `global_main.lua`，走 `include` 链），别在 `maps/EntryMap/script/` 下另造客户端入口
- 别与引擎侧平台存档混用：`y3.save_data` 是与云脚本存档完全不同的另一套，对照见 §3 末
- 地图脚本侧出处：`y3/game/game.lua` 的 `send_mlscript_msg`、`y3/meta/event.lua` 的 `玩家-收到云脚本消息`（字段 `mlscript_event_name` / `mlscript_event_data`）；行号随框架版本变化，按符号检索

## 附 B. 参考：热更脚本类题库（可选实践）

云脚本可把「题目/校验片段」以 base64 分片下发到客户端执行，再回收结果。实践要点（通用）：

- 客户端函数会被 `string.dump` 后下发，**dump 不携带 upvalue 值** → 函数里 MUST NOT 引用文件级 `local` 常量（客户端侧是 `nil`，会报 `attempt to perform arithmetic on a nil value`）；常量写在函数体内部
- 需要整段下发的内容按 base64 分片（每片附序号），客户端解码后再 `load` 组装，注意单条消息 10,240 字节上限
- 热更内容用单个 Redis key 存整段 JSON，只留最新一份 + 毫秒时间戳版本号，与随包发布的 `build_time` 比较判断是否过期
- 只在 `_roomloaded` 读一次（不轮询），下一局生效

## 附 C. 通讯层（y3.cloud / y3.client）

两端各一个薄封装，共用传输事件 `$Y3Cloud`：

| 端 | 模块 | 全局 |
|---|---|---|
| 客户端 | `global_script/y3/game/cloud.lua` | `y3.cloud` |
| 云脚本 | `cloud_script/y3/game/client.lua` | `y3.client` |

```lua
-- 客户端
y3.cloud.request(method, data, callback)   -- callback(suc, data, err)，返回请求 id
y3.cloud.awaitRequest(method, data)        -- 必须在协程内，返回 suc, data, err
y3.cloud.notify(method, data)
y3.cloud.register(method, callback)        -- callback(data, player) 的返回值作为应答；player 由业务自行判断

-- 云脚本
y3.client.request(player, method, data, callback)
y3.client.awaitRequest(player, method, data)
y3.client.notify(player, method, data)
y3.client.broadcast(method, data)
y3.client.register(method, callback)       -- callback(role_id, data) 的返回值作为应答
```

报文：`{ i = 请求 id, m = method, d = base64(y3.seri) 业务数据, e = 错误文本 }`

- **类型由字段组合判定**，不额外传 kind：有 `i` 有 `m` = 请求；有 `i` 无 `m` = 应答；无 `i` 有 `m` = 通知
- **业务数据走 `y3.seri` 序列化后再 base64**：下行 `mlscript_event_data` 是 `py.Table`，嵌套表不会自动转 Lua 表；seri 二进制还可能含 `\0` 和非法 UTF-8 字节（上行会被静默丢弃、下行会打断通道），必须 base64
- **成败只看 `e` 是否为 nil**：跨端布尔要过 py 对象，不作为状态字段
- **目标玩家透传给业务**：下行事件自带目标玩家 `player`（即 `MsSendMlEvent` 的 `role_id`），通讯层不过滤、原样交给 handler，由业务自己判断；报文里不传目标 id
- `broadcast` 按云脚本已识别的玩家集合逐个发送（`_roomloaded` 的 `player_guids`、`_playerjoin`、任何入站消息）
- 请求超时默认 5 秒（`M.timeout`，单位秒）；超时以 `suc=false, err='timeout'` 回调
- 云脚本侧 `awaitRequest` 依赖 `coroutine.isyieldable()`，在普通事件回调里调用会直接报错
