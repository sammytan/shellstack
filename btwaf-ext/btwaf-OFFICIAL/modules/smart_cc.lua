local smart_cc = {}

-- 获取人机验证类型
-- @return string
function smart_cc.get_verify_type()
    return 'btwaf'
end

-- 开始CC防护
-- @return void
function smart_cc.start()
    if BTWAF_RULES.smart_cc_list_count==0 then  return end
    -- 获取拦截级别
    if BTWAF_RULES.smart_cc_list[ngx.ctx.server_name] == nil then
        return
    end
    local level = smart_cc.run()
    -- 如果拦截级别为0，则直接放行
    if level == 0 then
        return
    elseif level == 1 then
        local verify_type = smart_cc.get_verify_type()
        ngx.ctx.is_url_type="智能CC"
        ngx.var.waf2monitor_blocked="智能CC-发送人机验证"
        BTWAF_OBJS.cc.renjiyanzheng(verify_type)
        return
    end
end

-- 获取历史请求的响应类型
-- @return string
function smart_cc.get_resp_content_type()
    local key = ngx.md5(ngx.ctx.server_name..':'..ngx.ctx.url_split)
    local content_type = ngx.shared.smart_cc:get(key)
    if content_type ~= nil then return content_type end
    return ""
end

-- 启动CC防护
-- @return int 0=正常访问 1=人机验证 2=禁止访问
function smart_cc.run()
    -- 获取当前CC防护级别
    if ngx.ctx.method ~= "GET" and ngx.ctx.method ~= "HEAD" then
        return 0
    end
   -- 直接放行局域网IP
    local is_lan = Public.is_lan_ip(ngx.ctx.ip)
    if is_lan then
        return 0
    end
    if  ngx.ctx.is_api then
        return 0
    end

    if ngx.shared.smart_cc:get(ngx.ctx.server_name.."cc") then return 1 end

    -- QPS小于10则不启动智能CC
    local qps=Logs.smart_get_cache(ngx.ctx.server_name,"qps")
    if qps<10 then
        return 0
    end

    local today,hour,minute = Public.get_pre_minute()
    local date_key='req_'..today .. '_' ..  hour .. '_' ..  minute
    local minute_req=Public.logs_get(ngx.ctx.server_name,date_key)
    local err_499_count=Public.get_error499()
    local timeout=ngx.shared.smart_cc:get(ngx.ctx.server_name.."_timecount")
    if timeout and timeout>20 then
        local minute_req_tmp= minute_req*0.01
        if minute_req_tmp<20 then 
            minute_req_tmp=20
        end
        if timeout>minute_req_tmp then 
            ngx.shared.smart_cc:set(ngx.ctx.server_name.."cc",1,60)
            Public.logs(ngx.ctx.server_name.." 60秒内出现超时请求超过"..timeout.."次、触发智能CC 限制60秒内触发人机验证")
            return 1
        end
    end
    local err_499 =Logs.smart_get_cache(ngx.ctx.server_name,'err_499')
    if err_499 and err_499> err_499_count then
        ngx.shared.smart_cc:set(ngx.ctx.server_name.."cc",1,120)
        Public.logs(ngx.ctx.server_name.." 60秒内出现499状态码",err_499_count,"次、触发智能CC 限制120秒内触发人机验证")
        return 1
    end
    local err_502 =Logs.smart_get_cache(ngx.ctx.server_name,'err_502')
    if err_502 and err_502>10 then
        local minute_req_tmp= minute_req*0.01
        if minute_req_tmp<20 then 
            minute_req_tmp=20
        end
        if err_502>minute_req_tmp then 
            ngx.shared.smart_cc:set(ngx.ctx.server_name.."cc",1,120)
            Public.logs(ngx.ctx.server_name.." 60秒内出现502超时"..err_502.."次、触发智能CC 限制120秒内触发人机验证")
            return 1
        end
    end

    local cache_key="total_report_"..ngx.ctx.server_name
    local report_data=ngx.shared.spider:get(cache_key)
    if report_data~=nil then 
        report_data=Json.decode(report_data)
        if report_data.avg_request~=nil and report_data.avg_request>500 then 
            local date_key='req_'..ngx.ctx.today .. '_' ..  ngx.ctx.hour .. '_' .. ngx.ctx.minute
            local minute_req=Public.logs_get(ngx.ctx.server_name,date_key)
            -- 最大值report_data
            if minute_req>report_data.request_max*2.5 then 
                ngx.shared.smart_cc:set(ngx.ctx.server_name.."cc",1,120)
                Public.logs(ngx.ctx.server_name.." 60秒内QPS大于最近一小时最大值的2.5倍、触发智能CC 限制120秒内触发人机验证")
                return 1
            end 
            if minute_req>report_data.avg_request*3.5 then 
                ngx.shared.smart_cc:set(ngx.ctx.server_name.."cc",1,120)
                Public.logs(ngx.ctx.server_name.." 60秒内QPS触发上一个小时的QPS的3.5倍、触发智能CC 限制120秒内触发人机验证")
                return 1
            end
        end
    end




    return 0
end

-- 一级CC防御
-- @param int cc_level 当前CC防护级别
-- @param bool is_inland 是否为境内IP
-- @return int 0=正常访问 1=人机验证 2=禁止访问
function smart_cc.level_one(cc_level, is_inland)
    return 0
end


-- 二级CC防御
-- @param int cc_level 当前CC防护级别
-- @param bool is_inland 是否为境内IP
-- @return int 0=正常访问 1=人机验证 2=禁止访问
function smart_cc.level_two(cc_level,is_idc)
    if cc_level < 2 then
        return 0
    end
    -- 境外IP要求人机验证
    if not is_idc then
        return 1
    end

    return 0
end


-- 三级CC防御
-- @param int cc_level 当前CC防护级别
-- @param bool is_inland 是否为境内IP
-- @return int 0=正常访问 1=人机验证 2=禁止访问
function smart_cc.level_three(cc_level,is_idc)
    if cc_level < 3 then
        return 0
    end

    -- 没有cookie的直接禁止访问
    -- local token=ngx.md5(ngx.ctx.Server_name)
    -- if  not ngx.ctx.cookie[token] then
    --     return 2
    -- end

    -- 境内访问要求人机验证
    return 1
end


-- 四级CC防御
-- @param int cc_level 当前CC防护级别
-- @return int 0=正常访问 1=人机验证 2=禁止访问
function smart_cc.level_four(cc_level,is_inland)
    if cc_level < 4 then
        return 0
    end

    -- 禁止境外访问
    if not is_inland then
        -- 如果是境内访问比较多的情况下，才禁止境外访问
        local global_is_inland = Workers.get_cache('global','global_is_inland')
        if global_is_inland ~= nil then
            if global_is_inland == 1 then
                return 2
            end
        end
    end

    -- 其它访问要求人机验证
    return 1
end

-- 五级CC防御
-- @param int cc_level 当前CC防护级别
-- @return int 0=正常访问 2=禁止访问
function smart_cc.level_five(cc_level)
    if cc_level < 5 then
        return 0
    end

    -- 禁止所有访问
    return 2
end

return smart_cc