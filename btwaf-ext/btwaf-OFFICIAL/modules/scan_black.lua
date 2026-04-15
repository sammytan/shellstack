local scan_black={}

function scan_black.scan_black()
	if not Config['scan']['open'] or not Public.is_site_config('scan') then return false end
    if ngx.ctx.cookie then  
        local cookie=ngx.ctx.cookie:get_all()
		if type(cookie)=="table" then 
		    if cookie['CustomCookie']~=nil or cookie['customcookie']~=nil or cookie['acunetixCookie']~=nil or cookie['acunetixcookie']~=nil then
		        ngx.ctx.is_type="扫描器拦截"
    			IpInfo.lan_ip('scan','扫描器拦截,已封锁IP1')
    			return true
		    end 
		end
    end 
	if ngx.re.find(ngx.ctx.request_uri,BTWAF_RULES.scan_black_rules['args'],"ijo") then
        ngx.ctx.is_type="扫描器拦截"
		ngx.var.waf2monitor_blocked="扫描器拦截"
        IpInfo.lan_ip('scan','扫描器拦截,已封锁IP2')
		return true
	end
	for key,_ in pairs(ngx.ctx.request_header)
	do  
	    if #key<100 and  ngx.shared.btwaf_data:get(key)==nil then 
    		if  ngx.re.find(key,BTWAF_RULES.scan_black_rules['header'],"ijo") then
                ngx.ctx.is_type="扫描器拦截"
    			ngx.var.waf2monitor_blocked="扫描器拦截"
                IpInfo.lan_ip('scan','扫描器拦截,已封锁IP3')
    			return true
    		end
    		ngx.shared.btwaf_data:set(key,1,60)
	    end 
	end
	return false
end

return scan_black

