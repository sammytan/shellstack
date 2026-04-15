local header ={}

header.header_key={}
header.header_key["cache-control"]=true
header.header_key["upgrade-insecure-requests"]=true
header.header_key["content-length"]=true
header.header_key["accept"]=true
header.header_key["accept-language"]=true
header.header_key["host"]=true
header.header_key["user-agent"]=true
header.header_key["connection"]=true
header.header_key["content-type"]=true
header.header_key["cookie"]=true
header.header_key["accept-encoding"]=true
header.header_key["token"]=true
header.header_key["jwt-token"]=true
header.header_key["origin"]=true
header.header_key["pragma"]=true
header.header_key["referer"]=true
header.header_key["x-http-token"]=true
header.header_key["authorization"]=true
header.header_key["x-requested-with"]=true
header.header_key["access-control-request-method"]=true
header.header_key["access-control-request-headers"]=true
header.header_key["if-none-match"]=true
header.header_key["x-csrf-token"]=true
header.header_key["cf-connecting-ip"]=true
header.header_key["ali-cdn-real-ip"]=true
header.header_key["true-client-ip"]=true
header.header_key["x-real-ip"]=true
header.header_key["x-forwarded-for"]=true
header.header_key["x-forwarded-proto"]=true
header.header_key["transfer-encoding"]=true
header.header_key["from"]=true
header.header_key["via"]=true
header.header_key["x-alicdn-da-via"]=true
header.header_key["ali-swift-ukeepalive-timeout"]=true
header.header_key["ali-tproxy-urequest-timeout"]=true
header.header_key["ali-swift-gzip"]=true
header.header_key["ali-swift-brotli"]=true 
header.header_key["ali-cdn-appview-name"]=true
header.header_key["x-client-scheme"]=true
header.header_key["ali-swift-stat-host"]=true
header.header_key["ali-swift-log-host"]=true
header.header_key["ali-cdn-real-port"]=true
header.header_key["eagleeye-traceid"]=true
header.header_key["ali-swift-urequest-timeout"]=true
header.header_key["sec-fetch-dest"]=true
header.header_key["sec-fetch-user"]=true
header.header_key["sec-fetch-mode"]=true
header.header_key["sec-ch-ua-mobile"]=true
header.header_key["sec-ch-ua-platform"]=true
header.header_key["sec-fetch-site"]=true
header.header_key["sec-gpc"]=true
header.header_key["dnt"]=true
header.header_key["keep-alive"]=true

header.header_key["sec-ch-ua"]=true
header.header_key["if-modified-since"]=true
header.header_key["accept-charset"]=true
header.header_key["cf-ray"]=true
header.header_key["cf-visitor"]=true
header.header_key["cf-ipcountry"]=true
header.header_key["cdn-loop"]=true
header.header_key["priority"]=true

header.header_key["upgrade"]=true






function  header.return_error3(method,msg)
	ngx.ctx.error_rule = msg
	IpInfo.write_log(method,msg)
end 

function header.method_type_check(method)
    local method_type={}
    if not Config['method_type'] then 
        return true
    else
        method_type=Config['method_type']
    end
    for _,v in ipairs(method_type) do
        if method == v[1] and not v[2] then
            
            return false 
        end
    end 
    return true 
end 

function header.header_check(header_data,len_data,header)
    for i,v in pairs(header_data) do
            if header == v[1] then 
                 if tonumber(len_data)>tonumber(v[2]) then return true end 
                 return false
            end
    end 
   	if len_data>20000 then return true end
    return false
end 

