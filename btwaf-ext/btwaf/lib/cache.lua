-- 说明：未 require 官方 logs.lua（该文件是 Logs.start() 的入口脚本，不是通用日志 API）。
-- 缓存相关行若调用 Public.logs，与 BTwaf 一致，写入 /www/wwwlogs/btwaf_debug.log；
-- ngx.log 写入 Nginx 的 error_log（站点 error.log 或主配置里的 error_log，取决于上下文）。
--
-- 响应头：access 阶段设置 X-Shellstack-Cache / Reason / Fingerprint，便于辨别工作状态。
-- Nginx 中 header_filter 早于 body_filter，无法在「本响应」里用头标明「是否已成功写入 Redis」；
-- 写入是否成功：首请求多为 MISS，再次 GET 若变为 HIT 即链路正常。
-- 关闭响应头：SHELLSTACK_CACHE_HEADERS=0
local redis_ok, redis = pcall(require, "resty.redis")
local cjson = require "cjson"

-- Redis configuration
local redis_config = {
    host = "127.0.0.1",
    port = 6379,
    db = 0
}

-- Cache configuration
local CACHE_PREFIX = "php_cache:"
local DEFAULT_TTL = 180 -- 3 minutes in seconds
local redis_missing_logged = false

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

-- 状态：HIT | MISS | SKIP | OFF（模块/连接不可用）
local function set_shellstack_cache_headers(state, reason, key)
    if not cache_headers_enabled() then
        return
    end
    if state then
        ngx.header["X-Shellstack-Cache"] = state
    end
    if reason then
        ngx.header["X-Shellstack-Cache-Reason"] = reason
    end
    if key then
        local fp = string.match(key, "^php_cache:([a-fA-F0-9]+)$")
        if fp and #fp >= 8 then
            ngx.header["X-Shellstack-Cache-Fingerprint"] = string.lower(string.sub(fp, -8))
        end
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
    local client = redis:new()
    client:set_timeout(1000)
    local ok, err = client:connect(redis_config.host, redis_config.port)
    if not ok then
        return nil
    end
    if redis_config.db and redis_config.db > 0 then
        local ok_db, err_db = client:select(redis_config.db)
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
    local client = redis:new()
    client:set_timeout(1000) -- 1秒超时
    cache_log(ngx.INFO, "connect_try", redis_config.host, ":", redis_config.port)
    local ok, err = client:connect(redis_config.host, redis_config.port)
    if not ok then
        cache_log(ngx.ERR, "connect_fail", err or "")
        return nil
    end
    if redis_config.db and redis_config.db > 0 then
        local ok_db, err_db = client:select(redis_config.db)
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
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(redis_config.host, redis_config.port)
    if not ok then
        cache_log(ngx.ERR, "async_connect_fail", err or "")
        return
    end
    if redis_config.db and redis_config.db > 0 then
        red:select(redis_config.db)
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
    if ngx.req.get_method() ~= "GET" then
        set_shellstack_cache_headers("SKIP", "method_not_get", nil)
        return
    end
    local sk = ngx.var.skip_cache
    if sk == "1" or sk == "true" or sk == 1 then
        set_shellstack_cache_headers("SKIP", "skip_cache_var", nil)
        return
    end
    if not redis_available() then
        set_shellstack_cache_headers("OFF", "redis_module_unavailable", nil)
        return
    end
    local client = get_redis_client_quiet()
    if not client then
        set_shellstack_cache_headers("OFF", "redis_connect_or_db_failed", nil)
        return
    end
    local key = body_fingerprint_key()
    local raw, err = client:get(key)
    client:set_keepalive(10000, 10)
    if not raw or raw == ngx.null then
        set_shellstack_cache_headers("MISS", "redis_key_miss", key)
        cache_log_op("access_miss", "key=", key_trace(key), err and (", err=" .. tostring(err)) or "")
        return
    end
    local ok, data = pcall(cjson.decode, raw)
    if not ok or type(data) ~= "table" or type(data.content) ~= "string" then
        set_shellstack_cache_headers("MISS", "corrupt_cache_entry", key)
        cache_log(ngx.ERR, "access_decode_fail", key)
        return
    end
    if data.headers and type(data.headers) == "table" then
        for hk, hv in pairs(data.headers) do
            if type(hv) == "string" then
                local hkl = string.lower(tostring(hk))
                if hkl ~= "transfer-encoding" and hkl ~= "content-length" then
                    ngx.header[hk] = hv
                end
            end
        end
    end
    set_shellstack_cache_headers("HIT", "served_from_redis", key)
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
        headers[k] = v
    end
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
    try_access_cache_hit = try_access_cache_hit
}
