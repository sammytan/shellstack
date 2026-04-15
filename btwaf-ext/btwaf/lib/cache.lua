-- 说明：未 require 官方 logs.lua（该文件是 Logs.start() 的入口脚本，不是通用日志 API）。
-- 缓存相关行若调用 Public.logs，与 BTwaf 一致，写入 /www/wwwlogs/btwaf_debug.log；
-- ngx.log 写入 Nginx 的 error_log（站点 error.log 或主配置里的 error_log，取决于上下文）。
--
-- 响应头：在 access 写入 ngx.ctx.shellstack_cache，在 header_filter 调用 apply_header_filter_headers()
-- 再写 X-Shellstack-*（避免 proxy_pass / fastcgi 上游覆盖 access 阶段 ngx.header）。
-- body 写入 Redis 仍无法在本响应头体现；首 MISS、次 HIT 即正常。
-- 关闭响应头：SHELLSTACK_CACHE_HEADERS=0
-- 排障：每请求 NOTICE 日志 SHELLSTACK_CACHE_TRACE=1（须 nginx env）
-- Redis：默认 127.0.0.1:6379；可设 SHELLSTACK_REDIS_HOST / SHELLSTACK_REDIS_PORT / SHELLSTACK_REDIS_DB（nginx 主配置须 env 指令声明）
local redis_ok, redis = pcall(require, "resty.redis")
local cjson = require "cjson"

local function get_redis_config()
    local h = os.getenv("SHELLSTACK_REDIS_HOST")
    if not h or h == "" then
        h = "127.0.0.1"
    end
    local port = tonumber(os.getenv("SHELLSTACK_REDIS_PORT") or "") or 6379
    local db = tonumber(os.getenv("SHELLSTACK_REDIS_DB") or "") or 0
    return { host = h, port = port, db = db }
end

local function redis_endpoint_hint()
    local c = get_redis_config()
    return " endpoint=" .. c.host .. ":" .. tostring(c.port) .. " (set SHELLSTACK_REDIS_HOST/PORT or start Redis; Baota: software store Redis + bind 127.0.0.1:6379)"
end

-- ngx.timer 内连接失败可能每请求一条，用 spider 字典 90s 内只打一条详细 ERR
local function cache_log_redis_connect_err(event, err_msg)
    local line = "[cache][" .. tostring(event) .. "] " .. tostring(err_msg or "") .. redis_endpoint_hint()
    local d = ngx.shared.spider
    if d then
        local k = "shellstack_redis_conn_err"
        if d:get(k) then
            return
        end
        d:set(k, 1, 90)
    end
    ngx.log(ngx.ERR, line)
    if _G.Public and type(_G.Public.logs) == "function" then
        pcall(_G.Public.logs, line)
    end
end

-- Cache configuration
local CACHE_PREFIX = "btwaf_cms_cache:"
-- 整页缓存在**单个 Redis Hash**（默认 btwaf_cms_cache）下：
-- field = md5(server|uri|args) 或 md5(server|uri|args|UA)（适应模式，与官方 waf 对 UA 的处理一致）。
-- SHELLSTACK_CACHE_HASH_KEY 覆盖 Hash 名；SHELLSTACK_CACHE_VARY_UA=0 关闭按 UA 分桶（仅 URL 维度）。
local DEFAULT_CACHE_HASH_KEY = "btwaf_cms_cache"
local DEFAULT_TTL = 180 -- 3 minutes in seconds
local redis_missing_logged = false

local function cache_vary_by_ua_enabled()
    local v = os.getenv("SHELLSTACK_CACHE_VARY_UA")
    if v == "0" or v == "off" or v == "no" or v == "false" then
        return false
    end
    return true
end

local function get_page_cache_hash_key()
    local k = os.getenv("SHELLSTACK_CACHE_HASH_KEY")
    if k and k ~= "" then
        return k
    end
    return DEFAULT_CACHE_HASH_KEY
end

-- 与 BTwaf 站点键一致：优先 ngx.ctx.server_name（Public.get_server_name_waf），否则 nginx 变量
-- try_access_cache_hit 早于 btwaf_run，须在命中前补全 ctx.server_name（见 try_access_cache_hit）
local function cache_page_site()
    local ctx_sn = ngx.ctx and ngx.ctx.server_name
    if type(ctx_sn) == "string" and ctx_sn ~= "" then
        return ctx_sn
    end
    local sn = ngx.var.server_name
    if type(sn) == "string" and sn ~= "" then
        return sn
    end
    return ngx.var.host or ngx.var.http_host or ""
