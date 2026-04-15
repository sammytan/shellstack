--[[
    @name JDBC 反序列化漏洞识别模块
    @author lkq@bt.cn
    @time 2025-08-28
    @version 1.0
]]--
local jdbc = {}
jdbc.version = "1.0"

-- 定义已知的危险参数和类
jdbc.dangerous_params = {
    -- MySQL
    ["autoDeserialize"] = true,
    ["statementInterceptors"] = true,
    ["queryInterceptors"] = true,
    ["exceptionInterceptors"] = true,
    ["detectCustomCollations"] = true,
    
    -- PostgreSQL
    ["socketFactory"] = true,
    ["socketFactoryArg"] = true,
    ["sslfactory"] = true,
    ["sslfactoryarg"] = true,
    
    -- DB2
    ["clientRerouteServerListJNDIName"] = true,
    
    -- H2
    ["INIT"] = true,
    ["CUSTOM_DATA_TYPES_HANDLER"] = true,
    ["JMX"] = true,
    ["AUTHENTICATOR"] = true,
    ["CIPHER"] = true,
    
    -- Derby
    ["create"] = true,
    ["bootPassword"] = true,
    ["shutdown"] = true
}

-- 定义危险类名的部分匹配
jdbc.dangerous_classes = {
    "ClassPathXmlApplicationContext",
    "FileSystemXmlApplicationContext",
    "JdbcRowSetImpl",
    "JndiDataSourceFactory",
    "RmiDataSource",
    "ScriptEngineFactory",
    "ELProcessor",
    "TemplatesImpl",
    "ldap://",
    "rmi://",
    "http://",
    "https://",
    "ftp://",
    "file://"
}

function jdbc.table_length(t)
    local count = 0
    if t then
        for _ in pairs(t) do
            count = count + 1
        end
    end
    return count
end

-- 检查参数或值是否包含危险类
function jdbc.check_dangerous_content(value)
    if not value then return false, nil end
    
    for _, pattern in ipairs(jdbc.dangerous_classes) do
        if value:find(pattern, 1, true) then
            return true, pattern
        end
    end
    
    return false, nil
end

-- 解析 MySQL JDBC URL
function jdbc.parse_mysql_url(url, result)
    -- 格式: jdbc:mysql://host:port/database?param1=value1&param2=value2
    local m = ngx.re.match(url, "mysql://([^:/]+):?(\\d*)/?([^?]*)", "jo")
    local host, port, database = nil, nil, nil
    if m then
        host, port, database = m[1], m[2], m[3]
    end
    result.host = host or ""
    result.port = port and port ~= "" and port or "3306"
    result.database = database and database ~= "" and database or nil
    
    -- 解析参数
    local m_params = ngx.re.match(url, "\\?(.+)$", "jo")
    local params_str = m_params and m_params[1]
    if params_str then
        local iterator, err = ngx.re.gmatch(params_str, "([^=&]+)=([^&]*)", "jo")
        if not iterator then
            return result
        end
        
        local m
        local iteration_count = 0
        local max_iterations = 20  -- 设置最大迭代次数防止无限循环
        
        while true do
            iteration_count = iteration_count + 1
            if iteration_count > max_iterations then
                break
            end
            
            m, err = iterator()
            if not m then
                break
            end
            local param, value = m[1], m[2]
            result.params[param] = value
            
            -- 检查危险参数
            if jdbc.dangerous_params[param] then
                result.vulnerable = true
                table.insert(result.vulnerability_details, {
                    param = param,
                    value = value,
                    reason = "危险参数"
                })
            end
            
            -- 检查值是否包含危险类
            local is_dangerous, pattern = jdbc.check_dangerous_content(value)
            if is_dangerous then
                result.vulnerable = true
                table.insert(result.vulnerability_details, {
                    param = param,
                    value = value,
                    reason = "包含危险类或URL: " .. pattern
                })
            end
        end
    end
    
    return result
end

