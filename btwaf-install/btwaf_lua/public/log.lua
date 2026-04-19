local logs = {}

logs.static_header={}
logs.static_header["text/css"]=true
logs.static_header["text/xml"]=true
logs.static_header["image/gif"]=true
logs.static_header["image/jpeg"]=true
logs.static_header["application/javascript"]=true
logs.static_header["application/atom+xml"]=true
logs.static_header["application/rss+xml"]=true
logs.static_header["image/avif"]=true
logs.static_header["image/png"]=true
logs.static_header["image/svg+xml"]=true
logs.static_header["image/tiff"]=true
logs.static_header["image/vnd.wap.wbmp"]=true
logs.static_header["image/webp"]=true
logs.static_header["image/x-icon"]=true
logs.static_header["image/x-jng"]=true
logs.static_header["image/x-ms-bmp"]=true
logs.static_header["font/woff"]=true
logs.static_header["font/woff2"]=true
logs.static_header["application/java-archive"]=true
logs.static_header["application/msword"]=true
logs.static_header["application/pdf"]=true
logs.static_header["application/postscript"]=true
logs.static_header["application/rtf"]=true
logs.static_header["application/vnd.apple.mpegurl"]=true
logs.static_header["application/vnd.google-earth.kmz"]=true
logs.static_header["application/vnd.ms-excel"]=true
logs.static_header["application/vnd.ms-fontobject"]=true
logs.static_header["application/vnd.ms-powerpoint"]=true
logs.static_header["application/vnd.oasis.opendocument.graphics"]=true
logs.static_header["application/vnd.openxmlformats-officedocument.presentationml.presentation"]=true
logs.static_header["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"]=true
logs.static_header["application/vnd.openxmlformats-officedocument.wordprocessingml.document"]=true
logs.static_header["application/vnd.wap.wmlc"]=true
logs.static_header["application/wasm"]=true
logs.static_header["application/x-7z-compressed"]=true
logs.static_header["application/x-cocoa"]=true
logs.static_header["application/x-java-archive-diff"]=true
logs.static_header["application/x-java-jnlp-file"]=true
logs.static_header["application/x-makeself"]=true
logs.static_header["application/x-rar-compressed"]=true
logs.static_header["application/x-redhat-package-manager"]=true
logs.static_header["application/x-shockwave-flash"]=true
logs.static_header["application/x-x509-ca-cert"]=true
logs.static_header["application/zip"]=true
logs.static_header["application/octet-stream"]=true
logs.static_header["audio/midi"]=true
logs.static_header["audio/mpeg"]=true
logs.static_header["audio/ogg"]=true
logs.static_header["audio/x-m4a"]=true
logs.static_header["audio/x-realaudio"]=true
logs.static_header["video/3gpp"]=true
logs.static_header["video/mp2t"]=true
logs.static_header["video/mp4"]=true
logs.static_header["video/mpeg"]=true
logs.static_header["video/quicktime"]=true
logs.static_header["video/webm"]=true
logs.static_header["video/x-flv"]=true
logs.static_header["video/x-m4v"]=true
logs.static_header["video/x-mng"]=true
logs.static_header["video/x-ms-asf"]=true
logs.static_header["video/x-ms-wmv"]=true
logs.static_header["video/x-msvideo"]=true