end

local function ensure_ctx_server_name_for_cache()
    local cur = ngx.ctx and ngx.ctx.server_name
    if type(cur) == "string" and cur ~= "" then
        return
    end
    if _G.Public and type(_G.Public.get_server_name_waf) == "function" then
        local ok, sn = pcall(_G.Public.get_server_name_waf)
        if ok and type(sn) == "string" and sn ~= "" then
            ngx.ctx.server_name = sn
        end
    end
end

-- 与官方 btwaf waf.lua 一致：有 User-Agent 用原值，否则 btwaf_null（access 早于 btwaf_run 时 ctx.ua 常未设置，用 $http_user_agent）
local function cache_page_user_agent()
    local ctx_ua = ngx.ctx and ngx.ctx.ua
    if type(ctx_ua) == "string" and ctx_ua ~= "" then
        return ctx_ua
    end
    if ngx.var.http_user_agent and ngx.var.http_user_agent ~= "" then
        return ngx.var.http_user_agent
    end
    return "btwaf_null"
end

local function cache_field_signing_string(site, uri, args, ua_token)
    site = site or ""
    uri = uri or ""
    args = args or ""
    if cache_vary_by_ua_enabled() then
        ua_token = ua_token or "btwaf_null"
        return site .. "|" .. uri .. "|" .. args .. "|" .. ua_token
    end
    return site .. "|" .. uri .. "|" .. args
end

local function cache_page_field_hex()
    return ngx.md5(cache_field_signing_string(
        cache_page_site(),
        ngx.var.uri or "",
        ngx.var.args or "",
        cache_page_user_agent()
    ))
end

-- 供 delete/get/set_cached_content；explicit_ua 在无 ngx 时必须传入（与 vary 开启时一致）
local function cache_page_field_hex_for(site, uri, args, explicit_ua)
    local ua_tok = explicit_ua
    if ua_tok == nil and ngx and ngx.var then
        ua_tok = cache_page_user_agent()
    elseif ua_tok == nil then
        ua_tok = "btwaf_null"
    end
    return ngx.md5(cache_field_signing_string(site, uri, args, ua_tok))
end

local function cache_payload_expired(data)
    local t = data and data.expires_at
    if type(t) ~= "number" then
        return false
    end
    return ngx.time() > t
end

-- body_filter 里 whole 多为已解压正文，但 ngx.header 可能仍带 gzip / attachment，命中时若照搬会导致浏览器乱码或「变成下载」
local PAGE_CACHE_HEADER_SKIP = {
    ["transfer-encoding"] = true,
    ["content-length"] = true,
    ["content-encoding"] = true,
    ["content-disposition"] = true,
    ["connection"] = true,
    ["keep-alive"] = true,
    ["proxy-connection"] = true,
    ["upgrade"] = true,
    ["trailer"] = true,
    ["content-md5"] = true,
}

local function page_cache_header_should_skip(name)
    local k = string.lower(tostring(name or ""))
    return PAGE_CACHE_HEADER_SKIP[k] == true
end

-- ngx.header["Content-Type"] 可能为 string 或 table（多值），必须用首元素判断/修复
local function header_value_string(h)
    if h == nil then
        return nil
    end
    if type(h) == "string" then
        return h
    end
    if type(h) == "table" and h[1] ~= nil then
        if type(h[1]) == "string" then
            return h[1]
        end
        return tostring(h[1])
    end
    return tostring(h)
end

-- 命中时优先沿用 Redis 里保存的**原响应头**；仅当 Content-Type 为泛二进制（如 octet-stream）时，
-- 再结合**请求 Accept**（写入缓存时记录的 accept + 当前请求）与正文嗅探尝试修正，避免一律改成 text/html。
local function content_type_is_generic_binary(ct)
    if ct == nil or ct == "" then
        return true
    end
    local c = string.lower(tostring(ct))
    if string.find(c, "application/octet%-stream", 1, true) then
        return true
    end
    if string.find(c, "application/x%-download", 1, true) then
        return true
    end
    if string.find(c, "binary/", 1, true) then
        return true
    end
    return false
end