-- 解析 PostgreSQL JDBC URL
function jdbc.parse_postgresql_url(url, result)
    -- 格式: jdbc:postgresql://host:port/database?param1=value1&param2=value2
    local m = ngx.re.match(url, "postgresql://([^:/]+):?(\\d*)/?([^?]*)", "jo")
    local host, port, database = nil, nil, nil
    if m then
        host, port, database = m[1], m[2], m[3]
    end
    result.host = host or ""
    result.port = port and port ~= "" and port or "5432"
    result.database = database and database ~= "" and database or nil
    
    -- 解析参数
    local m_params = ngx.re.match(url, "\\?(.+)$", "jo")
    local params_str = m_params and m_params[1]
    if params_str then
        local iterator, err = ngx.re.gmatch(params_str, "([^=&]+)=([^&]*)", "jo")
        if not iterator then
            return result
        end
        
        local m
        local iteration_count = 0
        local max_iterations = 20  -- 设置最大迭代次数防止无限循环
        
        while true do
            iteration_count = iteration_count + 1
            if iteration_count > max_iterations then
                break
            end
            
            m, err = iterator()
            if not m then
                break
            end
            local param, value = m[1], m[2]
            result.params[param] = value
            
            -- 检查危险参数
            if jdbc.dangerous_params[param] then
                result.vulnerable = true
                table.insert(result.vulnerability_details, {
                    param = param,
                    value = value,
                    reason = "危险参数"
                })
            end
            
            -- 检查值是否包含危险类
            local is_dangerous, pattern = jdbc.check_dangerous_content(value)
            if is_dangerous then
                result.vulnerable = true
                table.insert(result.vulnerability_details, {
                    param = param,
                    value = value,
                    reason = "包含危险类或URL: " .. pattern
                })
            end
        end
    end
    
    return result
end

-- 解析 SQLite JDBC URL
function jdbc.parse_sqlite_url(url, result)
    -- 格式: jdbc:sqlite:path 或 jdbc:sqlite::resource:url
    local m = ngx.re.match(url, "jdbc:sqlite:(.+)", "jo")
    local path = m and m[1]
    if not path then
        return result  -- 如果没有匹配到路径，直接返回结果
    end
    
    result.database = path
    
    -- 检查是否包含远程资源
    local m_resource = ngx.re.match(path, "^:resource:(.+)$", "jo")
    if m_resource then
        local resource_url = m_resource[1]
        result.params["resource"] = resource_url
        
        -- 检查资源URL是否危险
        local is_dangerous, pattern = jdbc.check_dangerous_content(resource_url)
        if is_dangerous then
            result.vulnerable = true
            table.insert(result.vulnerability_details, {
                param = "resource",
                value = resource_url,
                reason = "包含危险URL: " .. pattern
            })
        end
    end
    
    return result
end

-- 解析 DB2 JDBC URL
function jdbc.parse_db2_url(url, result)
    -- 格式: jdbc:db2://host:port/database:param1=value1;param2=value2;
    local m = ngx.re.match(url, "db2://([^:/]+):?(\\d*)/?([^:]*)", "jo")
    local host, port, database = nil, nil, nil
    if m then
        host, port, database = m[1], m[2], m[3]
    end
    result.host = host or ""
    result.port = port and port ~= "" and port or "50000"
    result.database = database and database ~= "" and database or nil
    
    -- 解析参数 (使用冒号和分号分隔)
    local m_params = ngx.re.match(url, ":([^/]+)$", "jo")
    local params_str = m_params and m_params[1]
    if params_str then
        local iterator, err = ngx.re.gmatch(params_str, "([^=;]+)=([^;]*)", "jo")
        if not iterator then
            return result
        end
        
        local m
        local iteration_count = 0
        local max_iterations = 20
        
        while true do
            iteration_count = iteration_count + 1
            if iteration_count > max_iterations then
                break
            end
            
            m, err = iterator()
            if not m then
                break
            end
            local param, value = m[1], m[2]
            result.params[param] = value
            
            -- 检查危险参数
            if jdbc.dangerous_params[param] then
                result.vulnerable = true
                table.insert(result.vulnerability_details, {
                    param = param,
                    value = value,
                    reason = "危险参数"
                })
            end
            
            -- 检查值是否包含危险类
            local is_dangerous, pattern = jdbc.check_dangerous_content(value)
            if is_dangerous then
                result.vulnerable = true
                table.insert(result.vulnerability_details, {
                    param = param,
                    value = value,
                    reason = "包含危险类或URL: " .. pattern
                })
            end
        end
    end
    
    return result
end

-- 解析 Derby JDBC URL
function jdbc.parse_derby_url(url, result)
    -- 格式: jdbc:derby:path;param1=value1;param2=value2
    local m = ngx.re.match(url, "jdbc:derby:([^;]+)", "jo")
    local path = m and m[1]
    if path then
        result.database = path
    end
    
    -- 解析参数
    local iterator, err = ngx.re.gmatch(url, ";([^=;]+)=([^;]*)", "jo")
    if not iterator then
        return result
    end
    
    local m
    local iteration_count = 0
    local max_iterations = 20
    
    while true do
        iteration_count = iteration_count + 1
        if iteration_count > max_iterations then
            break
        end
        
        m, err = iterator()
        if not m then
            break
        end
        local param, value = m[1], m[2]
        result.params[param] = value
        
        -- 检查危险参数
        if jdbc.dangerous_params[param] then
            result.vulnerable = true
            table.insert(result.vulnerability_details, {
                param = param,
                value = value,
                reason = "危险参数"
            })
        end
        
        -- 检查值是否包含危险类
        local is_dangerous, pattern = jdbc.check_dangerous_content(value)
        if is_dangerous then
            result.vulnerable = true
            table.insert(result.vulnerability_details, {
                param = param,
                value = value,
                reason = "包含危险类或URL: " .. pattern
            })
        end
    end
    
    return result
