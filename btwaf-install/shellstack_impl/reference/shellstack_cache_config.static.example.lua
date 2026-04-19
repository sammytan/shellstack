-- 参考：btwaf-ext 原版「纯 Lua 表」配置（未使用面板 JSON 时可用）
-- 正式安装包以 lib/shellstack_cache_config.lua + shellstack_cache_config.json 为准（见 SHELLSTACK_CACHE_IMPL.md）
-- ShellStack 整页 Redis 缓存 tunables（单文件集中修改；cache.lua 会 require 本模块）
-- 连接默认值见下方 redis；可被环境变量覆盖：SHELLSTACK_REDIS_HOST / PORT / DB / PASSWORD / TIMEOUT（nginx 主配置须 env 声明）

return {
    redis = {
        host = "127.0.0.1",
        port = 6379,
        db = 0,
        password = nil, -- 需要时在面板或此处填写；也可用环境变量 SHELLSTACK_REDIS_PASSWORD
        timeout = 1000, -- 毫秒，连接/读写超时（resty.redis set_timeout）
    },

    -- Redis STRING 键前缀：key = key_prefix .. md5(签名串)
    key_prefix = "btwaf_cms_cache:",

    -- SETEX 过期秒数（body 阶段 schedule 默认亦用此值，可按站点再传参）
    page_ttl_seconds = 180,

    -- 上限（秒）；仅作文档/外部读取，cache.lua 当前未强制 clamp TTL
    max_ttl = 86400,

    -- 参与 md5 的段，按顺序用 | 拼接。可选：
    --   "site"|"server"|"domain"|"domain_server" → 站点名
    --   "uri" → ngx.var.uri
    --   "args"|"query" → ngx.var.args
    --   "ua"|"user_agent" → 与官方 waf 一致（无则 btwaf_null）
    --   "referer"|"referrer" → ngx.var.http_referer
    --   "headers" / "headers:all" / "headers:*" → 全部请求头
    --   "headers:cookie,accept-language" → 仅列出头
    sign_components = { "site", "uri", "args" },

    -- 无扩展名 URL 在误标 application/octet-stream 时按「网页」做路径兜底（子串匹配 uri）
    html_path_hints = { "/e/" },

    -- 整页缓存跳过的 URI 前缀（uri 必须以该项开头）
    uri_prefix_skip = { "/tjcss/", "/tjjs/" },

    -- 可选：按 URI 后缀跳过（与 uri 尾部逐字匹配，区分大小写）。常见静态资源可不缓存。
    uri_suffix_skip = { ".js" },

    -- 是否与 Nginx $skip_cache 联动（FastCGI 缓存）；false 时与 Redis 解耦
    honor_nginx_skip_cache = false,

    -- 写回客户端时跳过的响应头名（小写）
    response_header_skip = {
        "transfer-encoding",
        "content-length",
        "content-encoding",
        "content-disposition",
        "connection",
        "keep-alive",
        "proxy-connection",
        "upgrade",
        "trailer",
        "content-md5",
    },

    -- clear_all_cache 时额外删除的旧版整页 Hash 键名
    legacy_hash_key = "btwaf_cms_cache",
}