function header.get_http_referer(http_referer)
	if http_referer==nil then return false end
    -- 如果是搜索引擎直接返回false 
    if ngx.re.match(http_referer,"^(https://github.com|https://www.github.com|https://www.zhihu.com|https://cn.bing.com|https://www.baidu.com|https://www.google.com|https://www.so.com|https://www.toutiao.com|https://m.sm.cn)","jo") then 
        return false
    end

    local list = {}
    local start_pos = string.find(http_referer, '?') or 1
    local flag=false
    while start_pos <= #http_referer do
        local equals_pos = string.find(http_referer, '=', start_pos)
        if not equals_pos then flag=true break end
        local and_pos = string.find(http_referer, '&', equals_pos) or (#http_referer + 1)

        local param_value = ngx.unescape_uri(string.sub(http_referer, equals_pos+1, and_pos-1))
        table.insert(list, param_value)
        start_pos = and_pos + 1
    end
    if flag then 
        if ngx.re.match(http_referer,"^http://|^https://","jo") then 
            return false
        end 
        return {http_referer}
    end 
    return list
end


function header.header_len_check(request_header)
    	
    -- 检查header 
    if ngx.ctx.request_header_infos and Check.args_urlencoded(ngx.ctx.request_header_infos) then
	    ngx.ctx.is_type="恶意Header拦截"
		ngx.var.waf2monitor_blocked="恶意Header拦截"
		IpInfo.write_log('header','恶意Header拦截')
		Public.return_html(Config['get']['status'],BTWAF_RULES.get_html)
		return true
	end
    --检测referer
	local http_referer=ngx.ctx.referer
	if http_referer~=nil and http_referer~="btwaf_referer_null" then
	    local header_list=header.get_http_referer(http_referer)
	    if type(header_list)=='table' then Check.args_urlencoded(header_list) end
	end 
    local method=ngx.ctx.method
	if method=='PROPFIND' or  method=='PROPPATCH' or method=='MKCOL' or method=='CONNECT'  or method=='SRARCH' or method=='REPORT' then return false end
    if not header.method_type_check(method) then
        ngx.ctx.is_type="请求类型过滤"
    	header.return_error3(method,'宝塔WAF提醒您不允许您当前的请求类型'..method..'此请求类型已经被禁用。如需开启请在Nginx防火墙-->全局设置-->HTTP请求过滤-->请求类型过滤开启'..method..'请求') 
    	Public.return_html_data('网站防火墙','宝塔WAF提醒您不允许您当前的请求类型','宝塔WAF提醒您不允许您当前的请求类型','Nginx防火墙-->全局设置-->HTTP请求过滤-->请求类型过滤开启'..method..'请求')
    end
    if not request_header then  
        ngx.ctx.is_type="header获取失败"
    	header.return_error3(method,'宝塔WAF提醒您header获取失败,可能是头部请求太长,如有误报.请调整nginx的header获取大小')
    	Public.return_html_data('网站防火墙','网站防火墙提醒您header获取失败','网站防火墙提醒您header获取失败','调整nginx的header获取大小')
    end
    local header_data={}
    if not  Config['header_len'] then
        return false
    else
        header_data=Config['header_len']
    end 
    for i,v in pairs(request_header) do
      if  header.header_check(header_data,#v,i) then  
		if i=='cookie' or i=='user-agent' then return false end 
        header.return_error3(method,'网站防火墙提醒您header头部参数'..i..'太长，如有误报请在Nginx防火墙--全局设置--HTTP请求过滤--请求头过滤调整'..i..'的长度,如果没有这个'..i..'的选项需要添加建议把长度默认为10000')
      	Public.return_html_data('网站防火墙','网站防火墙提醒您header头部参数'..i..'太长','网站防火墙提醒您header头部参数'..i..'太长','Nginx防火墙-->全局设置-->HTTP请求过滤-->请求头过滤调整'..i..'的长度。如果没有这个'..i..'的选项需要添加建议把长度默认为10000')
      end
    end
end




function header.ua_whilie2(ua)
	if not ua then return false end 
	ua = string.lower(ua)
    if ngx.re.match(ua,'baiduspider',"jo") then return true end 
    if ngx.re.match(ua,'googlebot',"jo") then return true end 
    if ngx.re.match(ua,'360spider',"jo") then return true end 
    if ngx.re.match(ua,'sogou',"jo") then return true end 
    if ngx.re.match(ua,'yahoo',"jo") then return true end 
    if ngx.re.match(ua,'bingbot',"jo") then return true end 
    if ngx.re.match(ua,'yisouspider',"jo") then return true end 
	if ngx.re.match(ua,'haosouspider',"jo") then return true end 
	if ngx.re.match(ua,'sosospider',"jo") then return true end 
	if ngx.re.match(ua,'weixin',"jo") then return true end 
	if ngx.re.match(ua,'iphone',"jo") then return true end
	if ngx.re.match(ua,'android',"jo") then return true end 
end 

function header.header_lan(header2)
    if not Config['is_browser'] then return false end 
    if type(header2['connection'])~='string' then return false end 
    if header.ua_whilie2(ngx.ctx.ua) then return false end
    if Public.is_ssl() then return false end
    if header2['connection'] =='1' then 
        if ngx.ctx.method =='GET' then ngx.ctx.method='args' end 
        if ngx.ctx.method =='POST' then ngx.ctx.method ='post' end 
        ngx.ctx.is_type='非浏览器请求'
        Public.write_log('other','非浏览器请求已被系统拦截,如想关闭此功能如下操作:Nginx防火墙--全局设置--非浏览器拦截')
	    ngx.exit(200)
    end
end

-- 检查字符串是否包含特殊字符 (不是 a-zA-Z0-9)
function header.has_special_chars(str)
    if type(str) ~= "string" then
        return str
    end
    if not str or str == "" then
        return false
    end
    -- 使用正则查找非字母数字字符，找到即返回 true
    return ngx.re.find(str, "[^a-zA-Z0-9-\\.,$]", "jo") ~= nil
end

function header.is_check_header()
    local count=0
    local requests_tmp={}
	if type(ngx.ctx.request_header)=='table' then
		for k,v in pairs(ngx.ctx.request_header)
		do
            if header.header_key[k] ==nil then 
                if header.has_special_chars(v) then 
                    requests_tmp[k]=v
                end
            end 
			if type(v)=='table' then
				for k2,v2 in pairs(v) do 
				   count=count+1 
				end
            end
            if type(v)=="string" then 
                count=count+1
            end
		end
	end
	if count>800 then 
	    return IpInfo.lan_ip('scan','header字段大于800 被系统拦截') 
	end
    ngx.ctx.request_header_infos=requests_tmp
   

    return false
end


return header