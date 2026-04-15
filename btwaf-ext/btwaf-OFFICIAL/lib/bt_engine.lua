local _M = {}
local ffi = require "ffi"

local lib, loaded,ok
ffi.cdef[[
 int IsCheck(const char *name,const char *buf);
int IsCheckJsp(const char *buf);
int IsCheckASP(const char *buf);
]]

_M.version = "0.1.1"
local function _loadlib()
	if (not loaded) then
		local path=BTWAF_INC..'/bt_engine.so'
		if WAF_SYSTEM=="arm" then 
			path=BTWAF_INC..'/bt_engine_arm.so'
		end
		ok,lib=pcall(function() 
		    return ffi.load(path)
		end)
		
		if not ok then 
		    lib=false
		end 

		if (lib) then
			loaded = true
			return true
		else
			return false
		end
	else
		return true
	end
end

function _M.sqli(name,string)
    local check_token=ngx.md5(name.."sqli")
    if ngx.shared.checklru:get(check_token)==1 then return false,"" end 
	if (not loaded) then
		if (not _loadlib()) then
			return false,""
		end
	end
	local is_check=lib.IsCheck(name,string)
	if is_check==1 then 
	    return true,"sql"
	elseif is_check==2 then 
	    return true,"rce"
	elseif is_check==4 then 
	    return true,"file_import"
	elseif is_check==5 then 
	    return true,"java_eval"
	elseif is_check==6 then 
	    return true,"template_injection"
	elseif is_check==7 then
		return true,"asp_aspx"
	elseif is_check==8 then
		return true,"nodejs"
	elseif is_check==10 then
		return true,"xss"
	else 
	    ngx.shared.checklru:set(check_token,1,600) 
	    return false 
	end
end

function _M.check_jsp(string)
	if (not loaded) then
		if (not _loadlib()) then
			return false,""
		end
	end
	local is_stsatu=lib.IsCheckJsp(string)
	if is_stsatu==1 then return true end
	return false
end 


function _M.check_asp(string)
	if (not loaded) then
		if (not _loadlib()) then
			return false,""
		end
	end
	local is_stsatu=lib.IsCheckASP(string)
	if is_stsatu==1 then return true end
	return false
end 


return _M