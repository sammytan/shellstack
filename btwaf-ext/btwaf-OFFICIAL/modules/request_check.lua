local request_check={}
local upload = require "upload"
local bt_engine =require "bt_engine"
local php_engine =require "php_engine"
local xss_engine =require "xss_engine"
local ngx_match = ngx.re.find


-- 记录攻击的详细日志,日志中包含uri header 头部和发送的参数
-- @return 返回详细的攻击日志
function request_check.http_log()
	local data = ""
	data = ngx.ctx.method .. " " .. ngx.var.request_uri .. " " .. "HTTP/1.1\n"
	if not ngx.ctx.request_header then
		return data
	end
	for key, valu in pairs(ngx.ctx.request_header) do
		if type(valu) == "string" then
			data = data .. key .. ": " .. valu .. "\n"
		end
		if type(valu) == "table" then
			for key2, val2 in pairs(valu) do
				data = data .. key .. ": " .. val2 .. "\n"
			end
		end
	end
	data=data.."waf-intercept-client-ip-port: "..ngx.var.remote_addr..":"..ngx.var.remote_port.."\n"
	data = data .. "\n"

	if ngx.ctx.method ~= "GET" then
		if ngx.ctx.header_btwaf ==true then return data end 
	   ngx.req.read_body()
	   local body_info=ngx.req.get_body_data()
	   if body_info then
	        if #body_info>1024*1024 and not Config["http_open"] then 
	            data = data ..string.sub(body_info, 1, 1024*1024) .. "\n该数据包较大系统默认只截取1M大小数据其他的不存储,如需要开启,请在[全局配置-->日志记录]"
	        else 
	            data = data .. body_info
	        end
		else
			if Config["http_open"] then
				local request_args2 = ngx.req.get_body_file()
				request_args2 = Public.read_file_body(request_args2)
				if request_args2~=nil then data = data .. request_args2 end
			else
				if ngx.ctx.method=="POST" then 
					data = data .. "\n拦截非法恶意上传文件或者非法from-data传值,该数据包较大系统默认不存储,如需要开启,请在[全局配置-->日志记录]"
				end
			end
			return data
		end 
	end
	return data
end

function request_check.is_body_intercept(body)
    if not Config['open'] or not Public.is_site_config('open') then return false end
    if not Config['body_intercept'] then return false end 
    if Public.arrlen(Config['body_intercept'])==0  then return false end
    if Config['body_intercept'] then
		for __,v in pairs(Config['body_intercept'])
		do
			if ngx.re.match(ngx.unescape_uri(body),v,"jo") then
			    ngx.var.waf2monitor_blocked="违禁词拦截"
				Public.return_html_data('禁止存在违禁词','禁止存在违禁词','禁止存在违禁词','禁止存在违禁词')
			end
		end
	end
end




function request_check.continue_key(key)
    if ngx.ctx.method~='POST' then return true end  
	key = tostring(key)
	if string.len(key) > 64 then return false end;
	local keys = {"content","contents","body","msg","file","files","img","newcontent","message","subject","kw","srchtxt",""}
	for _,k in ipairs(keys)
	do
		if k == key then return false end;
	end
	return true;
end


function request_check.select_rule2(is_type,rule)
    if is_type =='post' or is_type=='args' or is_type=='url' then
        local post_rules2 =Public.read_file(is_type)
    	if not post_rules2 then return nil end
    	for i,v in ipairs(post_rules2)
    	do 
    		if v[1] == 1 then
    		    if v[2]==rule then 
    		        return v[3]
    		        
    		    end
    		end
    	end
    end
	return nil
end


function request_check.is_type_return(is_type,rule,static)
    if is_type ~='post' and is_type~='args' and is_type~='url'  then return nil end 
	local data=""
    if static=='static' then 
        data=request_check.select_rule2(is_type,rule)
    elseif static=='ip' then 
        data=rule
    end 
    if data==nil then return nil end 
    if data=='目录保护1' or data=='目录保护2' or data=='目录保护3' then return "目录保护" end 
    if data=='PHP流协议过滤1' then return "PHP流协议" end 
    if  data=='一句话*屏蔽的关键字*过滤1' or  data=='一句话*屏蔽的关键字*过滤2' or data=='一句话木马过滤1' or data=='一句话木马过滤3' or data=='一句话*屏蔽的关键字*过滤3' or data=='菜刀流量过滤' then return 'PHP函数' end
    if data=='SQL注入过滤2' or data=='SQL注入过滤1' or data=='SQL注入过滤3' or data=='SQL注入过滤4' or data=='SQL注入过滤5' or data=='SQL注入过滤6'  then return "SQL注入"  end 
    if data=='SQL注入过滤7' or data=='SQL注入过滤9' or data=='SQL注入过滤8' or data=='SQL注入过滤10' or data=='test' then return 'SQL注入' end 
    if data=='SQL报错注入过滤01' or data=='SQL报错注入过滤02' then return 'SQL注入' end
    if data=='一句话木马过滤5' or data=='一句话木马过滤4' then return 'PHP脚本过滤' end
    if data=="" then return 'SQL注入' end
    if data=='XSS过滤1' then return 'XSS攻击' end
    if data=='ThinkPHP payload封堵' then return 'ThinkPHP攻击' end
    if data=='文件目录过滤1' or data=='文件目录过滤2' or data=='文件目录过滤3' then return '目录保护' end
    if data=='PHP脚本执行过滤1' or data=='PHP脚本执行过滤2' then return 'PHP脚本过滤' end
    return data
