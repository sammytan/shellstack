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
local CACHE_PREFIX = "php_cache:"
local DEFAULT_TTL = 180 -- 3 minutes in seconds
local redis_missing_logged = false

-- body_filter 里 whole 多为已解压正文，但 ngx.header 可能仍带 gzip / attachment，命中时若照搬会导致浏览器乱码或「变成下载」
local PAGE_CACHE_HEADER_SKIP = {
    ["transfer-encoding"] = true,
    ["content-length"] = true,
    ["content-encoding"] = true,
    ["content-disposition"] = true,
    ["connection"] = true,
    ["keep-alive"] = true,
    ["upgrade"] = true,
    ["trailer"] = true,
    ["content-md5"] = true,
}

local function page_cache_header_should_skip(name)
    local k = string.lower(tostring(name or ""))
    return PAGE_CACHE_HEADER_SKIP[k] == true
end

-- 上游/代理有时把 HTML 标成 application/octet-stream，浏览器会当下载；页缓存只服务 HTML 场景，按正文纠正类型
local function body_looks_like_html(body)
    if type(body) ~= "string" or body == "" then
        return false
    end
    local start = 1
    if string.byte(body, 1) == 239 and string.byte(body, 2) == 187 and string.byte(body, 3) == 191 then
        start = 4
    end
    local max_end = math.min(#body, start + 2047)
    local head = string.lower(string.sub(body, start, max_end))
    if not string.find(head, "^%s*<", 1) then
        return false
    end
    if string.find(head, "<!doctype html", 1, true)
        or string.find(head, "<html", 1, true)
        or string.find(head, "<head", 1, true)
        or string.find(head, "<body", 1, true) then
        return true
    end
    return false
end

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
    return false
end

local function fix_page_cache_content_type_from_body(body)
    local ct = ngx.header["Content-Type"]
    if content_type_is_generic_binary(ct) and body_looks_like_html(body) then
        ngx.header["Content-Type"] = "text/html; charset=utf-8"
    end
end

local function fix_stored_headers_content_type(headers, body)
    if type(headers) ~= "table" or type(body) ~= "string" then
        return
    end
    local ct_key, ct_val = nil, nil
    for k, v in pairs(headers) do
        if string.lower(tostring(k)) == "content-type" and type(v) == "string" then
            ct_key = k
            ct_val = v
            break
        end
    end
    if content_type_is_generic_binary(ct_val) and body_looks_like_html(body) then
        if ct_key then
            headers[ct_key] = "text/html; charset=utf-8"
        else
            headers["Content-Type"] = "text/html; charset=utf-8"
        end
    end
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
        local m = string.match(key, "^php_cache:([a-fA-F0-9]+)$")
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

-- Function to generate cache key
local function generate_cache_key(uri, query_string)
    local key = CACHE_PREFIX .. uri
    if query_string and query_string ~= "" then
        key = key .. "?" .. query_string
    end
    return key
end

-- Function to get cached content
local function get_cached_content(uri, query_string)
    local client = get_redis_client()
    if not client then
        cache_log(ngx.ERR, "get_client_nil", "Redis client nil")
        return nil
    end
    local key = generate_cache_key(uri, query_string)
    local cached_data, err = client:get(key)
    if not cached_data or cached_data == ngx.null then
        cache_log_op("get_miss", "key=", key_trace(key), err and (", err=" .. tostring(err)) or "")
        return nil
    end
    cache_log_op("get_hit", "key=", key_trace(key), ", payload_bytes=", tostring(#cached_data))
    return cjson.decode(cached_data)
end

-- Function to set cache content
local function set_cached_content(uri, query_string, content, ttl)
    local client = get_redis_client()
    if not client then
        cache_log(ngx.ERR, "set_client_nil", "Redis client nil")
        return
    end
    local key = generate_cache_key(uri, query_string)
    local data = cjson.encode(content)
    ttl = ttl or DEFAULT_TTL
    cache_log_op("set_try", "key=", key_trace(key), " ttl=", tostring(ttl), " payload_bytes=", tostring(#data))
    local ok, err = client:setex(key, ttl, data)
    if ok then
        cache_log_op("set_ok", "key=", key_trace(key), " ttl=", tostring(ttl))
    else
        cache_log(ngx.ERR, "set_fail", key, " err=", err or "")
    end
end

-- Function to delete cache
local function delete_cache(uri, query_string)
    local client = get_redis_client()
    if not client then return end
    local key = generate_cache_key(uri, query_string)
    client:del(key)
end

-- Function to clear all cache
local function clear_all_cache()
    local client = get_redis_client()
    if not client then return end
    local keys, err = client:keys(CACHE_PREFIX .. "*")
    if keys and type(keys) == "table" then
        for _, key in ipairs(keys) do
            client:del(key)
        end
    end
end

-- body_filter 阶段：与 URI+查询串键不同，按 UA/Accept-Encoding 区分变体（与 body.lua 原逻辑一致）
local function body_fingerprint_key()
    local uri = ngx.var.uri or ""
    local args = ngx.var.args or ""
    local ua = ngx.req.get_headers()["user-agent"] or ""
    local accept_encoding = ngx.req.get_headers()["accept-encoding"] or ""
    local raw = uri .. "|" .. args .. "|" .. ua .. "|" .. accept_encoding
    return CACHE_PREFIX .. ngx.md5(raw)
end

local function async_redis_setex(premature, key, ttl, value)
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
    local ok1, err_set = red:setex(key, ttl, value)
    if not ok1 then
        cache_log(ngx.ERR, "async_set_fail", "key=", key_trace(key), " err=", err_set or "")
        return
    end
    red:set_keepalive(10000, 10)
    cache_log_op("async_set_ok", "key=", key_trace(key), " ttl=", tostring(ttl), " payload_bytes=", tostring(#value))
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
    local client = get_redis_client_quiet()
    if not client then
        stash_shellstack_cache_state("OFF", "redis_connect_or_db_failed", nil)
        return
    end
    local key = body_fingerprint_key()
    local raw, err = client:get(key)
    client:set_keepalive(10000, 10)
    if not raw or raw == ngx.null then
        stash_shellstack_cache_state("MISS", "redis_key_miss", key)
        cache_log_op("access_miss", "key=", key_trace(key), err and (", err=" .. tostring(err)) or "")
        return
    end
    local ok, data = pcall(cjson.decode, raw)
    if not ok or type(data) ~= "table" or type(data.content) ~= "string" then
        stash_shellstack_cache_state("MISS", "corrupt_cache_entry", key)
        cache_log(ngx.ERR, "access_decode_fail", key)
        return
    end
    if data.headers and type(data.headers) == "table" then
        for hk, hv in pairs(data.headers) do
            if type(hv) == "string" and not page_cache_header_should_skip(hk) then
                ngx.header[hk] = hv
            end
        end
    end
    fix_page_cache_content_type_from_body(data.content)
    ngx.header["Content-Length"] = tostring(#data.content)
    stash_shellstack_cache_state("HIT", "served_from_redis", key)
    cache_log_op("access_hit", "key=", key_trace(key), " body_bytes=", tostring(#data.content))
    ngx.print(data.content)
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
    fix_stored_headers_content_type(headers, whole)
    local key = body_fingerprint_key()
    local payload = cjson.encode({
        content = whole,
        headers = headers,
        url = ngx.var.uri,
        args = ngx.var.args,
        user_agent = ngx.req.get_headers()["user-agent"]
    })
    local ok, err = ngx.timer.at(0, async_redis_setex, key, ttl, payload)
    if not ok then
        cache_log(ngx.ERR, "timer_fail", err or "")
    else
        cache_log_op("body_timer_queued", "key=", key_trace(key), " ttl=", tostring(ttl), " payload_bytes=", tostring(#payload))
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