logs.static_ext={}
logs.static_ext[".css"]="text/css"
logs.static_ext[".xml"]="text/xml"
logs.static_ext[".gif"]="image/gif"
logs.static_ext[".jpeg"]="image/jpeg"
logs.static_ext[".jpg"]="image/jpeg"
logs.static_ext[".js"]="application/javascript"
logs.static_ext[".atom"]="application/atom+xml"
logs.static_ext[".rss"]="application/rss+xml"
logs.static_ext[".avif"]="image/avif"
logs.static_ext[".png"]="image/png"
logs.static_ext[".svg"]="image/svg+xml"
logs.static_ext[".tiff"]="image/tiff"
logs.static_ext[".wbmp"]="image/vnd.wap.wbmp"
logs.static_ext[".webp"]="image/webp"
logs.static_ext[".ico"]="image/x-icon"
logs.static_ext[".jng"]="image/x-jng"
logs.static_ext[".bmp"]="image/x-ms-bmp"
logs.static_ext[".woff"]="font/woff"
logs.static_ext[".woff2"]="font/woff2"
logs.static_ext[".jar"]="application/java-archive"
logs.static_ext[".doc"]="application/msword"
logs.static_ext[".pdf"]="application/pdf"
logs.static_ext[".ps"]="application/postscript"
logs.static_ext[".rtf"]="application/rtf"
logs.static_ext[".m3u8"]="application/vnd.apple.mpegurl"
logs.static_ext[".kmz"]="application/vnd.google-earth.kmz"
logs.static_ext[".xls"]="application/vnd.ms-excel"
logs.static_ext[".eot"]="application/vnd.ms-fontobject"
logs.static_ext[".ppt"]="application/vnd.ms-powerpoint"
logs.static_ext[".odg"]="application/vnd.oasis.opendocument.graphics"
logs.static_ext[".pptx"]="application/vnd.openxmlformats-officedocument.presentationml.presentation"
logs.static_ext[".xlsx"]="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
logs.static_ext[".docx"]="application/vnd.openxmlformats-officedocument.wordprocessingml.document"
logs.static_ext[".wmlc"]="application/vnd.wap.wmlc"
logs.static_ext[".wasm"]="application/wasm"
logs.static_ext[".7z"]="application/x-7z-compressed"
logs.static_ext[".cocoa"]="application/x-cocoa"
logs.static_ext[".jnlp"]="application/x-java-jnlp-file"
logs.static_ext[".run"]="application/x-makeself"
logs.static_ext[".rar"]="application/x-rar-compressed"
logs.static_ext[".rpm"]="application/x-rpm"
logs.static_ext[".swf"]="application/x-shockwave-flash"
logs.static_ext[".crt"]="application/x-x509-ca-cert"
logs.static_ext[".zip"]="application/zip"
logs.static_ext[".mid"]="audio/midi"
logs.static_ext[".midi"]="audio/midi"
logs.static_ext[".mp3"]="audio/mpeg"
logs.static_ext[".ogg"]="audio/ogg"
logs.static_ext[".m4a"]="audio/x-m4a"
logs.static_ext[".ra"]="audio/x-realaudio"
logs.static_ext[".3gp"]="video/3gpp"
logs.static_ext[".ts"]="video/mp2t"
logs.static_ext[".mp4"]="video/mp4"
logs.static_ext[".mpeg"]="video/mpeg"
logs.static_ext[".mpg"]="video/mpeg"
logs.static_ext[".mov"]="video/quicktime"
logs.static_ext[".webm"]="video/webm"
logs.static_ext[".flv"]="video/x-flv"
logs.static_ext[".m4v"]="video/x-m4v"
logs.static_ext[".mng"]="video/x-mng"
logs.static_ext[".asf"]="video/x-ms-asf"
logs.static_ext[".wmv"]="video/x-ms-wmv"
logs.static_ext[".avi"]="video/x-msvideo"
logs.static_ext[".ttf"]="font/ttf"




-- 请求数统计
function logs.request_incr()
    logs.traffic_incr()
    logs.ip_count_minute()
    local key = 'req_'.. logs.date_key
    Public.logs_incr("global",key,1,logs.cycle)
    Public.logs_incr(logs.server_name,key,1,logs.cycle)
    if ngx.ctx.proxy==nil then ngx.ctx.proxy=false end
    if ngx.ctx.proxy then
        Public.logs_incr("global","proxy_count"..key,1,logs.cycle)
        Public.logs_incr(logs.server_name,"proxy_count"..key,1,logs.cycle)
    end
    if logs.session==1 then 
        Public.logs_incr("global","session_count"..key,1,logs.cycle)
        Public.logs_incr(logs.server_name,"session_count"..key,1,logs.cycle)
    end 
    Public.logs_incr(logs.time,'qps',1,10)
    if logs.length>0 then 
        Public.logs_incr(logs.time,'traffic',logs.length,10)
    end 
    -- 智能CC
    logs.smart_cc_cache(logs.server_name,'qps',1,1)
end



-- 指定缓存值+1
-- @param string server_name  网站名称
-- @param string key  缓存key
-- @param int num 增加的值
-- @return void
function logs.cache_incr(server_name,key,num)
    if not key then return end
    local skey = server_name .. '_status_' .. key
    local val = ngx.shared.smart_cc:get(skey)
    if val == nil then
		logs.today_expire_time = Public.get_today_end_time() - logs.time
        ngx.shared.smart_cc:set(skey,0,logs.today_expire_time)
    end
    ngx.shared.smart_cc:incr(skey,num)
end

function logs.smart_cc_cache(server_name,key,num,expire_time)
    if BTWAF_RULES.smart_cc_list_count==0 then  return end
    if BTWAF_RULES.smart_cc_list[logs.server_name]==nil then return false end
    if not key then return end
    local skey = server_name .. '_status_' .. key
    local val = ngx.shared.smart_cc:get(skey)
    if val == nil then
        ngx.shared.smart_cc:set(skey,0,expire_time)
    end
    ngx.shared.smart_cc:incr(skey,num)
end 

function logs.smart_get_cache(server_name,key)
    if not key then return end
    local skey = server_name .. '_status_' .. key
    local val = ngx.shared.smart_cc:get(skey)
    if val == nil then
        return 0
    end
    return val
end