local function body_looks_like_html(body)
    if type(body) ~= "string" or body == "" then
        return false
    end
    local start = 1
    if string.byte(body, 1) == 239 and string.byte(body, 2) == 187 and string.byte(body, 3) == 191 then
        start = 4
    end
    local max_end = math.min(#body, start + 65535)
    local head = string.lower(string.sub(body, start, max_end))
    if string.find(head, "<!doctype html", 1, true)
        or string.find(head, "<html", 1, true)
        or string.find(head, "<head", 1, true)
        or string.find(head, "<body", 1, true)
        or string.find(head, "<meta", 1, true)
        or string.find(head, "<title", 1, true)
        or string.find(head, "<div", 1, true)
        or string.find(head, "<section", 1, true)
        or string.find(head, "<article", 1, true) then
        return true
    end
    if string.find(head, "^%s*<") and string.find(head, "html", 1, true) then
        return true
    end
    return false
end

local function body_looks_like_json(body)
    if type(body) ~= "string" or body == "" then
        return false
    end
    local _, e = string.find(body, "^%s*")
    local c = string.byte(body, (e or 0) + 1)
    return c == 123 or c == 91
end

-- 缓存里常为 gzip 正文 + 错误的 octet-stream；用 BTwaf Public.ungzipbit（无 iconv）解压后再嗅探/回源
local function cache_gunzip_if_gzip(body)
    if type(body) ~= "string" or #body < 3 then
        return body
    end
    local b1, b2 = string.byte(body, 1, 2)
    if b1 ~= 0x1f or b2 ~= 0x8b then
        return body
    end
    if _G.Public and type(_G.Public.ungzipbit) == "function" then
        local ok, out = pcall(_G.Public.ungzipbit, body)
        if ok and type(out) == "string" and #out > 0 and out ~= body then
            return out
        end
    end
    return body
end

local function request_looks_like_top_level_document()
    local h = ngx.req.get_headers()
    local dest = h["Sec-Fetch-Dest"] or h["sec-fetch-dest"]
    if dest == "document" then
        return true
    end
    local mode = h["Sec-Fetch-Mode"] or h["sec-fetch-mode"]
    if mode == "navigate" then
        return true
    end
    return false
end

-- 常见整页 URL（用于 octet-stream + 浏览器导航时兜底为 HTML，避免「变成下载」）
local function uri_typically_html_document()
    local uri = ngx.var.uri or ""
    if uri == "/" then
        return true
    end
    if string.find(uri, ".html", 1, true) or string.find(uri, ".htm", 1, true) then
        return true
    end
    if string.find(uri, ".php", 1, true) then
        return true
    end
    if string.find(uri, ".asp", 1, true) or string.find(uri, ".jsp", 1, true) then
        return true
    end
    return false
end

-- 从正文前部嗅探 HTML charset（GBK 等）；用于仅在需要把泛二进制改成 HTML 时
local function page_cache_html_content_type(body)
    if type(body) ~= "string" or body == "" then
        return "text/html; charset=utf-8"
    end
    local n = math.min(#body, 16384)
    local low = string.lower(string.sub(body, 1, n))
    local m = string.match(low, 'charset%s*=%s*["\']%s*([%a%d%._%-]+)%s*["\']')
    if not m then
        m = string.match(low, 'charset%s*=%s*([%a%d%._%-]+)')
    end
    if not m then
        m = string.match(low, '<meta%s+charset%s*=%s*["\']?([%a%d%._%-]+)["\']?')
    end
    if m and #m > 0 and #m < 48 then
        return "text/html; charset=" .. m
    end
    return "text/html; charset=utf-8"
end

local function merge_accept_for_cache_hit(data)
    local parts = {}
    if type(data.accept) == "string" and data.accept ~= "" then
        parts[#parts + 1] = data.accept
    end
    local h = ngx.req.get_headers()
    local cur = h["Accept"] or h["accept"]
    if type(cur) == "string" and cur ~= "" then
        parts[#parts + 1] = cur
    end
    return table.concat(parts, ",")
end

-- 仅在泛二进制时返回新 Content-Type；sniff_body 可为解压后的正文（与 data.content 可能不同）
local function infer_content_type_when_generic_binary(data, sniff_body)
    sniff_body = sniff_body or data.content
    local accept = string.lower(merge_accept_for_cache_hit(data))
    if string.find(accept, "text/html", 1, true) then
        if body_looks_like_html(sniff_body) then
            return page_cache_html_content_type(sniff_body)
        end
    end
    if string.find(accept, "application/json", 1, true) and body_looks_like_json(sniff_body) then
        return "application/json; charset=utf-8"
    end
    -- */* 常见于内嵌 WebView / 少数客户端
    if string.find(accept, "*/*", 1, true) and body_looks_like_html(sniff_body) then
        return page_cache_html_content_type(sniff_body)
    end
    if body_looks_like_html(sniff_body) then
        return page_cache_html_content_type(sniff_body)
    end
    if request_looks_like_top_level_document() and uri_typically_html_document() and body_looks_like_html(sniff_body) then
        return page_cache_html_content_type(sniff_body)
    end
    return nil
end

-- 返回实际应对浏览器输出的正文（gzip + octet-stream 时可能改为解压后的字符串）
local function repair_generic_content_type_and_body(data)
    local raw = data.content
    local sniff = cache_gunzip_if_gzip(raw)
    local ct = header_value_string(ngx.header["Content-Type"])
    if not content_type_is_generic_binary(ct) then
        return raw
    end
    local fixed = infer_content_type_when_generic_binary(data, sniff)
    -- .html 等文档 URL：泛二进制 + 解压后仍像网页但上面未命中时，再兜底（避免 ngx.header Content-Type 为 table 时曾漏判）
    if not fixed and uri_typically_html_document() and body_looks_like_html(sniff) then
        fixed = page_cache_html_content_type(sniff)
    end
    if not fixed then
        return raw
    end
    ngx.header["Content-Type"] = fixed
    if sniff ~= raw then
        return sniff
    end
    return raw
end

-- 写入 Redis 前：解压 gzip 正文、纠正误报的 octet-stream，避免 HIT 时无 Content-Encoding 却仍为压缩流
local function normalize_page_cache_payload_before_store(headers, whole)
    if type(headers) ~= "table" or type(whole) ~= "string" then
        return whole
    end
    local body = cache_gunzip_if_gzip(whole)
    local hk_ct = nil
    for k, _ in pairs(headers) do
        if string.lower(tostring(k)) == "content-type" then
            hk_ct = k
            break
        end
    end
    local ct_raw = hk_ct and headers[hk_ct] or nil
    if body ~= whole and body_looks_like_html(body) then
        if hk_ct then
            headers[hk_ct] = page_cache_html_content_type(body)
        else
            headers["Content-Type"] = page_cache_html_content_type(body)
        end
        return body
    end
    if uri_typically_html_document() and content_type_is_generic_binary(ct_raw) and body_looks_like_html(body) then
        if hk_ct then
            headers[hk_ct] = page_cache_html_content_type(body)
        else
            headers["Content-Type"] = page_cache_html_content_type(body)
        end
    end
    return body
end

local function cache_debug_enabled()
    if _G.Config and type(_G.Config) == "table" then
        if _G.Config.cache_debug == true then
            return true
        end
        if _G.Config.cache and type(_G.Config.cache) == "table" and _G.Config.cache.debug == true then
            return true
        end
    end
    return false
end

-- 命中/未命中/排队写入/异步 SET 等业务日志
-- 默认开启（ngx.WARN），在 error_log 为 warn 时仍可见；高流量可关闭：SHELLSTACK_CACHE_LOG=0
-- systemd 下需 Environment= 且 nginx 主配置 env SHELLSTACK_CACHE_LOG; 一并传入
-- 或在 config.json 解析后的 Config.cache_log = false（若运行时可读）
local function cache_ops_enabled()
    if _G.Config and type(_G.Config) == "table" and _G.Config.cache_log == false then
        return false
    end
    local v = os.getenv("SHELLSTACK_CACHE_LOG")
    if v == "0" or v == "off" or v == "no" then
        return false
    end
    -- 默认开启；仅 0/off/no 或 Config.cache_log=false 时关闭
    return true
end

local function cache_ops_level()
    local v = os.getenv("SHELLSTACK_CACHE_LOG") or ""
    if v == "info" or cache_debug_enabled() then
        return ngx.INFO
    end
    return ngx.WARN
end

local function key_trace(k)
    if not k then
        return ""
    end
    if #k <= 72 then
        return k
    end
    return string.sub(k, 1, 28) .. "..." .. string.sub(k, -16)
end

local function cache_headers_enabled()
    local v = os.getenv("SHELLSTACK_CACHE_HEADERS")
    if v == "0" or v == "off" or v == "no" then
        return false
    end
    return true
end

-- 状态：HIT | MISS | SKIP | OFF（仅写入 ctx；由 header_filter 落到响应头）
local function stash_shellstack_cache_state(state, reason, key)
    local fp = nil
    if key then
        -- 指纹展示：key 形如 "btwaf_cms_cache:" .. field（32 位 md5 hex）
        local m = string.match(key, ":([a-fA-F0-9]+)$")
        if m and #m >= 8 then
            fp = string.lower(string.sub(m, -8))
        end
    end
    ngx.ctx.shellstack_cache = {
        state = state,
        reason = reason,
        fingerprint = fp
    }
end

-- 由 /www/server/btwaf/header.lua 末尾钩子调用（install 脚本自动追加，见 btwaf_extend.sh）
local function apply_header_filter_headers()
    if not cache_headers_enabled() then
        return
    end
    local s = ngx.ctx.shellstack_cache
    if not s or not s.state then
        return
    end
    ngx.header["X-Shellstack-Cache"] = s.state
    if s.reason then
        ngx.header["X-Shellstack-Cache-Reason"] = s.reason
    end
    if s.fingerprint then
        ngx.header["X-Shellstack-Cache-Fingerprint"] = s.fingerprint
    end
end

local function cache_log(level, event, ...)
    local msg = table.concat({...}, "")
    -- 常规事件（hit/miss/set）仅在 debug 开启时记录，异常始终记录
    local is_error = (level == ngx.ERR or level == ngx.ALERT or level == ngx.CRIT)
    if not is_error and not cache_debug_enabled() then
        return
    end

    local line = "[cache][" .. tostring(event) .. "] " .. msg
    ngx.log(level or ngx.INFO, line)
    if _G.Public and type(_G.Public.logs) == "function" then
        pcall(_G.Public.logs, line)
    end
end

local function cache_log_op(event, ...)
    if not cache_ops_enabled() then
        return
    end
    local msg = table.concat({...}, "")
    local line = "[cache][" .. tostring(event) .. "] " .. msg
    local lev = cache_ops_level()
    ngx.log(lev, line)
    if _G.Public and type(_G.Public.logs) == "function" then
        pcall(_G.Public.logs, line)
    end
end

local function redis_available()
    if redis_ok and redis then
        return true
    end
    if not redis_missing_logged then
        redis_missing_logged = true
        cache_log(
            ngx.ERR,
            "redis_module_missing",
            "module 'resty.redis' not found; cache disabled"
        )
    end
    return false
end

-- access 阶段命中缓存用，避免每条请求打 ERR 日志
local function get_redis_client_quiet()
    if not redis_available() then
        return nil
    end
    local cfg = get_redis_config()
    local client = redis:new()
    client:set_timeout(1000)
    local ok, err = client:connect(cfg.host, cfg.port)
    if not ok then
        return nil
    end
    if cfg.db and cfg.db > 0 then
        local ok_db, err_db = client:select(cfg.db)
        if not ok_db then
            return nil
        end
    end
    return client
end

-- 获取 Redis 客户端
local function get_redis_client()
    if not redis_available() then
        return nil
    end
    local cfg = get_redis_config()
    local client = redis:new()
    client:set_timeout(1000) -- 1秒超时
    cache_log(ngx.INFO, "connect_try", cfg.host, ":", cfg.port)
    local ok, err = client:connect(cfg.host, cfg.port)
    if not ok then
        cache_log(ngx.ERR, "connect_fail", err or "", redis_endpoint_hint())
        return nil
    end
    if cfg.db and cfg.db > 0 then
        local ok_db, err_db = client:select(cfg.db)
        if not ok_db then
            cache_log(ngx.ERR, "select_db_fail", err_db or "")
            return nil
        end
    end
    cache_log(ngx.INFO, "connect_ok", "connected")
    return client
end

local function resolve_cache_site(explicit_site)
    if type(explicit_site) == "string" and explicit_site ~= "" then
        return explicit_site
    end
    if ngx and ngx.var then
        return cache_page_site()
    end
    return ""
end

-- Function to get cached content（与整页缓存共用 Hash + field；可选 explicit_site / explicit_ua）
local function get_cached_content(uri, query_string, explicit_site, explicit_ua)
    local client = get_redis_client()
    if not client then
        cache_log(ngx.ERR, "get_client_nil", "Redis client nil")
        return nil
    end
    local main_key = get_page_cache_hash_key()
    local field = cache_page_field_hex_for(resolve_cache_site(explicit_site), uri, query_string, explicit_ua)
    local trace = main_key .. "#" .. key_trace(CACHE_PREFIX .. field)
    local cached_data, err = client:hget(main_key, field)
    if not cached_data or cached_data == ngx.null then
        cache_log_op("get_miss", "key=", trace, err and (", err=" .. tostring(err)) or "")
        return nil
    end
    local ok, decoded = pcall(cjson.decode, cached_data)
    if not ok or type(decoded) ~= "table" then
        cache_log_op("get_miss", "key=", trace, ", err=decode_fail")
        return nil
    end
    if cache_payload_expired(decoded) then
        cache_log_op("get_miss", "key=", trace, ", err=expired")
        return nil
    end
    cache_log_op("get_hit", "key=", trace, ", payload_bytes=", tostring(#cached_data))
    return decoded
end

-- Function to set cache content
local function set_cached_content(uri, query_string, content, ttl, explicit_site, explicit_ua)
    local client = get_redis_client()
    if not client then
        cache_log(ngx.ERR, "set_client_nil", "Redis client nil")
        return
    end
    ttl = ttl or DEFAULT_TTL
    if type(content) ~= "table" then
        cache_log(ngx.ERR, "set_fail", "content must be a table")
        return
    end
    local main_key = get_page_cache_hash_key()
    local field = cache_page_field_hex_for(resolve_cache_site(explicit_site), uri, query_string, explicit_ua)
    local trace = main_key .. "#" .. key_trace(CACHE_PREFIX .. field)
    local payload_tbl = {}
    for k, v in pairs(content) do
        payload_tbl[k] = v
    end
    payload_tbl.expires_at = ngx.time() + ttl
    local data = cjson.encode(payload_tbl)
    cache_log_op("set_try", "key=", trace, " ttl=", tostring(ttl), " payload_bytes=", tostring(#data))
    local ok, err = client:hset(main_key, field, data)
    if ok then
        cache_log_op("set_ok", "key=", trace, " ttl=", tostring(ttl))
    else
        cache_log(ngx.ERR, "set_fail", trace, " err=", err or "")
    end
end

-- Function to delete cache（仅删除当前 UA 分桶；要清整站用 clear_all_cache）
local function delete_cache(uri, query_string, explicit_site, explicit_ua)
    local client = get_redis_client()
    if not client then return end
    local main_key = get_page_cache_hash_key()
    local field = cache_page_field_hex_for(resolve_cache_site(explicit_site), uri, query_string, explicit_ua)
    client:hdel(main_key, field)
end

-- Function to clear all cache（主 Hash + btwaf_cms_cache:* 遗留 string 键；另清 php_cache:* 便于从旧版迁移）
local function clear_all_cache()
    local client = get_redis_client()
    if not client then return end
    client:del(get_page_cache_hash_key())
    local keys, err = client:keys(CACHE_PREFIX .. "*")
    if keys and type(keys) == "table" then
        for _, key in ipairs(keys) do
            client:del(key)
        end
    end
    local legacy, _ = client:keys("php_cache:*")
    if legacy and type(legacy) == "table" then
        for _, key in ipairs(legacy) do
            client:del(key)
        end
    end
end

local function page_cache_trace_key(field_hex)
    return get_page_cache_hash_key() .. "#" .. key_trace(CACHE_PREFIX .. field_hex)
end

local function async_redis_hset_page(premature, main_key, field, value)
    if premature then return end
    if not redis_available() then return end
    local cfg = get_redis_config()
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(cfg.host, cfg.port)
    if not ok then
        cache_log_redis_connect_err("async_connect_fail", err or "connect failed")
        return
    end
    if cfg.db and cfg.db > 0 then
        red:select(cfg.db)
    end
    local ok1, err_set = red:hset(main_key, field, value)
    if not ok1 then
        cache_log(ngx.ERR, "async_set_fail", "key=", page_cache_trace_key(field), " err=", err_set or "")
        return
    end
    red:set_keepalive(10000, 10)
    cache_log_op("async_set_ok", "key=", page_cache_trace_key(field), " payload_bytes=", tostring(#value))
end

-- 供 body_filter 在拼装完整响应体后异步写入 Redis（GET 200、非白名单）
-- access 阶段：与 schedule_body_page_cache 使用同一 Redis 键；命中则 ngx.exit(200)，未命中返回（继续 WAF）
local function try_access_cache_hit()
    if os.getenv("SHELLSTACK_CACHE_TRACE") == "1" then
        ngx.log(ngx.NOTICE, "[shellstack-cache] access_try ", ngx.var.request_method or "", " ", ngx.var.request_uri or "")
    end
    if ngx.req.get_method() ~= "GET" then
        stash_shellstack_cache_state("SKIP", "method_not_get", nil)
        return
    end
    local sk = ngx.var.skip_cache
    if sk == "1" or sk == "true" or sk == 1 then
        stash_shellstack_cache_state("SKIP", "skip_cache_var", nil)
        return
    end
    if not redis_available() then
        stash_shellstack_cache_state("OFF", "redis_module_unavailable", nil)
        return
    end
    ensure_ctx_server_name_for_cache()
    local client = get_redis_client_quiet()
    if not client then
        stash_shellstack_cache_state("OFF", "redis_connect_or_db_failed", nil)
        return
    end
    local main_key = get_page_cache_hash_key()
    local field = cache_page_field_hex()
    local trace = page_cache_trace_key(field)
    local raw, err = client:hget(main_key, field)
    client:set_keepalive(10000, 10)
    if not raw or raw == ngx.null then
        stash_shellstack_cache_state("MISS", "redis_key_miss", CACHE_PREFIX .. field)
        cache_log_op("access_miss", "key=", trace, err and (", err=" .. tostring(err)) or "")
        return
    end
    local ok, data = pcall(cjson.decode, raw)
    if not ok or type(data) ~= "table" or type(data.content) ~= "string" then
        stash_shellstack_cache_state("MISS", "corrupt_cache_entry", CACHE_PREFIX .. field)
        cache_log(ngx.ERR, "access_decode_fail", trace)
        return
    end
    if cache_payload_expired(data) then
        stash_shellstack_cache_state("MISS", "cache_entry_expired", CACHE_PREFIX .. field)
        cache_log_op("access_miss", "key=", trace, ", err=expired")
        return
    end
    if data.headers and type(data.headers) == "table" then
        for hk, hv in pairs(data.headers) do
            if type(hv) == "string" and not page_cache_header_should_skip(hk) then
                ngx.header[hk] = hv
            end
        end
    end
    local body_out = repair_generic_content_type_and_body(data)
    ngx.header["Content-Length"] = tostring(#body_out)
    stash_shellstack_cache_state("HIT", "served_from_redis", CACHE_PREFIX .. field)
    cache_log_op("access_hit", "key=", trace, " body_bytes=", tostring(#body_out))
    ngx.print(body_out)
    ngx.exit(ngx.HTTP_OK)
end

local function schedule_body_page_cache(ttl, whole)
    ttl = ttl or DEFAULT_TTL
    if ngx.req.get_method() ~= "GET" then return end
    if ngx.status ~= 200 then return end
    if ngx.ctx.white_rule then return end
    local headers = {}
    for k, v in pairs(ngx.header) do
        if not page_cache_header_should_skip(k) then
            if type(v) == "string" then
                headers[k] = v
            elseif type(v) == "table" then
                if v[1] and type(v[1]) == "string" then
                    headers[k] = v[1]
                end
            end
        end
    end
    ensure_ctx_server_name_for_cache()
    local hreq = ngx.req.get_headers()
    local main_key = get_page_cache_hash_key()
    local field = cache_page_field_hex()
    local trace = page_cache_trace_key(field)
    whole = normalize_page_cache_payload_before_store(headers, whole)
    local payload = cjson.encode({
        content = whole,
        headers = headers,
        url = ngx.var.uri,
        args = ngx.var.args,
        site = cache_page_site(),
        user_agent = hreq["user-agent"] or hreq["User-Agent"],
        accept = hreq["Accept"] or hreq["accept"],
        expires_at = ngx.time() + ttl
    })
    local ok, err = ngx.timer.at(0, async_redis_hset_page, main_key, field, payload)
    if not ok then
        cache_log(ngx.ERR, "timer_fail", err or "")
    else
        cache_log_op("body_timer_queued", "key=", trace, " ttl=", tostring(ttl), " payload_bytes=", tostring(#payload))
    end
end

-- Export functions
return {
    get_cached_content = get_cached_content,
    set_cached_content = set_cached_content,
    delete_cache = delete_cache,
    clear_all_cache = clear_all_cache,
    schedule_body_page_cache = schedule_body_page_cache,
    try_access_cache_hit = try_access_cache_hit,
    apply_header_filter_headers = apply_header_filter_headers
}
