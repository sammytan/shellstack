# BTwaf（宝塔 WAF）模块说明

本目录收录 **宝塔面板 BTwaf**（宝塔网站防火墙）相关的 OpenResty / Nginx Lua 代码片段与参考配置，与面板内 `/www/server/btwaf` 部署结构对应。

## 与 ShellStack `--extend-btwaf-cache` 的配合

1. **扩展文件来源（任选）**：① 在运行脚本的服务器上**完整克隆本仓库**，使 `btwaf-ext/btwaf` 与 `modsecurity` 目录同级；② 或把本机 **`btwaf-ext/btwaf`** 目录上传到服务器任意路径，执行前设置 **`SHELLSTACK_BTWAF_OVERLAY_SRC=/该路径/btwaf`**；③ 或将 `btwaf-ext/` 同步到你的 **`SHELLSTACK_BASE_URL`（或 `BASE_URL`）** 静态站点下，保证可访问  
   `https://<你的站点>/btwaf-ext/btwaf/lib/cache.lua`  
   脚本在本地找不到目录时会自动 **curl/wget 下载**；④ 仅缺 `cache.lua` 时可设 **`SHELLSTACK_BTWAF_CACHE_LUA_URL`** 为单文件直链（如 GitHub raw）。
2. 执行 ModSecurity 主脚本的 `--extend-btwaf-cache`：脚本会依次运行 **`/www/server/panel/plugin/btwaf/install.sh install`**（需已安装面板「宝塔网站防火墙」插件）、通过 **`install_soft.sh` 安装 Redis**（若 6379 未就绪）、再将 **`btwaf-ext/btwaf`** 中的 **`lib/cache.lua`、`body.lua`、`waf.lua`** 覆盖到 **`/www/server/btwaf`**（若未带 `waf.lua` 会尝试向官方 `waf.lua` **自动注入** access 缓存命中块），并在 **`nginx` 的 `btwaf.conf`** 中按需加入 `lua_shared_dict cache_shared 5000m;`，在 **`init.lua`** 中若无则自动插入 `cache = require "cache"`（支持 sed / perl，无需手改）。
3. **部署后即用**：`lib/cache.lua` 提供 **`try_access_cache_hit`**（access 阶段读 Redis，键与 body 阶段写入一致）与 **`schedule_body_page_cache`**（body_filter 异步写）；`waf.lua` 在 `pcall(btwaf_run)` 之前调用前者，无需再改 `header.lua`。默认 **Redis 页缓存不读宝塔的 `$skip_cache`**，可与 **FastCGI 缓存**同时开（FastCGI 仍用 `$skip_cache` 绕过）；仅跳过 Redis 时在站点 `server` 内初始化 `set $shellstack_skip_cache 0;`，需要处再 `set $shellstack_skip_cache 1;`。若要让 Redis 与 FastCGI 共用绕过条件，在 `cache.lua` 设 **`PAGE_CACHE_HONOR_NGINX_SKIP_CACHE = true`**。
4. **不建议**整目录替换官方 WAF；若必须用旧版 `btwaf.tar.gz` 全量包，可设 **`SHELLSTACK_BTWAF_LEGACY_TARBALL=1`**（仍建议随后再 overlay 扩展文件）。

## 内置缓存 Lua 模块（`btwaf/lib/cache.lua`）

BTwaf 在 `init.lua` 中通过 `cache = require "cache"` 加载 **`btwaf/lib/cache.lua`**（若官方未带此行，由部署脚本自动插入）。该模块是 **基于 Redis 的页面/接口缓存辅助层**，用于在 WAF 流程中读写缓存数据；**body_filter 中的整页异步写入**已统一调用 **`cache.schedule_body_page_cache`**，避免与 `body.lua` 重复实现 Redis 逻辑。

### 行为概要

- **后端**：使用 `lua-resty-redis` 连接本机 Redis（默认 `127.0.0.1:6379`，数据库 `0`）。
- **键名规则**：整页缓存在 **Redis STRING**，键名 **`btwaf_cms_cache:`** + **md5(签名串)**；签名由 `PAGE_CACHE_SIGN_COMPONENTS` 决定（默认含 `site` / `uri` / `args` / `ua`）。可增删项：`referer`；`headers` 或 `headers:all` / `headers:*`（全部请求头，名小写、按名字排序）；`headers:cookie,accept-language`（仅列出头，缺省按空值参与签名）。与官方 `waf.lua` 一致：无 UA 时为 `btwaf_null`。
- **存取格式**：缓存值为 **JSON**，经 `cjson` 编码后写入 Redis；读取时再解码为 Lua 表。
- **默认过期时间**：`PAGE_CACHE_TTL_SECONDS`（默认 180 秒）；写入用 **SETEX**，过期由 Redis TTL 管理。
- **对外接口**（模块 `return` 表）：
  - `try_access_cache_hit()`：access 阶段调用，命中则直接响应并 `ngx.exit(200)`，未命中则返回。
  - `schedule_body_page_cache(ttl, whole)`：body_filter 在整页响应后异步 **SETEX** 写入 Redis。
  - `get_cached_content(uri, query_string, explicit_site?, explicit_ua?, opts?)`：**GET**；无 ngx 且签名含 `ua` / `referer` / `headers:*` 时须在 `opts` 中传 `{ referer = "...", headers = { ... } }`。
  - `set_cached_content(uri, query_string, content, ttl, explicit_site?, explicit_ua?, opts?)`：**SETEX**。
  - `delete_cache(uri, query_string, explicit_site?, explicit_ua?, opts?)`：**DEL** 当前签名对应键；全量用 `clear_all_cache()`。
  - `clear_all_cache()`：删除 `btwaf_cms_cache:*`，并清理旧版 `php_cache:*`（依赖 `KEYS`，数据量大时注意 Redis 影响）。

### 与配置的关系

`btwaf/lib/config.lua` 中另有 **cache 相关配置项**（如 `prefix`、`default_ttl`、`max_ttl`），与面板 JSON 配置配合使用；`cache.lua` 内 Redis 连接以环境变量 **`SHELLSTACK_REDIS_*`** 为准；页缓存键前缀、签名段、默认 TTL、**`PAGE_CACHE_HTML_PATH_HINTS`**、**`PAGE_CACHE_HONOR_NGINX_SKIP_CACHE`**（默认 `false`，与 FastCGI 的 `$skip_cache` 解耦；改为 `true` 则与 FastCGI 同步绕过）在 **`cache.lua` 顶部常量**中修改。

### 依赖

- OpenResty / ngx_lua 环境。
- `resty.redis`、`cjson` 等 Lua 库（通常由宝塔 Nginx 站点 `lualib` 提供）。
- 本机或网络可达的 **Redis** 服务。

### 相关 Nginx 配置参考（`btwaf.conf`）

`lua_shared_dict cache_shared` 等共享字典与 `lua_package_path` 用于 WAF 主流程与其它子模块；**Redis 缓存逻辑在 `cache.lua` 中实现**，与 `cache_shared` 字典用途不同，请勿混为一谈。

### 版权声明

`init.lua` 等文件头注释标明：**宝塔 Linux 面板**相关代码版权归属宝塔软件（bt.cn）。本仓库文件仅作说明与备份，使用与分发请遵循原软件许可证及宝塔用户协议。