-- 错误码统计
function logs.err_incr()
    -- 不统计401以下的错误码
    if ngx.status < 401 then return end
    -- 判断当前错误码
    local err_key = 'err_'
    if ngx.status == 502 then
        err_key = err_key .. '502'
    elseif ngx.status == 499 then
        err_key = err_key .. '499'
    else
        return
    end
    -- 智能CC
    logs.smart_cc_cache(logs.server_name,err_key,1,60)
    
    local key = err_key .. '_' .. logs.date_key
    Public.logs_incr(logs.server_name,key,1,logs.cycle)
    Public.logs_incr("global",key,1,logs.cycle)

end

-- 统计回源耗时
function logs.upstream_response_time()
    if ngx.var.upstream_response_time==nil then return end
    if not ngx.var.upstream_response_time then return end
    if not tonumber(ngx.var.upstream_response_time) then return end
    local upstream_response_time = tonumber(ngx.var.upstream_response_time) * 1000
    if upstream_response_time==nil then return false end 
    Public.logs_incr(logs.time,'proxy_time',upstream_response_time,10)
    Public.logs_incr(logs.time,'proxy_count',1,10)
    if BTWAF_RULES.smart_cc_list_count==0 then  return end
    if BTWAF_RULES.smart_cc_list[logs.server_name]==nil then return false end
    if upstream_response_time>2000 and not ngx.ctx.is_api then 
        local timeout=ngx.shared.smart_cc:get(logs.server_name.."_timecount")
        if not timeout then 
            ngx.shared.smart_cc:set(logs.server_name.."_timecount",1,60)
        else 
            ngx.shared.smart_cc:incr(logs.server_name.."_timecount",1)
        end
    end
end


function logs.get_length()
    local clen = ngx.var.bytes_sent
    if clen == nil then
        clen = 0
    end
    return tonumber(clen)
end


-- 每分钟的IP数量统计
function logs.ip_count_minute()
    -- 获取当前分钟还剩余多少秒
    local remaining_seconds = 60 - (logs.time % 60)
    local key = 'ip_count_' ..logs.ip
    if ngx.shared.ip_tmp:get(key) then 
        return
    end
    ngx.shared.ip_tmp:set(key,1,remaining_seconds + 1)
    local key = 'ip_count' .. '_' .. logs.date_key
    Public.logs_incr(logs.server_name,key,1,120)
    Public.logs_incr("global",key,1,120)
end


function logs.traffic_incr()
    if logs.length==0 then return end 
    -- 静态流量统计
    if logs.static_header[logs.content_type] then 
        local key = 'static_flow' .. '_' .. logs.date_key
        Public.logs_incr(logs.server_name,key,logs.length,logs.cycle)
        Public.logs_incr('global',key,logs.length,logs.cycle)
    end 
    -- 全部流量统计
    local key = 'flow' .. '_' .. logs.date_key
    Public.logs_incr(logs.server_name,key,logs.length,logs.cycle)
    Public.logs_incr('global',key,logs.length,logs.cycle)
end

-- IP流量统计
--   @auther lkq@bt.cn
--   @name 统计IP的流量、次数
function logs.ip_count_incr()
    if logs.length==0 then return end
    if ngx.ctx.white_rule==true and (ngx.ctx.white_type=="IP白名单" or ngx.ctx.white_type=="蜘蛛列表IP") then return false end
    local token=logs.ip.."|"..logs.server_name
    local token_data=ngx.shared.ip:get(token)
    if token_data then 
        token_data=Public.split(token_data,"|")
        if token_data==nil then return end 
        if Public.arrlen(token_data)<5 then  return end 
        local count =tonumber(token_data[1])
        local static=tonumber(token_data[2])
        local traffic=tonumber(token_data[3])
        local static_traffic=tonumber(token_data[4])
        local session_count=tonumber(token_data[5])
        if logs.static_header[logs.content_type] then 
            static=static+1
            static_traffic=static_traffic+logs.length
        end
        if logs.session==1 then 
            session_count=session_count+1
        end 
        count=count+1
        traffic=traffic+logs.length
        ngx.shared.ip:set(token,count.."|"..static.."|"..traffic.."|"..static_traffic.."|"..session_count.."|"..logs.time,logs.today_expire_time)
    else
        -- 如果在Top500 中则直接写入到ngx.shared.ip 中
        local ipcount=ngx.shared.spider:get(token)
        if ipcount~=nil and ipcount>10 then 
            local session=0
            if logs.session==1 then 
                session=1
            end 
            ngx.shared.ip:set(token,"1|0|"..logs.length.."|0|"..session.."|"..logs.time,logs.today_expire_time)
        else
            local ip_tmp_count=ngx.shared.ip_tmp:get(token)
            if ip_tmp_count then 
                ngx.shared.ip_tmp:incr(token,1)
                if ip_tmp_count>20 then 
                    local session=0
                    if logs.session==1 then 
                        session=21
                    end 
                    if logs.static_header[logs.content_type] then 
                        ngx.shared.ip:set(token,"21|11|"..logs.length.."|"..logs.length.."|"..session.."|"..logs.time,logs.today_expire_time)
                    else
                        ngx.shared.ip:set(token,"21|0|"..logs.length.."|0|"..session.."|"..logs.time,logs.today_expire_time)
                    end
                end
            else
                ngx.shared.ip_tmp:set(token,1,900)
            end
        end
    end
