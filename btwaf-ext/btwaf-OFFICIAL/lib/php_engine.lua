local _M = {}
local bit = require "bit"
local ffi = require "ffi"

local ffi_new    = ffi.new
local ffi_string = ffi.string
local lib, loaded
ffi.cdef[[
    typedef signed char GoInt8;
    typedef unsigned char GoUint8;
    typedef short GoInt16;
    typedef unsigned short GoUint16;
    typedef int GoInt32;
    typedef unsigned int GoUint32;
    typedef long long GoInt64;
    typedef unsigned long long GoUint64;
    typedef GoInt64 GoInt;
    typedef GoUint64 GoUint;
    typedef size_t GoUintptr;
    typedef float GoFloat32;
    typedef double GoFloat64;
    typedef char _check_for_64_bit_pointer_matching_GoInt[sizeof(void*)==64/8 ? 1:-1];
    typedef struct { const char *p; ptrdiff_t n; } _GoString_;
	int CheckJava(const char *data, int length);
	int CheckXXE(const char *data, int length);
    typedef _GoString_ GoString;

    typedef void *GoMap;
    typedef void *GoChan;
    typedef struct { void *t; void *v; } GoInterface;
    typedef struct { void *data; GoInt len; GoInt cap; } GoSlice;
     GoUint8 PHPDetected(GoString path, GoInt versions);
     GoUint8 XssParse(GoString text);
    GoInt PHPCheck(GoString path, GoInt versions);
    struct NadyParse_return {
            GoUint8 r0;
            char* r1;
    };
    struct NadyParse_return NadyParse(GoString data, GoString urlinfo);
]]

local function _loadlib()
	if (not loaded) then
		local path=BTWAF_INC..'/php_engine.so'
		if WAF_SYSTEM=="arm" then 
			path=BTWAF_INC..'/php_engine_arm.so'
		end 
		local ok=false
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

function _M.php_detected(string,version)
	if (not loaded) then
		if (not _loadlib()) then
			return false
		end
	end
	if  #string>500*1024 then return false end
    local info = ffi.new("GoString", {string, #string})
	return lib.PHPDetected(info,version)
end

function _M.php_check(string,version)
    if type(string)~="string" then return false,"" end 
	if (not loaded) then
		if (not _loadlib()) then
			return false
		end
	end
	if ngx.re.match(string, [[\xAC\xED|aced|rO0AB]], "jo") then
	    if _M.check_java(string) then 
	        return true,"java_serialize"
	    end 
	end 
	if ngx.re.match(string, [[<\?xml|<!doctype|<!entity]], "ijo") then
	    if _M.check_xxe(string) then 
	        return true,"xml_xxe"
	    end 
	end 
	local php_token=ngx.md5(string.."php_check")
	if ngx.shared.checklru:get(php_token)==1 then return false,"" end 
    local info = ffi.new("GoString", {string, #string})
	local score=lib.PHPCheck(info,version)
	if score==1 then 
		return true,"php"
	elseif score==2  then 
		return true,"java"
	elseif score==3  then 
		return true,"java_ognl"
	elseif score==4  then 
		return true,"log4j2"
	elseif score==5  then 
		return true,"fastjson"
	elseif score==6  then 
		return true,"ssrf"
	elseif score>100  then 
		return true,"php_serialize"
	end
    ngx.shared.checklru:set(php_token,1,600)
    return false,""
end


function _M.check_java(string)
	if (not loaded) then
		if (not _loadlib()) then
			return false
		end
	end
	local java_token=ngx.md5(string.."java_check")
	if ngx.shared.checklru:get(java_token)==1 then return false end 
    local score=lib.CheckJava(string,#string)
    if score>=100 then 
        return true 
    end 
    ngx.shared.checklru:set(java_token,1,600)
    return false
end

-- XML XXE 
function _M.check_xxe(string)
	if (not loaded) then
		if (not _loadlib()) then
			return false
		end
	end
	local xxe_token=ngx.md5(string.."xxe_check")
	if ngx.shared.checklru:get(xxe_token)==1 then return false end 
    local score=lib.CheckXXE(string,#string)
    if score>=100 then 
        return true 
    end 
    ngx.shared.checklru:set(xxe_token,1,600)
    return false
end


function _M.xss_detected(string)
	if (not loaded) then
		if (not _loadlib()) then
			return false
		end
	end
    local goStr = ffi.new("GoString", {string, #string})
	return lib.XssParse(goStr)
end

function _M.nday_detected(str,urlinfo)
	if (not loaded) then
		if (not _loadlib()) then
			return false
		end
	end
    local data = ffi.new("GoString", {str, #str})
    local url = ffi.new("GoString", {urlinfo, #urlinfo})
    local ret = lib.NadyParse(data,url)
    return ret.r0,ffi.string(ret.r1)
end

return _M
