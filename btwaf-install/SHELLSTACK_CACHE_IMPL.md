# ShellStack Redis 页缓存 — 植入任务文档

本文档与仓库 **`btwaf-ext/README.md`** 中「`--extend-btwaf-cache` / 内置缓存 Lua」一节对齐，记录宝塔网站防火墙（`btwaf`）**官方安装包（`btwaf-install`）**内整页 Redis 缓存的完整植入范围。

## 一、与 btwaf-ext/README.md 的对应关系

| README 要求 | 本安装包实现 |
|-------------|----------------|
| `lib/cache.lua` | `shellstack_impl/lib/cache.lua` → `/www/server/btwaf/lib/cache.lua` |
| `lib/shellstack_cache_config.lua` | `shellstack_impl/lib/shellstack_cache_config.lua`（读面板 JSON；纯 Lua 表参考见 `reference/`） |
| `body.lua` 中 `schedule_body_page_cache` | `shellstack_impl/overlay/body.lua` 覆盖官方 `body.lua`（避免官方提前 `return` 导致永不写 Redis） |
| `waf.lua` 在 `btwaf_run` 成功后再 `try_access_cache_hit` | `install.sh` 向 `waf.lua` 末尾幂等追加（标记 `shellstack_page_cache_after_btwaf`） |
| `init.lua` 中 `cache = require "cache"` | `install.sh` 在 `Json = require "cjson"` 下一行幂等插入 |
| `header.lua` 中响应头阶段写 `X-Shellstack-*` | `install.sh` 向 `header.lua` 末尾幂等追加 `apply_header_filter_headers`（标记 `shellstack_header_cache_hook`） |
| `btwaf.conf` 中 `lua_shared_dict cache_shared` 与扩展 `lua_package_path` | 已合并进安装包根目录 **`btwaf.conf` / `btwaf2.conf`**（与 ext 一致为 **5000m**，小内存机器请改小）；**`shellstack_impl/reference/btwaf.conf.btwaf-ext`** 为 ext 原文对照 |

## 二、功能说明

- **access**：`waf.lua` 末尾在 `ok == true` 时调用 `try_access_cache_hit()`。
- **body_filter**：`body.lua` 在响应体合并完成后调用 `schedule_body_page_cache(nil, whole)`，`nil` TTL 表示使用 `shellstack_cache_config.page_ttl_seconds`（面板 JSON）。
- **header_filter**：`header.lua` 末尾调用 `apply_header_filter_headers()`，写入 `X-Shellstack-Cache*` 等（可通过环境变量关闭，见 `cache.lua` 注释）。
- **配置**：`/www/server/panel/plugin/btwaf/shellstack_cache_config.json`；保存后 `nginx reload`（`btwaf_main.set_shellstack_cache_config`）。

## 三、任务清单（文件级）

| 序号 | 任务 | 位置 |
|------|------|------|
| 1 | 缓存核心 | `shellstack_impl/lib/cache.lua` |
| 2 | 配置加载（JSON） | `shellstack_impl/lib/shellstack_cache_config.lua` |
| 3 | 默认 JSON | `shellstack_impl/shellstack_cache_config.json` |
| 4 | 纯 Lua 表示例（可选参考，非运行时默认） | `shellstack_impl/reference/shellstack_cache_config.static.example.lua` |
| 5 | `body.lua` 覆盖 | `shellstack_impl/overlay/body.lua` |
| 6 | `install.sh`：lib、body、init、header、waf、json | `install.sh`「ShellStack」段 |
| 7 | 面板 API + UI | `btwaf_main.py`、`index.html` |
| 8 | Nginx WAF 片段：`cache_shared` + `lua_package_path` | `btwaf.conf`、`btwaf2.conf`（安装时复制到 `vhost/nginx/btwaf.conf`） |

## 四、升级官方 `btwaf_lua` 时的合并步骤

1. 放入官方 **`btwaf_lua/`** 完整目录。
2. 保留 **`shellstack_impl/`** 与 `install.sh` 中 ShellStack 段。
3. 若官方修改了 **`body.lua` 的 `run_body`** 结构，需将 **`btwaf-ext/btwaf/body.lua`** 或本包 **`overlay/body.lua`** 与新版手动合并，保留：缓冲合并、`eof` 时 `schedule_body_page_cache`。
4. 检查 **`init.lua`** 是否仍为 `Json = require "cjson"` 单行；若格式变化，需调整 `install.sh` 中的 `awk` 匹配规则。
5. 检查 **`waf.lua` / `header.lua`** 末尾标记是否仍在；若官方大改文件，可手动补回 `install.sh` 中三段 heredoc 内容。

## 五、相关路径速查

| 路径 | 说明 |
|------|------|
| `/www/server/panel/plugin/btwaf/shellstack_cache_config.json` | 面板持久化配置 |
| `/www/server/btwaf/lib/cache.lua` | 缓存逻辑 |
| `/www/server/btwaf/lib/shellstack_cache_config.lua` | 配置加载模块 |
| `/www/server/btwaf/body.lua` | ShellStack 覆盖版（含 body 写 Redis） |
| `/www/server/btwaf/init.lua` | 含 `cache = require "cache"` |
| `/www/server/btwaf/waf.lua` | 末尾 access 命中钩子 |
| `/www/server/btwaf/header.lua` | 末尾 header 响应头钩子 |
| `/www/server/panel/vhost/nginx/btwaf.conf` | 由包内 `btwaf.conf`/`btwaf2.conf` 安装；含 `lua_shared_dict cache_shared` 与扩展 `lua_package_path` |

**注意**：`cache_shared 5000m` 与 **btwaf-ext/btwaf.conf** 一致，占用共享内存较大；若服务器内存紧张，请把该项改为例如 `128m` 或 `512m` 后再 `nginx -t && nginx -s reload`。当前 `cache.lua` 仍以 `ngx.shared.spider` 为主；`cache_shared` 供扩展或其它脚本使用 `ngx.shared.cache_shared`。