end

function logs.uri_incr()
    if ngx.status==404 then return false end
    if ngx.status==405 then return false end
    if ngx.status==302 then return false end
    if ngx.status==301 then return false end
    if logs.length==0 then return end
    -- if ngx.ctx.white_rule==true and ngx.ctx.white_type=="URL白名单" then return false end
    if logs.url_split==nil then return end
    local token=""
    local static=false
    local static_fix=false
    token=logs.server_name.."|"..logs.url_split
    if logs.static_header[logs.content_type] then 
        static=true
        local end_fix=Public.get_end_fix(logs.url_split)
        if logs.static_ext[end_fix]~=nil then 
            static_fix=true
        end 
    end
    if #token >255 then 
        token=string.sub(token,1,249)
    end 
    local token_data=ngx.shared.url:get(token)
    if token_data then 
        token_data=Public.split(token_data,"|")
        if token_data==nil then  return end 
        if Public.arrlen(token_data)<6 then return end 
        local count=tonumber(token_data[1])
        local static_count=tonumber(token_data[2])
        local flow=tonumber(token_data[3])
        local flow_static=tonumber(token_data[4])
        local session_count=tonumber(token_data[5])
        count=count+1
        if static then
            static_count=static_count+1
            flow_static=flow_static+logs.length
        end 
        if logs.session==1 then 
            session_count=session_count+1
        end
        flow=flow+logs.length
        local value=count.."|"..static_count.."|"..flow.."|"..flow_static.."|"..session_count.."|"..logs.time.."|"..logs.content_type
        ngx.shared.url:set(token,value,logs.today_expire_time)
    else
        local ip_tmp_count=ngx.shared.url_tmp:get(token)
        if ip_tmp_count then 
            ngx.shared.url_tmp:incr(token,1)
            if ip_tmp_count>20 then 
                local fow=logs.length*15
                local session=0
                if logs.session==1 then 
                    session=1
                end
                local value="21|0|"..fow.."|0|"..session.."|"..logs.time.."|"..logs.content_type
                if static_fix then 
                    value="21|21|"..fow.."|"..fow.."|"..session.."|"..logs.time.."|"..logs.content_type
                end 
                ngx.shared.url:set(token,value,logs.today_expire_time)
            end
        else
            ngx.shared.url_tmp:set(token,1,240)
        end
    end
end 

function logs.start()
    if ngx.var.request_uri == '/favicon.ico' or ngx.status == 0 or ngx.status == 444 then return true end
    if not Config['open']  then return false end
    if not Public.is_site_config('open')  then return false end
    logs.ip=ngx.ctx.ip
    if logs.ip == nil or not logs.ip or logs.ip=="" then
        logs.ip = IpInfo.get_client_ip_bylog()
        if logs.ip == nil or not logs.ip or logs.ip=="" then
            return 
        end
    end
    logs.server_name = ngx.ctx.server_name
    if logs.server_name == nil then
        logs.server_name =Public.get_server_name_waf()
    end

    logs.content_type =ngx.header.content_type
     if logs.content_type==nil then 
       logs.content_type=""
    end

    logs.url_split = ngx.ctx.url_split
    if logs.url_split==nil then 
        logs.url_split=Public.get_request_uri()
    end 

    if logs.ip == '127.0.0.1' then return true end
    if logs.server_name=="127.0.0.1" then return false end
    logs.time = ngx.ctx.time
    if logs.time == nil then
        logs.time = Public.int(ngx.now())
    end
    logs.today = ngx.ctx.today
    if logs.today == nil then
        logs.today = ngx.today()
    end
    logs.hour = ngx.ctx.hour
    if logs.hour == nil then
        logs.hour = os.date("%H")
    end
    logs.minute = ngx.ctx.minute
    if logs.minute == nil then
        logs.minute = os.date("%M")
    end
    
    logs.length=logs.get_length()
    logs.session=Public.check_server_name_session()
    logs.today_expire_time = Public.get_today_end_time_logs() - logs.time
    logs.date_key=logs.today .. '_' ..  tonumber(logs.hour) .. '_' .. tonumber(logs.minute)
    logs.cycle = 360
    logs.ip_count_incr()
    logs.uri_incr()
    logs.request_incr()
    logs.err_incr()
end 


return logs