end


function request_check.is_ngx_match(rules,sbody,rule_name)
	local server_name =ngx.ctx.server_name

	if rules == nil or sbody == nil then return false end
	if type(sbody) == "string" then
		sbody = {sbody}
	end
	
	if type(rules) == "string" then
		rules = {rules}
	end
	for k,body in pairs(sbody)
    do 
		if request_check.continue_key(k) then
			for i,rule in ipairs(rules)
			do
				if Site_config[server_name] and rule_name then
					local n = i - 1
					for _,j in ipairs(Site_config[server_name]['disable_rule'][rule_name])
					do
						if n == j then
							rule = ""
						end
					end
				end
				if body and rule ~="" then
					if type(body) == "string" and type(rule) == "string" then
						if ngx_match(ngx.unescape_uri(body),rule,"isjo") then
						    ngx.ctx.is_type =request_check.is_type_return(rule_name,rule,"static")
							ngx.ctx.error_rule = rule .. ' >> ' .. k .. '=' .. body.. ' >> ' .. body
							return true
						end
					elseif type(body) == "string" and type(rule) == "table" then
					    if ngx_match(ngx.unescape_uri(body),rule[1],"isjo") then
							ngx.ctx.is_type =request_check.is_type_return(rule_name,rule[2],"ip")
							ngx.ctx.error_rule = rule[1] .. ' >> ' .. k .. '=' .. body.. ' >> ' .. body
							return true
						end
					end
				end
			end
		end
	end
	return false
end



function request_check.libinjection_args(requires_data)
	local server_name=ngx.ctx.server_name
	if type(requires_data)~='table' then return false,"note" end 
	for k,v in pairs(requires_data) do
		if type(v)=='string' then
			request_check.is_body_intercept(v)
			if  Config['sql_injection'] and Config['sql_injection']['open'] and  Site_config[server_name] and Site_config[server_name]['sql_injection'] and Site_config[server_name]['sql_injection']['open'] then 
        		local issqli = bt_engine.sqli("sqli",tostring(upload.ReadFileHelper4(v)))
        			if issqli then 
        			    ngx.ctx.is_type='SQL注入'
        				ngx.ctx.error_rule = '语义分析分析出sql注入' .. ' >> ' .. tostring(k)..'='..tostring(v)
        				return true,'sql'
        			end
			end 
		end 
    end
	if  Config['xss_injection'] and Config['xss_injection']['open'] and  Site_config[server_name] and Site_config[server_name]['xss_injection'] and Site_config[server_name]['xss_injection']['open'] then
		local isxss,key,value = xss_engine.parseXss(requires_data)
		if isxss then 
			ngx.ctx.is_type='XSS防御'
			ngx.ctx.error_rule = '语义分析分析出xss跨站攻击' .. ' >> ' ..tostring(key)..'='..tostring(value)
			return true,'xss'
		end
    end 
    return false,"note"
end


function request_check.is_ngx_match2(rules,sbody,rule_name)
	if rules == nil or sbody == nil then return false,ngx.ctx.is_type end
	if type(sbody) == "string" then
		sbody = {sbody}
	end
	local count =0
	local fraction=0
	if type(rules) == "string" then
		rules = {rules}
	end
	for k,body in pairs(sbody)
    do  
		if request_check.continue_key(k) then
			for i,rule in ipairs(rules)
			do
				if Site_config[ngx.ctx.server_name] and rule_name then
					local n = i - 1
					for _,j in ipairs(Site_config[ngx.ctx.server_name]['disable_rule'][rule_name])
					do
						if n == j then
							local rule = ""
						end
					end
				end
				if body and rule ~="" then
					if type(body) == "string" and type(rule) == "string" then
						if ngx_match(ngx.unescape_uri(body),rule,"isjo") then
						    ngx.ctx.is_type =request_check.is_type_return(rule_name,rule,"static")
							ngx.ctx.error_rule = rule .. ' >> ' .. k .. '=' .. body.. ' >> ' .. body
							fraction=fraction+100
							count=count+1
						end
					elseif type(body) == "string" and type(rule) == "table" then
					    if ngx_match(ngx.unescape_uri(body),rule[1],"isjo") then
						    ngx.ctx.is_type =request_check.is_type_return(rule_name,rule[2],"ip")
							ngx.ctx.error_rule = rule[1] .. ' >> ' .. k .. '=' .. body.. ' >> ' .. body
							count=count+1
							fraction=fraction+rule[3]
						end
					end
				end
			end
		end
    end
    -- if count >=2 then return true,ngx.ctx.is_type end
    if fraction >=100 then return true,ngx.ctx.is_type end
	return false,ngx.ctx.is_type
end




