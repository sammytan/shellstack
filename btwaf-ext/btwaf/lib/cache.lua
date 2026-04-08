local redis = require "resty.redis"
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

-- 获取 Redis 客户端
local function get_redis_client()
    local client = redis:new()
    client:set_timeout(1000) -- 1秒超时
    ngx.log(ngx.ERR, "[cache] try connect redis: ", redis_config.host, ":", redis_config.port)
    local ok, err = client:connect(redis_config.host, redis_config.port)
    if not ok then
        ngx.log(ngx.ERR, "[cache] failed to connect to redis: ", err)
        return nil
    end
    if redis_config.db and redis_config.db > 0 then
        local ok_db, err_db = client:select(redis_config.db)
        if not ok_db then
            ngx.log(ngx.ERR, "[cache] failed to select redis db: ", err_db)
            return nil
        end
    end
    ngx.log(ngx.ERR, "[cache] connected to redis successfully")
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
        ngx.log(ngx.ERR, "[cache] Redis client nil in get_cached_content")
        return nil
    end
    local key = generate_cache_key(uri, query_string)
    local cached_data, err = client:get(key)
    if not cached_data or cached_data == ngx.null then
        ngx.log(ngx.INFO, "[cache] MISS: ", key)
        return nil
    end
    ngx.log(ngx.INFO, "[cache] HIT: ", key)
    return cjson.decode(cached_data)
end

-- Function to set cache content
local function set_cached_content(uri, query_string, content, ttl)
    local client = get_redis_client()
    if not client then
        ngx.log(ngx.ERR, "[cache] Redis client nil in set_cached_content")
        return
    end
    local key = generate_cache_key(uri, query_string)
    local data = cjson.encode(content)
    ttl = ttl or DEFAULT_TTL
    ngx.log(ngx.ERR, "[cache] TRY SET: ", key, " ttl=", ttl, " data=", data)
    local ok, err = client:setex(key, ttl, data)
    if ok then
        ngx.log(ngx.ERR, "[cache] SET: ", key, " ttl=", ttl)
    else
        ngx.log(ngx.ERR, "[cache] SET FAILED: ", key, " err=", err)
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

-- Export functions
return {
    get_cached_content = get_cached_content,
    set_cached_content = set_cached_content,
    delete_cache = delete_cache,
    clear_all_cache = clear_all_cache
} 
