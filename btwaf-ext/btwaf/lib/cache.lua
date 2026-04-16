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

-- Cache configuration（只改本段即可；无需为 key/TTL/签名设环境变量）
-- Redis **STRING**：key = CACHE_KEY_PREFIX .. md5(签名串)，过期 = SETEX(..., PAGE_CACHE_TTL_SECONDS, ...)
-- PAGE_CACHE_SIGN_COMPONENTS：参与 md5 的段，按顺序用 | 拼接。可选：
--   "site"|"server"|"domain"|"domain_server" → cache_page_site()
--   "uri" → ngx.var.uri
--   "args"|"query" → ngx.var.args
--   "ua"|"user_agent" → 与官方 waf 一致（无则 btwaf_null）；不需要 UA 分桶时从表中删掉 "ua" 即可
--   "referer"|"referrer" → ngx.var.http_referer（无则空串）
--   "headers" 或 "headers:all"|"headers:*" → 全部请求头（名小写、名字典序，多值逗号拼接）
--   "headers:cookie,accept-language" → 仅列出头（名小写后字典序；缺省头按空值参与签名）
local CACHE_KEY_PREFIX = "btwaf_cms_cache:"
local PAGE_CACHE_TTL_SECONDS = 180
local PAGE_CACHE_SIGN_COMPONENTS = { "site", "uri", "args" }
-- 无扩展名 URL 在误标 application/octet-stream 时按「网页」做路径兜底（子串匹配 ngx.var.uri，plain find）。
-- 后台改目录后在此增删即可，无需改业务逻辑；设为空表 {} 则仅依赖 .php/.html 等内置规则。
-- 默认含 "/e/" 兼容常见帝国 CMS 伪静态；若站点不用可删掉或换成实际前缀（如 "/yourapp/extend/"）。
local PAGE_CACHE_HTML_PATH_HINTS = { "/e/" }

local redis_missing_logged = false

-- 任一项为 headers:* 时才会 ngx.req.get_headers()（略省开销）
local sign_config_uses_headers = false

local function trim_str(s)
    if type(s) ~= "string" then
        return ""
    end
    return (string.match(s, "^%s*(.-)%s*$")) or s
end