function request_check.deteday(cmsdata,nday_request_args)
	local flag = 0
	local count = 0
	for i ,v in pairs(cmsdata) do
	    if not nday_request_args[i] then return false end 
	    count=count+1
	    if type(nday_request_args[i])=='table' then 
	        local tmp=""
	        for i2,v2 in pairs(nday_request_args[i]) do 
	            tmp=tmp..v2
	        end 
	        nday_request_args[i]=tmp
	    end 
	    if v == "" then 
	        flag=flag+1
	    elseif v==nday_request_args[i] then 
	        flag=flag+1
	    end
	    if string.match(v, "^$_BT") then 
	        if v == "$_BT_PHPCODE"  then
	            if php_engine.php_detected(nday_request_args[i],7)==1 then 
	                flag=flag+1
	            end
	        elseif string.match(v, "^$_BT_REGEXP") then 
	            if ngx.re.find(nday_request_args[i],string.sub(v, 12),"jo") then 
	                flag=flag+1
	            end 
	        elseif string.match(v, "^$_BT_LEN") then 
	            local lencount=tonumber(string.sub(v, 9))
	            if #nday_request_args[i]==lencount then 
	                flag=flag+1
	            end 
	         elseif string.match(v, "^$_BT_START") then 
	            if ngx.re.find(nday_request_args[i],"^"..string.sub(v, 11),"jo") then 
	                flag=flag+1
	            end 
	        end
	    end 
	end 
	return flag==count
end 

function request_check.nday_detected(request_args,cmsinfo)
    if cmsinfo=="" then  return false end 
    local cms_path=BTWAF_INC.."/nday/"..cmsinfo..".lua"
    local cms_path_info =Public.read_file_body(cms_path)
    if cms_path_info ==nil then return false end
    local cmsobj=loadstring(cms_path_info)
    if type(cmsobj)~='function' then return false end
    local cmsdata=cmsobj()
    if not cmsdata["status"] then return false end
    if cmsdata["method"]~="" and ngx.ctx.method~=cmsdata["method"] then return false end 
    local nday_request_args={}
    if Public.count_sieze(request_args)==0 then return false end 
    for k,v in pairs(request_args) do 
        if type(v)~='string' then 
            nday_request_args[k]=v
        else 
             nday_request_args[k]=v
        end 
    end 
    for key,valu in pairs(ngx.req.get_headers(40)) do 
        if type(valu)=='string' then 
            nday_request_args['bt_header_'..key]=valu
        end
    end
    if ngx.ctx.method=="POST" then 
        for key,valu in pairs(ngx.req.get_uri_args(20)) do 
            if type(valu)=='string' then 
                nday_request_args['bt_args_'..key]=valu
            end
        end 
    end
    if not cmsdata["matchs"] then 
        if request_check.deteday(cmsdata["keys"],nday_request_args) then 
            ngx.ctx.is_type="通用漏洞拦截"
            IpInfo.write_log("通用漏洞拦截","拦截"..cmsdata["info"])
            Public.return_html(Config['get']['status'],BTWAF_RULES.get_html)
        end 
    else
		-- 如果keys 长度为0 则直接进入到matchs中
		if Public.count_sieze(cmsdata["keys"])==0 then
			for i,v in pairs(cmsdata["matchs"]) do 
                if request_check.deteday(v,nday_request_args) then 
                    ngx.ctx.is_type="通用漏洞拦截"
                    IpInfo.write_log("通用漏洞拦截","拦截"..cmsdata["info"])
                    Public.return_html(Config['get']['status'],BTWAF_RULES.get_html)
                end 
            end
        elseif request_check.deteday(cmsdata["keys"],nday_request_args) then 
            for i,v in pairs(cmsdata["matchs"]) do 
                if request_check.deteday(v,nday_request_args) then 
                    ngx.ctx.is_type="通用漏洞拦截"
                    IpInfo.write_log("通用漏洞拦截","拦截"..cmsdata["info"])
                    Public.return_html(Config['get']['status'],BTWAF_RULES.get_html)
                end 
            end 
        end 
    end 
end 


