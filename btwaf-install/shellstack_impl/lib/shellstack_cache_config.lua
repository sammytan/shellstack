--[[
  ---------------------------------------------------------------------------
  ShellStack 整页缓存 — 配置加载器（宝塔 WAF 官方安装包植入）
  ---------------------------------------------------------------------------
  面板侧持久化：/www/server/panel/plugin/btwaf/shellstack_cache_config.json
  由 btwaf_main.get_shellstack_cache_config / set_shellstack_cache_config 读写。
  维护与任务清单见仓库：SHELLSTACK_CACHE_IMPL.md
  ---------------------------------------------------------------------------
]]

local cjson = require "cjson.safe"

-- 与 Python _shellstack_cache_defaults / shellstack_cache_config.json 保持一致
local CFG_PATH = "/www/server/panel/plugin/btwaf/shellstack_cache_config.json"

local function deep_merge_redis(base, ext)
    if type(ext) ~= "table" then
        return base
    end
    local o = {}
    for k, v in pairs(base) do
        o[k] = v
    end
    for k, v in pairs(ext) do
        o[k] = v
    end
    if o.password == "" then
        o.password = nil
    end
    return o
end

local function merge_lists(base, ext)
    if type(ext) == "table" then
        return ext
    end
    return base
end

local defaults = {
    redis = { host = "127.0.0.1", port = 6379, db = 0, password = nil, timeout = 1000 },
    key_prefix = "btwaf_cms_cache:",
    page_ttl_seconds = 180,
    max_ttl = 86400,
    sign_components = { "site", "uri", "args" },
    html_path_hints = { "/e/" },
    uri_prefix_skip = { "/tjcss/", "/tjjs/" },
    uri_suffix_skip = { ".js" },
    honor_nginx_skip_cache = false,
    response_header_skip = {
        "transfer-encoding", "content-length", "content-encoding", "content-disposition",
        "connection", "keep-alive", "proxy-connection", "upgrade", "trailer", "content-md5",
    },
    legacy_hash_key = "btwaf_cms_cache",
}

local function load_from_json()
    local f, err = io.open(CFG_PATH, "r")
    if not f then
        return nil
    end
    local raw = f:read("*a")
    f:close()
    local j = cjson.decode(raw)
    if type(j) ~= "table" then
        return nil
    end
    local out = {}
    out.redis = deep_merge_redis(defaults.redis, j.redis)
    out.key_prefix = type(j.key_prefix) == "string" and j.key_prefix or defaults.key_prefix
    out.page_ttl_seconds = tonumber(j.page_ttl_seconds) or defaults.page_ttl_seconds
    out.max_ttl = tonumber(j.max_ttl) or defaults.max_ttl
    out.sign_components = merge_lists(defaults.sign_components, j.sign_components)
    out.html_path_hints = merge_lists(defaults.html_path_hints, j.html_path_hints)
    out.uri_prefix_skip = merge_lists(defaults.uri_prefix_skip, j.uri_prefix_skip)
    out.uri_suffix_skip = merge_lists(defaults.uri_suffix_skip, j.uri_suffix_skip)
    out.honor_nginx_skip_cache = j.honor_nginx_skip_cache == true
    out.response_header_skip = merge_lists(defaults.response_header_skip, j.response_header_skip)
    out.legacy_hash_key = type(j.legacy_hash_key) == "string" and j.legacy_hash_key or defaults.legacy_hash_key
    return out
end

local merged = load_from_json()
if merged then
    return merged
end
return defaults