-- 返回 nil，或 { kind = "all" }，或 { kind = "keys", keys = { "cookie", ... } }（已小写、已排序）
local function component_header_spec(comp)
    local s = trim_str(tostring(comp or ""))
    local slow = string.lower(s)
    if slow == "headers" then
        return { kind = "all" }
    end
    if string.sub(slow, 1, 8) ~= "headers:" then
        return nil
    end
    local rest = trim_str(string.sub(s, 9))
    local rlow = string.lower(rest)
    if rest == "" or rlow == "all" or rlow == "*" then
        return { kind = "all" }
    end
    local keys = {}
    for part in string.gmatch(rest, "[^,]+") do
        local p = trim_str(part)
        if p ~= "" then
            keys[#keys + 1] = string.lower(p)
        end
    end
    if #keys == 0 then
        return { kind = "all" }
    end
    table.sort(keys)
    return { kind = "keys", keys = keys }
end

for _, comp in ipairs(PAGE_CACHE_SIGN_COMPONENTS) do
    if component_header_spec(comp) then
        sign_config_uses_headers = true
        break
    end
end

local function header_value_string_for_sign(v)
    if v == nil then
        return ""
    end
    if type(v) == "string" then
        return v
    end
    if type(v) == "table" then
        local out = {}
        for i = 1, #v do
            out[#out + 1] = tostring(v[i])
        end
        return table.concat(out, ", ")
    end
    return tostring(v)
end

local function headers_tbl_lookup(headers_tbl, canon_name)
    if type(headers_tbl) ~= "table" then
        return nil
    end
    local v = headers_tbl[canon_name]
    if v ~= nil then
        return v
    end
    for hk, hv in pairs(headers_tbl) do
        if string.lower(tostring(hk)) == canon_name then
            return hv
        end
    end
    return nil
end

local function headers_sign_segment(headers_tbl, spec)
    if spec.kind == "all" then
        if type(headers_tbl) ~= "table" then
            return ""
        end
        local names = {}
        for k, _ in pairs(headers_tbl) do
            names[#names + 1] = string.lower(tostring(k))
        end
        table.sort(names)
        local lines = {}
        for _, name in ipairs(names) do
            local v = headers_tbl_lookup(headers_tbl, name)
            lines[#lines + 1] = name .. ":" .. header_value_string_for_sign(v)
        end
        return table.concat(lines, "\n")
    end
    -- keys
    local lines = {}
    for _, name in ipairs(spec.keys) do
        local v = headers_tbl_lookup(headers_tbl, name)
        lines[#lines + 1] = name .. ":" .. header_value_string_for_sign(v)
    end
    return table.concat(lines, "\n")
end

-- ctx: { site, uri, args, ua, referer, headers }
local function sign_component_value(comp, ctx)
    local c = string.lower(tostring(comp))
    if c == "site" or c == "server" or c == "domain" or c == "domain_server" then
        return ctx.site or ""
    end
    if c == "uri" then
        return ctx.uri or ""
    end
    if c == "args" or c == "query" then
        return ctx.args or ""
    end
    if c == "ua" or c == "user_agent" then
        return ctx.ua or "btwaf_null"
    end
    if c == "referer" or c == "referrer" then
        return ctx.referer or ""
    end
    return ""
end

local function cache_field_signing_string_from_ctx(ctx)
    local parts = {}
    for _, comp in ipairs(PAGE_CACHE_SIGN_COMPONENTS) do
        local hspec = component_header_spec(comp)
        if hspec then
            parts[#parts + 1] = headers_sign_segment(ctx.headers, hspec)
        else
            parts[#parts + 1] = sign_component_value(comp, ctx)
        end
    end
    return table.concat(parts, "|")
end

local function page_cache_redis_key(field_hex)
    return CACHE_KEY_PREFIX .. field_hex
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

local function capture_headers_for_sign()
    if not sign_config_uses_headers then
        return nil
    end
    if ngx and ngx.req and type(ngx.req.get_headers) == "function" then
        local ok, h = pcall(ngx.req.get_headers)
        if ok and type(h) == "table" then
            return h
        end
    end
    return {}
end

local function cache_page_field_hex()
    local ctx = {
        site = cache_page_site(),
        uri = ngx.var.uri or "",
        args = ngx.var.args or "",
        ua = cache_page_user_agent(),
        referer = ngx.var.http_referer or "",
        headers = capture_headers_for_sign(),
    }
    return ngx.md5(cache_field_signing_string_from_ctx(ctx))
end

-- 供 delete/get/set_cached_content。无 ngx 时：签名含 ua / referer / headers 须传对应显式参数（见下方 opts）
local function cache_page_field_hex_for(site, uri, args, explicit_ua, opts)
    opts = opts or {}
    local ua_tok = explicit_ua
    if ua_tok == nil and ngx and ngx.var then
        ua_tok = cache_page_user_agent()
    elseif ua_tok == nil then
        ua_tok = "btwaf_null"
    end
    local ref = opts.referer
    if ref == nil and ngx and ngx.var then
        ref = ngx.var.http_referer or ""
    elseif ref == nil then
        ref = ""
    end
    local hdrs = opts.headers
    if hdrs == nil and sign_config_uses_headers then
        hdrs = capture_headers_for_sign()
    end
    local ctx = {
        site = site or "",
        uri = uri or "",
        args = args or "",
        ua = ua_tok,
        referer = ref,
        headers = hdrs,
    }
    return ngx.md5(cache_field_signing_string_from_ctx(ctx))
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

-- 与 Public.ungzipbit 相同算法；access 阶段早于部分模块加载时 Public 可能不可用
local function cache_gunzip_via_ffi_zlib(body)
    local ok_mod, zlib = pcall(require, "ffi-zlib")
    if not ok_mod or not zlib or type(zlib.inflateGzip) ~= "function" then
        return nil
    end
    local output_table = {}
    local output = function(data)
        table.insert(output_table, data)
    end
    local count = 0
    local input = function(bufsize)
        local start = count > 0 and bufsize * count or 1
        local finish = (bufsize * (count + 1)) - 1
        count = count + 1
        if bufsize == 1 then
            start = count
            finish = count
        end
        return body:sub(start, finish)
    end
    local ok_i, _err = zlib.inflateGzip(input, output, 15 + 32)
    if not ok_i then
        return nil
    end
    local out = table.concat(output_table, "")
    if type(out) == "string" and #out > 0 and out ~= body then
        return out
    end
    return nil
end

-- 缓存里常为 gzip 正文 + 错误的 octet-stream；Public.ungzipbit → ffi-zlib
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
    local out2 = cache_gunzip_via_ffi_zlib(body)
    if out2 then
        return out2
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
local function uri_matches_html_path_hints(uri)
    if type(uri) ~= "string" or uri == "" then
        return false
    end
    for _, hint in ipairs(PAGE_CACHE_HTML_PATH_HINTS) do
        if type(hint) == "string" and hint ~= "" and string.find(uri, hint, 1, true) then
            return true
        end
    end
    return false
end

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
    if uri_matches_html_path_hints(uri) then
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
    -- 空正文无法嗅探标签；路径已表明是常见 CMS/PHP 路由时，勿让 octet-stream 触发「下载」
    if type(sniff_body) == "string" and #sniff_body == 0 and uri_typically_html_document() then
        return "text/html; charset=utf-8"
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
        -- .html 仍无法推断但正文已解压且明显含 HTML 标签（模板前部过长等）
        if uri_typically_html_document() and type(sniff) == "string" and #sniff > 100 then
            local win = string.lower(string.sub(sniff, 1, math.min(#sniff, 98304)))
            if string.find(win, "<html", 1, true) or string.find(win, "<!doctype", 1, true) then
                fixed = page_cache_html_content_type(sniff)
            end
        end
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
    if type(whole) == "string" and #whole == 0 and uri_typically_html_document() and content_type_is_generic_binary(ct_raw) then
        if hk_ct then
            headers[hk_ct] = "text/html; charset=utf-8"
        else
            headers["Content-Type"] = "text/html; charset=utf-8"
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
    -- Redis HIT 在 access 已设好 Content-Type/Length；header_filter 阶段可能被其它逻辑改回 octet-stream，此处强制恢复
    if s.state == "HIT" then
        if s.replay_content_type then
            ngx.header["Content-Type"] = s.replay_content_type
        end
        if s.replay_content_length then
            ngx.header["Content-Length"] = s.replay_content_length
        end
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

-- Function to get cached content（Redis STRING：key = page_cache_redis_key(md5)；可选 explicit_site / explicit_ua）
-- opts（可选）：{ referer = "...", headers = { ["cookie"] = "..." } }，与 PAGE_CACHE_SIGN_COMPONENTS 中含 referer / headers:* 时配合；无 ngx 时必须提供
local function get_cached_content(uri, query_string, explicit_site, explicit_ua, opts)
    local client = get_redis_client()
    if not client then
        cache_log(ngx.ERR, "get_client_nil", "Redis client nil")
        return nil
    end
    local field = cache_page_field_hex_for(resolve_cache_site(explicit_site), uri, query_string, explicit_ua, opts)
    local redis_key = page_cache_redis_key(field)
    local trace = key_trace(redis_key)
    local cached_data, err = client:get(redis_key)
    if not cached_data or cached_data == ngx.null then
        cache_log_op("get_miss", "key=", trace, err and (", err=" .. tostring(err)) or "")
        return nil
    end
    local ok, decoded = pcall(cjson.decode, cached_data)
    if not ok or type(decoded) ~= "table" then
        cache_log_op("get_miss", "key=", trace, ", err=decode_fail")
        return nil
    end
    cache_log_op("get_hit", "key=", trace, ", payload_bytes=", tostring(#cached_data))
    return decoded
end

-- Function to set cache content
local function set_cached_content(uri, query_string, content, ttl, explicit_site, explicit_ua, opts)
    local client = get_redis_client()
    if not client then
        cache_log(ngx.ERR, "set_client_nil", "Redis client nil")
        return
    end
    ttl = tonumber(ttl) or PAGE_CACHE_TTL_SECONDS
    if ttl < 1 then
        ttl = PAGE_CACHE_TTL_SECONDS
    end
    if type(content) ~= "table" then
        cache_log(ngx.ERR, "set_fail", "content must be a table")
        return
    end
    local field = cache_page_field_hex_for(resolve_cache_site(explicit_site), uri, query_string, explicit_ua, opts)
    local redis_key = page_cache_redis_key(field)
    local trace = key_trace(redis_key)
    local payload_tbl = {}
    for k, v in pairs(content) do
        payload_tbl[k] = v
    end
    local data = cjson.encode(payload_tbl)
    cache_log_op("set_try", "key=", trace, " ttl=", tostring(ttl), " payload_bytes=", tostring(#data))
    local ok, err = client:setex(redis_key, ttl, data)
    if ok then
        cache_log_op("set_ok", "key=", trace, " ttl=", tostring(ttl))
    else
        cache_log(ngx.ERR, "set_fail", trace, " err=", err or "")
    end
end

-- Function to delete cache（当前签名对应的一条 STRING；整库清理由 clear_all_cache）
local function delete_cache(uri, query_string, explicit_site, explicit_ua, opts)
    local client = get_redis_client()
    if not client then return end
    local field = cache_page_field_hex_for(resolve_cache_site(explicit_site), uri, query_string, explicit_ua, opts)
    client:del(page_cache_redis_key(field))
end

-- Function to clear all cache（btwaf_cms_cache:*；另清旧版整页 Hash 键 btwaf_cms_cache 与 php_cache:*）
local function clear_all_cache()
    local client = get_redis_client()
    if not client then return end
    client:del("btwaf_cms_cache")
    local keys, err = client:keys(CACHE_KEY_PREFIX .. "*")
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
    return key_trace(page_cache_redis_key(field_hex))
end

local function async_redis_setex_page(premature, redis_key, ttl_sec, value)
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
    local ttl = tonumber(ttl_sec) or PAGE_CACHE_TTL_SECONDS
    if ttl < 1 then
        ttl = PAGE_CACHE_TTL_SECONDS
    end
    local ok1, err_set = red:setex(redis_key, ttl, value)
    if not ok1 then
        cache_log(ngx.ERR, "async_set_fail", "key=", key_trace(redis_key), " err=", err_set or "")
        return
    end
    red:set_keepalive(10000, 10)
    cache_log_op("async_set_ok", "key=", key_trace(redis_key), " payload_bytes=", tostring(#value))
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
    local field = cache_page_field_hex()
    local redis_key = page_cache_redis_key(field)
    local trace = page_cache_trace_key(field)
    local raw, err = client:get(redis_key)
    client:set_keepalive(10000, 10)
    if not raw or raw == ngx.null then
        stash_shellstack_cache_state("MISS", "redis_key_miss", redis_key)
        cache_log_op("access_miss", "key=", trace, err and (", err=" .. tostring(err)) or "")
        return
    end
    local ok, data = pcall(cjson.decode, raw)
    if not ok or type(data) ~= "table" or type(data.content) ~= "string" then
        stash_shellstack_cache_state("MISS", "corrupt_cache_entry", redis_key)
        cache_log(ngx.ERR, "access_decode_fail", trace)
        return
    end
    if data.headers and type(data.headers) == "table" then
        for hk, hv in pairs(data.headers) do
            if type(hv) == "string" and not page_cache_header_should_skip(hk) then
                -- 误存的 application/octet-stream 先不写进 ngx.header，交给 repair 按解压后正文重写（否则下游可能锁死为下载）
                if string.lower(tostring(hk)) == "content-type" and content_type_is_generic_binary(hv) then
                    -- skip
                else
                    ngx.header[hk] = hv
                end
            end
        end
    end
    local body_out = repair_generic_content_type_and_body(data)
    ngx.header["Content-Length"] = tostring(#body_out)
    stash_shellstack_cache_state("HIT", "served_from_redis", redis_key)
    ngx.ctx.shellstack_cache.replay_content_type = ngx.header["Content-Type"]
    ngx.ctx.shellstack_cache.replay_content_length = ngx.header["Content-Length"]
    cache_log_op("access_hit", "key=", trace, " body_bytes=", tostring(#body_out))
    ngx.print(body_out)
    ngx.exit(ngx.HTTP_OK)
end

local function schedule_body_page_cache(ttl, whole)
    ttl = tonumber(ttl) or PAGE_CACHE_TTL_SECONDS
    if ttl < 1 then
        ttl = PAGE_CACHE_TTL_SECONDS
    end
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
    local field = cache_page_field_hex()
    local redis_key = page_cache_redis_key(field)
    local trace = page_cache_trace_key(field)
    whole = normalize_page_cache_payload_before_store(headers, whole)
    local payload = cjson.encode({
        content = whole,
        headers = headers,
        url = ngx.var.uri,
        args = ngx.var.args,
        site = cache_page_site(),
        user_agent = hreq["user-agent"] or hreq["User-Agent"],
        accept = hreq["Accept"] or hreq["accept"]
    })
    local ok, err = ngx.timer.at(0, async_redis_setex_page, redis_key, ttl, payload)
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