function request_check.cms_rule_detected(request_args,cmsdata)
	if not cmsdata then 
		return false end
    if not cmsdata["status"] then 
		return false end
    local nday_request_args={}
    if Public.count_sieze(request_args)==0 then return false end
	if cmsdata["method"]~="ALL" then if cmsdata["method"]~=ngx.ctx.method then 
		return false end end
	-- 不经过参数验证直接拦截
	if not cmsdata["check_param"] then 
		ngx.ctx.is_type="CMS专属规则"
		ngx.var.waf2monitor_blocked="CMS专属规则"
		IpInfo.write_log("通用漏洞拦截",cmsdata["cms_type"].."专属规则".." >> 拦截规则:"..cmsdata["info"].." >> 如需关闭此条规则请到 WAF页面-->专属规则-->规则ID: "..cmsdata["ruleid"])
		Public.return_html(Config['get']['status'],BTWAF_RULES.get_html)
	end
    for k,v in pairs(request_args) do 
        if type(v)~='string' then 
            nday_request_args[k]=v
        else 
             nday_request_args[k]=v
        end 
    end 
    for key,valu in pairs(ngx.req.get_headers(40)) do 
        if type(valu)=='string' then 
            nday_request_args['bt_header_'..key]=valu
        end
    end
    if ngx.ctx.method=="POST" then 
        for key,valu in pairs(ngx.req.get_uri_args(20)) do
            if type(valu)=='string' then 
                nday_request_args['bt_args_'..key]=valu
            end
        end 
    end
    if not cmsdata["matchs"] then 
        if request_check.deteday(cmsdata["keys"],nday_request_args) then 
			ngx.ctx.is_type="CMS专属规则"
			ngx.var.waf2monitor_blocked="CMS专属规则"
			IpInfo.write_log("通用漏洞拦截",cmsdata["cms_type"].."专属规则".." >> 拦截规则:"..cmsdata["info"].." >> 如需关闭此条规则请到 WAF页面->专属规则-->规则ID: "..cmsdata["ruleid"])
			Public.return_html(Config['get']['status'],BTWAF_RULES.get_html)
		end 
    else
        if request_check.deteday(cmsdata["keys"],nday_request_args) then 
            for i,v in pairs(cmsdata["matchs"]) do 
                if request_check.deteday(v,nday_request_args) then 
					ngx.ctx.is_type="CMS专属规则"
					ngx.var.waf2monitor_blocked="CMS专属规则"
					IpInfo.write_log("通用漏洞拦截",cmsdata["cms_type"].."专属规则".." >> 拦截规则:"..cmsdata["info"].." >> 如需关闭此条规则请到 WAF页面->专属规则-->规则ID: "..cmsdata["ruleid"])
					Public.return_html(Config['get']['status'],BTWAF_RULES.get_html)

				end
            end
        end
    end
end


function request_check.is_username(args,types)
	if types=="username" then
		if type(args)~='table' then 
			if BTWAF_RULES.username_top[tostring(args)]~=nil then return true end
		else
			for _,v in pairs(args) do 
				if type(v)=='string' then 
					if BTWAF_RULES.username_top[tostring(v)]~=nil then return true end
				end
			end
		end
	else 
		if type(args)~='table' then 
			if BTWAF_RULES.password[tostring(args)]~=nil then return true end
		else
			for _,v in pairs(args) do 
				if type(v)=='string' then 
					if BTWAF_RULES.password[tostring(v)]~=nil then return true end
				end
			end
		end
	end
	return false
end


function request_check.args_urlencoded(request_args)
	local server_name=ngx.ctx.server_name
    if Config['other_rule'] and Config['other_rule']['open'] and  Site_config[server_name] and Site_config[server_name]['other_rule'] and Site_config[server_name]['other_rule']['open'] then 
       	local tmp={}
    	if type(request_args)=='table' then 
    		for k,v in pairs(request_args) do 
    			if type(v)=='string' then  
    				local out=BTWAF_OBJS.decode.decode(v)
    				if out~="" then 
    					tmp[k.."decode_encode"]=out
    				end 
    			end 
				-- 如果key 不是a-zA-Z0-9_ - 的情况下 需要加入
				if not string.match(k, "^[a-zA-Z0-9_-]+$") then
					tmp[Public.generate_random_int(5)]=k
				end
    		end
			tmp=Public.process_json_args_ret(tmp)
    	end
    	for k,v in pairs(tmp)  do
            request_args[k]=v
        end
		if Config['password']~=nil and Config['password'] and (request_args['username']~=nil  or request_args['user']~=nil or request_args['account']~=nil) then 
			local is_username=false
			local is_password=false
			local pass=""
			if request_args['username'] ~=nil then if request_check.is_username(request_args['username'],"username") then is_username=true end end
			if request_args['user'] ~=nil then if request_check.is_username(request_args['user'],"username") then is_username=true end end
			if request_args['account'] ~=nil then if request_check.is_username(request_args['account'],"username") then is_username=true end end
			if is_username then
				if request_args['passwd'] ~=nil then if request_check.is_username(request_args['passwd'],"password") then is_password=true pass=request_args['passwd'] end end 
				if request_args['password'] ~=nil then if request_check.is_username(request_args['password'],"password") then is_password=true pass=request_args['password'] end  end 
				if request_args['pass'] ~=nil then if request_check.is_username(request_args['pass'],"password") then is_password=true pass=request_args['pass'] end end 
				if is_password then 
					ngx.ctx.is_type="弱密码拦截"
					ngx.var.waf2monitor_blocked="弱密码拦截"
					if type(pass)=='table' then pass=pass[1] end
					IpInfo.write_log("sql","拦截弱密码"..tostring(pass).."， 如需要关闭请在全局设置中关闭弱密码拦截")
					Public.return_html_data('网站防火墙','您的登录所使用的密码为弱密码，已被管理员拦截','您的登录所使用的密码为弱密码,拒绝访问','全局设置中关闭弱密码拦截')
				end
			end
		end
		if ngx.ctx.fastjson~=nil  and ngx.ctx.fastjson==true  or ngx.ctx.jackson~=nil and ngx.ctx.jackson==true then 
             ngx.ctx.is_type = "Java反序列化检测"
            if ngx.ctx.jackson==true then 
	            ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type.."-jackson拦截"
            elseif ngx.ctx.fastjson==true then 
                ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type.."-Fastjson拦截"
            else 
                 ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type
            end 
            ngx.var.waf2monitor_blocked="触发Java反序列化检测-Fastjson拦截"
            IpInfo.write_log("java_serialize",'ip攻击次数多被拦截11111111111')
    		Public.return_html(Config['get']['status'],BTWAF_RULES.get_html)  
    		return
        end
        local is_status,other_type=request_check.is_ngx_match_sum(BTWAF_RULES.args_rules,request_args,'args') 
        if is_status then 
            local other="other"
			if other_type == "文件包含" then
				other = "file_import"
			end
			if other_type == "PHP代码执行" then
				other = "php"
			end
			if other_type == "SQL注入" then
				other = "sql"
			end
			if other_type == "XSS攻击" then
				other = "xss"
			end
			if other_type == "命令执行" then
				other = "rce"
			end
			if other_type == "SSRF" then
				other = "ssrf"
			end
			if other_type == "通用漏洞" then
				other = "nday"
			end
			if other_type == "JAVA代码执行" then
				other = "java"
			end
			if other_type == "Java代码执行检测" then
				other = "java"
			end
			if other_type == "模板注入检测" then
				other = "template_injection"
			end
			if other_type == "Java反序列化检测" then
				other = "java_serialize"
			end
			if other_type == "PHP反序列化检测" then
				other = "php_serialize"
			end
			if other_type == "XML注入检测" then
				other = "xml_xxe"
			end
			if other_type == "ASP/ASPX代码执行检测" then
				other = "asp_aspx"
			end
			if other_type == "nodejs代码执行检测" then
				other = "nodejs"
			end
			ngx.var.waf2monitor_blocked="触发"..other_type.."拦截"
            IpInfo.write_log(other,'ip攻击次数多被拦截11111111111')
    		Public.return_html(Config['get']['status'],BTWAF_RULES.get_html)
        end 
    end 

	if ngx.ctx.cms_rule_name ~=nil then 
		if string.find(ngx.ctx.cms_rule_name,",") then 
            local cms=Public.split(ngx.ctx.cms_rule_name,',')
			if type(cms)~="table" then return false end 
            for _,v in pairs(cms) do 
                request_check.cms_rule_detected(request_args,BTWAF_CMS_OBJS[v])
            end 
        else 
            request_check.cms_rule_detected(request_args,BTWAF_CMS_OBJS[ngx.ctx.cms_rule_name])
        end
	end 
