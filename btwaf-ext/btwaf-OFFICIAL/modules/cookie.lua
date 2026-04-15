local cookie ={}

function cookie.is_ngx_match(rules,sbody,rule_name)
	if rules == nil or sbody == nil then return false end
	if type(sbody) == "string" then
		return false
	end
	if type(rules) == "string" then
		return false
	end
	for k,body in pairs(sbody)
    do 
		for _,rule in ipairs(rules)
		do
			if body and rule ~="" then
				if type(body) == "string" and type(rule) == "string" then
					if ngx.re.find(body,rule,"ijo") then
					    ngx.ctx.is_type =BTWAF_OBJS.request_check.is_type_return(rule_name,rule,"static")
						ngx.ctx.error_rule = rule .. ' >> ' .. k .. '=' .. body.. ' >> ' .. body
						return true
					end
				end
			end
		end
	end
	return false
end

function cookie.cookie()
	if not Config['cookie']['open'] or not Public.is_site_config('cookie') then return false end
	if ngx.ctx.cookie and Check.args_urlencoded_cookie(ngx.ctx.cookie:get_all_rule()) then
	    ngx.ctx.is_type="恶意Cookie拦截"
		ngx.var.waf2monitor_blocked="恶意Cookie拦截"
		IpInfo.write_log('cookie','cookie拦截')
		Public.return_html(Config['get']['status'],BTWAF_RULES.get_html)
		return true
	end
	return false
end

return cookie