end

-- 解析 JCR JDBC URL
function jdbc.parse_jcr_url(url, result)
    -- 格式: jdbc:jcr:jndi:ldap://host:port/path
    local m = ngx.re.match(url, "jdbc:jcr:jndi:(.+)", "jo")
    local jndi_url = m and m[1]
    if jndi_url then
        result.params["jndi"] = jndi_url
        
        result.vulnerable = true
        table.insert(result.vulnerability_details, {
            param = "jndi",
            value = jndi_url,
            reason = "JNDI URL 可能导致远程代码执行"
        })
    end
    
    return result
end

-- 解析 H2 JDBC URL
function jdbc.parse_h2_url(url, result)
    -- 格式: jdbc:h2:path;param1=value1;param2=value2
    local m = ngx.re.match(url, "jdbc:h2:([^;]+)", "jo")
    local path = m and m[1]
    if path then
        result.database = path
    end
    
    -- 解析参数
    local iterator, err = ngx.re.gmatch(url, ";([^=;]+)=([^;]*)", "jo")
    if not iterator then
        return result
    end
    
    local m
    local iteration_count = 0
    local max_iterations =  20
    
    while true do
        iteration_count = iteration_count + 1
        if iteration_count > max_iterations then
            break
        end
        
        m, err = iterator()
        if not m then
            break
        end
        local param, value = m[1], m[2]
        result.params[param] = value
        
        -- 检查危险参数
        if jdbc.dangerous_params[param] then
            result.vulnerable = true
            table.insert(result.vulnerability_details, {
                param = param,
                value = value,
                reason = "危险参数"
            })
        end
        
        -- 检查值是否包含危险类
        local is_dangerous, pattern = jdbc.check_dangerous_content(value)
        if is_dangerous then
            result.vulnerable = true
            table.insert(result.vulnerability_details, {
                param = param,
                value = value,
                reason = "包含危险类或URL: " .. pattern
            })
        end
    end
    
    return result
end


-- 解析 JDBC URL
function jdbc.parse_jdbc_url(url)
    local result = {
        db_type = nil,
        host = nil,
        port = nil,
        database = nil,
        params = {},
        vulnerable = false,
        vulnerability_details = {}
    }
    -- 提取数据库类型
    local m = ngx.re.match(url, "^jdbc:([^:]+):", "jo")
    local db_type = m and m[1]
    if db_type then
        result.db_type = db_type
    else
        return nil, "无效的 JDBC URL 格式"
    end
    -- 根据不同数据库类型解析 URL
    if db_type == "mysql" then
        return jdbc.parse_mysql_url(url, result)
    elseif db_type == "postgresql" then
        return jdbc.parse_postgresql_url(url, result)
    elseif db_type == "sqlite" then
        return jdbc.parse_sqlite_url(url, result)
    elseif db_type == "db2" then
        return jdbc.parse_db2_url(url, result)
    elseif db_type == "derby" then
        return jdbc.parse_derby_url(url, result)
    elseif db_type == "jcr" then
        return jdbc.parse_jcr_url(url, result)
    elseif db_type == "h2" then
        return jdbc.parse_h2_url(url, result)
    else
        return nil, "无效的 JDBC URL 格式"
    end
end

-- 主函数：分析 JDBC URL 并返回结果
function jdbc.analyze(jdbc_url)
    if not jdbc_url or jdbc_url == "" then
        return 0
    end
    
    local result, err = jdbc.parse_jdbc_url(jdbc_url)
    if err then
        return 0
    end
    if result==nil then
        return 0
    end
    if result.vulnerable then return 100 end
    if result.db_type=="mysql" or result.db_type=="postgresql" or result.db_type=="db2"  then 
        if result.host and result.port then return 100 end
    elseif result.db_type=="h2" or result.db_type=="sqlite" or result.db_type=="derby" or result.db_type=="jcr"  then 
        if result.database then return 100 end
        if jdbc.table_length(result.params) > 0 then return 100 end 
    else
        return 0
    end 
    return 0 
end

return jdbc