end

--检测是否为纯数字
function request_check.is_numeric(str)
	if type(str)~="string" then return false end
	if #str>100 then return false end
	--纯数字就跳过
	for i = 1, #str do
        local byte = str:byte(i)
        if byte < 48 or byte > 57 then
            return false
        end
    end
    return true
end

--检测是否为纯字母
function request_check.is_alpha(str)
	if type(str)~="string" then return false end 
	if #str>100 then return false end
	--纯字母就跳过
    for i = 1, #str do
        local byte = str:byte(i)
        if not ((byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)) then
            return false
        end
    end
    return true
end

--去掉字符串中的@符号
--@param string  字符串
--@return string 替换后的字符串
function request_check.replace_at(string)
	if not string then
		return ""
	end
	local str = string.gsub(string, "@", "")
	return str
end

--判断是否包含< > 
function request_check.is_html(str)
	if type(str)~="string" then return false end 
	for i = 1, #str do
		local byte = str:byte(i)
		if byte==60 or byte==62 then
			return true
		end
	end
	return false
end

function request_check.extract_and_decode_base64(input_str)
    if BTWAF_RULES.base64==nil then return false end 
    if not BTWAF_RULES.base64 then return false end 
	if #input_str>1000 then return "" end
    local pattern = '(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=|[A-Za-z0-9+/]{4})'
    local iterator, err = ngx.re.gmatch(input_str, pattern, "jo")
    local output = ""
    if not iterator then
        return ""
    end
	local count =0
    while true do
        local m, err = iterator()
        if err then
            break
        end
		count=count+1
		if count >7 then break end
        if m then
            local decoded_str = ngx.decode_base64(m[0])
            local flag=true
            if decoded_str then
                for i = 1, #decoded_str do
            		local byte = decoded_str:byte(i)
            	    if byte>127 or byte<33 then flag=false break end 
                end
        	    if flag then  output=output..decoded_str end 
            end
        else
            break
        end
    end
	if #output<10 then return "" end 
    return output
end


function request_check.get_lru(body)
    if type(body)=="string" and #body<100 then 
       if ngx.shared.checklru:get(body)~=nil then 
             return false
       end 
    end 
    return true
end 

-- 匹配规则并计算分数
-- @param rules 规则
-- @param sbody 请求体
-- @param rule_name 规则名称
-- @return true or false
function request_check.is_ngx_match_sum(rules, sbody, rule_name)
	if rules == nil or sbody == nil then
		return false, ngx.ctx.is_type
	end
	if type(sbody) == "string" then
		sbody = {sbody}
	end
