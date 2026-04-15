return {
    redis = {
        host = "127.0.0.1",
        port = 6379,
        db = 0,
        password = nil,  -- Set your Redis password here if needed
        timeout = 1000   -- Connection timeout in milliseconds
    },
    cache = {
        prefix = "btwaf_cms_cache:",
        default_ttl = 120,  -- Default cache time in seconds
        max_ttl = 86400      -- Maximum cache time in seconds (24 hours)
    }
} 
