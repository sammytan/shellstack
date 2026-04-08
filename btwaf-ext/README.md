# BTwaf（宝塔 WAF）模块说明

本目录收录 **宝塔面板 BTwaf**（宝塔网站防火墙）相关的 OpenResty / Nginx Lua 代码片段与参考配置，与面板内 `/www/server/btwaf` 部署结构对应。

## 内置缓存 Lua 模块（`btwaf/lib/cache.lua`）

BTwaf 在 `init.lua` 中通过 `cache = require "cache"` 加载 **`btwaf/lib/cache.lua`**。该模块是 **基于 Redis 的页面/接口缓存辅助层**，用于在 WAF 流程中读写缓存数据（例如与 PHP 等业务响应相关的缓存条目）。

### 行为概要

- **后端**：使用 `lua-resty-redis` 连接本机 Redis（默认 `127.0.0.1:6379`，数据库 `0`）。
- **键名规则**：统一前缀 `php_cache:`，由 **URI + 可选查询串** 组成，例如：`php_cache:/path?a=1`。
- **存取格式**：缓存值为 **JSON**，经 `cjson` 编码后写入 Redis；读取时再解码为 Lua 表。
- **默认过期时间**：`DEFAULT_TTL = 180` 秒（3 分钟，可在模块内按需调整）。
- **对外接口**（模块 `return` 表）：
  - `get_cached_content(uri, query_string)`：命中返回解码后的表，未命中返回 `nil`。
  - `set_cached_content(uri, query_string, content, ttl)`：写入缓存，`ttl` 可选。
  - `delete_cache(uri, query_string)`：删除单条。
  - `clear_all_cache()`：按前缀 `php_cache:*` 批量删除（依赖 `KEYS`，数据量大时注意 Redis 影响）。

### 与配置的关系

`btwaf/lib/config.lua` 中另有 **cache 相关配置项**（如 `prefix`、`default_ttl`、`max_ttl`），与面板 JSON 配置配合使用；`cache.lua` 内当前为 **写死的 `redis_config` 与 `CACHE_PREFIX`**，若环境与默认不一致，需在 `cache.lua` 或上层封装中改为与 `config.lua` / `config.json` 一致，并保证 **Redis 已启动且可连**。

### 依赖

- OpenResty / ngx_lua 环境。
- `resty.redis`、`cjson` 等 Lua 库（通常由宝塔 Nginx 站点 `lualib` 提供）。
- 本机或网络可达的 **Redis** 服务。

### 相关 Nginx 配置参考（`btwaf.conf`）

`lua_shared_dict cache_shared` 等共享字典与 `lua_package_path` 用于 WAF 主流程与其它子模块；**Redis 缓存逻辑在 `cache.lua` 中实现**，与 `cache_shared` 字典用途不同，请勿混为一谈。

### 版权声明

`init.lua` 等文件头注释标明：**宝塔 Linux 面板**相关代码版权归属宝塔软件（bt.cn）。本仓库文件仅作说明与备份，使用与分发请遵循原软件许可证及宝塔用户协议。