-- 	local count = 0
	local fraction = 0
	if type(rules) == "string" then
		rules = {rules}
	end
	local is_sql=true
	if Config['sql_injection'] and Config['sql_injection']['open'] and  Site_config[ngx.ctx.server_name] and Site_config[ngx.ctx.server_name]['sql_injection'] and Site_config[ngx.ctx.server_name]['sql_injection']['open'] then 
		is_sql=false
	end 
	local is_xss=true
	if Config['xss_injection'] and Config['xss_injection']['open'] and  Site_config[ngx.ctx.server_name] and Site_config[ngx.ctx.server_name]['xss_injection'] and Site_config[ngx.ctx.server_name]['xss_injection']['open'] then 
    	is_xss=false
	end
	
	local is_rce=true
	if Config['rce_injection'] and Config['rce_injection']['open'] and  Site_config[ngx.ctx.server_name] and Site_config[ngx.ctx.server_name]['rce_injection'] and not Site_config[ngx.ctx.server_name]['rce_injection']['open'] then 
    	is_rce=false
	end

	for k, body in pairs(sbody) do
		--如果body为纯数字的情况下。则不进行检测
		if  not request_check.is_numeric(body) and not request_check.is_alpha(body)   then
			--如果是key不是白名单的时候才检测   这里是检测规则的时候调用的
			if body and  request_check.continue_key(k) and request_check.get_lru(body) then 
				for _, rule in ipairs(rules) do
					if body and rule ~= "" then
						if type(body) == "string" and type(rule) == "table" then
							if ngx_match(body, rule[1], "isjo") then
								ngx.ctx.is_type = request_check.is_type_return(rule_name, rule[2], "ip")
								ngx.ctx.error_rule = rule[1] .. " >> " .. k .. "=" .. body .. " >> " .. body
								fraction = fraction + rule[3]
							end
							
						end
						if type(body)=="table" and type(rule)=="table" then 
							for _,v in pairs(body) do
								if type(v) == "string" and ngx_match(v, rule[1], "isjo") then
									ngx.ctx.is_type = request_check.is_type_return(rule_name, rule[2], "ip")
									ngx.ctx.error_rule = rule[1] .. " >> " .. k .. "=" .. v .. " >> " .. v
									fraction = fraction + rule[3]
								end
							end
						end
					end
				end
				if fraction==0 and type(body)=="string"  and #body<100 then
				    ngx.shared.checklru:set(body,true,60)
				end 
			end
			if body and type(body)=='string' and #body>5 and string.sub(body, 1, 5)=="jdbc:" then 
			    local jdbc_infos=BTWAF_OBJS.jdbc.analyze(body)
                if jdbc_infos==100 then 
                    ngx.ctx.is_type = "Java反序列化检测"
			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type.."-JDBC反序列化" .. " >> " .. tostring(k) .. "=" .. tostring(body) .. " >> " .. tostring(body)
					fraction=100
                end 
			end
			if body  then 
			    local php_check 
			    local v2=""
			    local msg_php=""
			    if type(body) == "string" then
			        local php_status,msg2=php_engine.php_check(body,7)
					if php_status==true then 
					    php_check=true
					    v2=body
					    msg_php=msg2
					 end 
				--如果是table的情况下
				elseif type(body)=="table" then
					for _,v in pairs(body) do 
						if type(v)=="string" then 
						    local php_status,msg2=php_engine.php_check(body,7)
							if php_status==true then 
					            php_check=true
					            v2=body
					            msg_php=msg2
					            break
					       end 
						end
					end
				end
			    if php_check==true then 
			        if msg_php=="php_serialize" then
			             ngx.ctx.is_type = "PHP反序列化检测"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. " >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
    				elseif msg_php=="java_serialize" then
			             ngx.ctx.is_type = "Java反序列化检测"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. " >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
    				elseif msg_php=="ssrf" then
			             ngx.ctx.is_type = "SSRF"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. " >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
    				elseif msg_php=="fastjson" then
			             ngx.ctx.is_type = "Java反序列化检测"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. "-Fastjson反序列化 >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
					elseif msg_php=="java" then
			             ngx.ctx.is_type = "JAVA代码执行"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. "-SpEl表达式注入 >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
					elseif msg_php=="java_ognl" then
			             ngx.ctx.is_type = "JAVA代码执行"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. "-Ognl表达式注入 >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
					elseif msg_php=="log4j2" then
			             ngx.ctx.is_type = "JAVA代码执行"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. "-log4j2表达式注入 >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
					elseif msg_php=="xml_xxe" then
			             ngx.ctx.is_type = "XML注入检测"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. " >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
    				else
    			        ngx.ctx.is_type = "PHP代码执行"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. " >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
    				end 
			    end
			end 
			--语义分析的时候调用的、语法分析的时候只要触发了。就是100分
			--判断body 是否为字符串
			if body and  not is_sql then 
				local issqli,types 
				local v=""
				if type(body) == "string" then
					request_check.is_body_intercept(body)
					issqli,types = bt_engine.sqli(body)
					if issqli then v=body end
				elseif type(body)=="table" then
					for _,v in pairs(body) do 
						if type(v)=="string" then 
							issqli,types = bt_engine.sqli(request_check.replace_at(v))
							if issqli then v=body end
							if issqli then break end
						end
					end
				end
				if issqli then
					if types=="sql" then 
						ngx.ctx.is_type = "SQL注入"
					elseif types=="rce" then
						ngx.ctx.is_type = "命令执行"
						if not is_rce then return false,"rce" end 
					elseif types=="file_import" then
						ngx.ctx.is_type = "文件包含"
					elseif types=="ssrf" then
						ngx.ctx.is_type = "SSRF"
					elseif types=="xss" then
						ngx.ctx.is_type = "XSS攻击"
					elseif types=="java_eval" then
						ngx.ctx.is_type = "Java代码执行检测"
					elseif types=="template_injection" then
						ngx.ctx.is_type = "模板注入检测"
					elseif types=="asp_aspx" then
						ngx.ctx.is_type = "ASP/ASPX代码执行检测"
					elseif types=="nodejs" then
						ngx.ctx.is_type = "nodejs代码执行检测"
					else
						ngx.ctx.is_type = "SQL注入"
					end 
					ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. " >> " .. tostring(k) .. "=" .. tostring(v) .. " >> " .. tostring(v)
					fraction=100
					return true, ngx.ctx.is_type
				end
			end
		end
	end
	if fraction >= 100 then
		return true, ngx.ctx.is_type
	end
	return false, ngx.ctx.is_type
