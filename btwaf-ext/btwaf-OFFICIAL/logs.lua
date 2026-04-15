local function logs_run()
	Logs.start()
	Logs.upstream_response_time()
end 

local ok,error = pcall(function()
	return logs_run()
end)


if not ok then
   if not ngx.shared.spider:get("logs_access") then 
        Public.logs(error)
        ngx.shared.spider:set("logs_access",1,180)
    end
end