end



-- 匹配规则并计算分数
-- @param rules 规则
-- @param sbody 请求体
-- @param rule_name 规则名称
-- @return true or false
function request_check.is_ngx_match_sum_cookie(rules, sbody, rule_name)
	if rules == nil or sbody == nil then
		return false, ngx.ctx.is_type
	end
	if type(sbody) == "string" then
		sbody = {sbody}
	end
-- 	local count = 0
	local fraction = 0
	if type(rules) == "string" then
		rules = {rules}
	end
	local is_sql=true
	if Config['sql_injection'] and Config['sql_injection']['open'] and  Site_config[ngx.ctx.server_name] and Site_config[ngx.ctx.server_name]['sql_injection'] and Site_config[ngx.ctx.server_name]['sql_injection']['open'] then 
		is_sql=false
	end 

	local is_rce=true
	if Config['rce_injection'] and Config['rce_injection']['open'] and  Site_config[ngx.ctx.server_name] and Site_config[ngx.ctx.server_name]['rce_injection'] and not Site_config[ngx.ctx.server_name]['rce_injection']['open'] then 
    	is_rce=false
	end

	for k, body in pairs(sbody) do
		--如果body为纯数字的情况下。则不进行检测
		if  not request_check.is_numeric(body) and not request_check.is_alpha(body)   then
			--如果是key不是白名单的时候才检测   这里是检测规则的时候调用的
			if body and  request_check.continue_key(k) and request_check.get_lru(body) then 
				for _, rule in ipairs(rules) do
					if body and rule ~= "" then
						if type(body) == "string" and type(rule) == "table" then
							if ngx_match(body, rule[1], "isjo") then
								ngx.ctx.is_type = request_check.is_type_return(rule_name, rule[2], "ip")
								ngx.ctx.error_rule = rule[1] .. " >> " .. k .. "=" .. body .. " >> " .. body
								fraction = fraction + rule[3]
							end
							
						end
						if type(body)=="table" and type(rule)=="table" then 
							for _,v in pairs(body) do
								if type(v) == "string" and ngx_match(v, rule[1], "isjo") then
									ngx.ctx.is_type = request_check.is_type_return(rule_name, rule[2], "ip")
									ngx.ctx.error_rule = rule[1] .. " >> " .. k .. "=" .. v .. " >> " .. v
									fraction = fraction + rule[3]
								end
							end
						end
					end
				end
				if fraction==0 and type(body)=="string"  and #body<100 then
				    ngx.shared.checklru:set(body,true,60)
				end 
			end
			if body and type(body)=='string' and #body>5 and string.sub(body, 1, 5)=="jdbc:" then 
			    local jdbc_infos=BTWAF_OBJS.jdbc.analyze(body)
                if jdbc_infos==100 then 
                    ngx.ctx.is_type = "Java反序列化检测"
			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type.."-JDBC反序列化" .. " >> " .. tostring(k) .. "=" .. tostring(body) .. " >> " .. tostring(body)
					fraction=100
                end 
			end
			if body  then 
			    local php_check 
			    local v2=""
			    local msg_php=""
			    if type(body) == "string" then
			        local php_status,msg2=php_engine.php_check(body,7)
					if php_status==true then 
					    php_check=true
					    v2=body
					    msg_php=msg2
					 end 
				--如果是table的情况下
				elseif type(body)=="table" then
					for _,v in pairs(body) do 
						if type(v)=="string" then 
						    local php_status,msg2=php_engine.php_check(body,7)
							if php_status==true then 
					            php_check=true
					            v2=body
					            msg_php=msg2
					            break
					       end 
						end
					end
				end
			    if php_check==true then 
			        if msg_php=="php_serialize" then
			             ngx.ctx.is_type = "PHP反序列化检测"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. " >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
    				elseif msg_php=="java_serialize" then
			             ngx.ctx.is_type = "Java反序列化检测"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. " >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
    				elseif msg_php=="ssrf" then
			             ngx.ctx.is_type = "SSRF"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. " >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
					elseif msg_php=="fastjson" then
			             ngx.ctx.is_type = "Java反序列化检测"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. "-Fastjson反序列化 >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
					elseif msg_php=="java" then
			             ngx.ctx.is_type = "JAVA代码执行"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. "-SpEl表达式注入 >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
					elseif msg_php=="java_ognl" then
			             ngx.ctx.is_type = "JAVA代码执行"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. "-Ognl表达式注入 >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
					elseif msg_php=="log4j2" then
			             ngx.ctx.is_type = "JAVA代码执行"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. "-log4j2表达式注入 >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
					elseif msg_php=="xml_xxe" then
			             ngx.ctx.is_type = "XML注入检测"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. " >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
    				else
    			        ngx.ctx.is_type = "PHP代码执行"
    			        ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. " >> " .. tostring(k) .. "=" .. tostring(v2) .. " >> " .. tostring(v2)
    					fraction=100
    					return true, ngx.ctx.is_type
    				end 
			    end
			end 
			--语义分析的时候调用的、语法分析的时候只要触发了。就是100分
			--判断body 是否为字符串
			if body and  not is_sql then 
				local issqli,types 
				local v=""
				if type(body) == "string" then
					request_check.is_body_intercept(body)
					issqli,types = bt_engine.sqli(body)
					-- 判断XSS需要判断是否包含< > 之类的字符
					if issqli then v=body end
				--如果是table的情况下
				elseif type(body)=="table" then
					for _,v in pairs(body) do 
						if type(v)=="string" then 
							issqli,types = bt_engine.sqli(request_check.replace_at(v))
							if issqli then v=body end
							if issqli then break end
						end
					end
				end
				
				if issqli then
					if types=="sql" then 
						ngx.ctx.is_type = "SQL注入"
					elseif types=="rce" then
						ngx.ctx.is_type = "命令执行"
						if not is_rce then return false,"rce" end 
					elseif types=="file_import" then
						ngx.ctx.is_type = "文件包含"
					elseif types=="ssrf" then
						ngx.ctx.is_type = "SSRF"
					elseif types=="java_eval" then
						ngx.ctx.is_type = "Java代码执行检测"
					elseif types=="template_injection" then
						ngx.ctx.is_type = "模板注入检测"
					elseif types=="asp_aspx" then
						ngx.ctx.is_type = "ASP/ASPX代码执行检测"
					elseif types=="nodejs" then
						ngx.ctx.is_type = "nodejs代码执行检测"
					else
						ngx.ctx.is_type = "SQL注入"
					end 
					ngx.ctx.error_rule = "语义分析分析出"..ngx.ctx.is_type .. " >> " .. tostring(k) .. "=" .. tostring(v) .. " >> " .. tostring(v)
					fraction=100
					return true, ngx.ctx.is_type
				end
			end
		end
	end
	if fraction >= 100 then
		return true, ngx.ctx.is_type
	end
	return false, ngx.ctx.is_type
end


function request_check.args_urlencoded_cookie(request_args)
	local tmp={}
	if type(request_args)=='table' then 
		for k,v in pairs(request_args) do 
			if type(v)=='string' then  
				local out=BTWAF_OBJS.decode.decode(v)
				if out~="" then 
					tmp[k.."decode_encode"]=out
				end 
			end 
			-- 如果key 不是a-zA-Z0-9_ - 的情况下 需要加入
			if not string.match(k, "^[a-zA-Z0-9_-]+$") then
				tmp[Public.generate_random_int(5)]=k
			end
		end
		tmp=Public.process_json_args_ret(tmp)
	end
	for k,v in pairs(tmp)  do
		request_args[k]=v
	end
	local is_status,other_type=request_check.is_ngx_match_sum_cookie(BTWAF_RULES.args_rules,request_args,'args') 
	if is_status then 
		local other="other"
		if other_type == "文件包含" then
			other = "file_import"
		end
		if other_type == "PHP代码执行" then
			other = "php"
		end
		if other_type == "SQL注入" then
			other = "sql"
		end
		if other_type == "XSS攻击" then
			other = "xss"
		end
		if other_type == "命令执行" then
			other = "rce"
		end
		if other_type == "SSRF" then
			other = "ssrf"
		end
		if other_type == "通用漏洞" then
			other = "nday"
		end
		if other_type == "JAVA代码执行" then
			other = "java"
		end
		if other_type == "Java代码执行检测" then
			other = "java"
		end
		if other_type == "模板注入检测" then
			other = "template_injection"
		end
		if other_type == "Java反序列化检测" then
			other = "java_serialize"
		end
		if other_type == "PHP反序列化检测" then
			other = "php_serialize"
		end
		if other_type == "XML注入检测" then
			other = "xml_xxe"
		end
		if other_type == "ASP/ASPX代码执行检测" then
			other = "asp_aspx"
		end
		if other_type == "nodejs代码执行检测" then
			other = "nodejs"
		end
		ngx.var.waf2monitor_blocked="触发"..other_type.."拦截"
		IpInfo.write_log(other,'ip攻击次数多被拦截11111111111')
		Public.return_html(Config['get']['status'],BTWAF_RULES.get_html)
	end 
end


return request_check