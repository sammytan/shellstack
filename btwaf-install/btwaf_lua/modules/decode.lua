-- decode_ngx.lua - 多层解码器 (使用ngx正则表达式)
-- 支持 base64, url, hex, unicode,xml json  解码
-- 自动识别编码类型，最多解码三层

local decode = {}
local bit = require("bit")

-- 预编译正则表达式模式以提高性能
local base64_pattern = "^[A-Za-z0-9+/]*=*$"
local url_pattern = "%[0-9A-Fa-f]{2}"
local hex_pattern = "^[0-9A-Fa-f]*$"
local unicode_pattern = "\\\\u[0-9A-Fa-f]{4}"
local xml_pattern = "<[^>]+>"

-- 尝试加载 xml2lua 库（只加载一次）
local XmlParser, XmlHandler
local xml_lib_available = false

local ok1, parser_module = pcall(require, "xml2lua.XmlParser")
local ok2, handler_module = pcall(require, "xml2lua.xmlhandler.tree")
if ok1 and ok2 then
    XmlParser = parser_module
    XmlHandler = handler_module
    xml_lib_available = true
end

-- Base64解码 (使用ngx.decode_base64)
function decode.base64_decode(str)
    if not str or str == "" then
        return nil
    end
    -- 如果是 兼容data:image/jpeg;base64,PD9waHAgcGhwaW5mbygpOz8%2B  data:image/jsp;base64,PD9waHAgcGhwaW5mbygpOz8%2B
    local prefix_match, err = ngx.re.match(str, "^data:[^;]+;base64,","jo")
    if prefix_match then
        str = ngx.re.sub(str, "^data:[^;]+;base64,", "", "jo")
    end
     -- 检查长度是否为4的倍数
    local len = #str
    if len % 4 ~= 0 then
        return nil
    end
    local match, err = ngx.re.match(str, base64_pattern, "jo")
    if not match then
        return nil
    end
    local decoded = ngx.decode_base64(str)
    if decoded==nil then 
        return nil 
    end
    
    local check_result = decode.hex_decode_and_check(decoded)
    
    if check_result then 
        return decoded 
    end
    
    return nil
end

function decode.is_visible_char(byte)
    return byte==10 or  byte >= 32 and byte <= 126
end

--url编码
function decode.url_decode(str)
    if not str or str == "" then
        return nil
    end
    local match, err = ngx.re.match(str, url_pattern, "jo")
    if not match then
        return nil
    end
    return ngx.unescape_uri(str)
end

-- 随机取可见字符数
function decode.hex_decode_and_check(decoded)
    if decoded==nil then return false end
    local s,e,f = string.byte(decoded,1,3)
    if s == 31 and  e == 139 and f==8 then
       return decoded
    end
    local sample_data = ""
    local len_decoded=#decoded 
    if len_decoded <=200 then
        sample_data = decoded
    else
        local selected_chars = {}
        local decoded_len = #decoded
        math.randomseed(os.time() + math.random(100000))
        for i = 1, 200 do
            local pos = math.random(decoded_len)
            table.insert(selected_chars, string.sub(decoded, pos, pos))
        end
        sample_data = table.concat(selected_chars)
    end
    local visible_count = 0
    for i = 1, #sample_data do
        
        if decode.is_visible_char(string.byte(sample_data, i)) then
            visible_count = visible_count + 1
        end
    end
    
    local visible_ratio = visible_count / #sample_data
    if len_decoded<=200 then return visible_ratio > 0.85 end 
    return visible_ratio > 0.75
end


-- Hex解码
function decode.hex_decode(str)
    if not str or str == "" then
        return nil
    end
    local len = #str
    if len % 2 ~= 0 then
        return nil
    end
    local match, err = ngx.re.match(str, hex_pattern, "jo")
    if not match then
        return nil
    end
    local result = {}
    local result_len = len / 2
    for i = 1, len, 2 do
        local hex_byte = tonumber(str:sub(i, i+1), 16)
        if not hex_byte then
            return nil
        end
        result[#result + 1] = string.char(hex_byte)
    end
    local result=table.concat(result)
    if decode.hex_decode_and_check(result) then return result end 
    return nil
end

-- Unicode解码
function decode.unicode_decode(str)
    if not str or str == "" then
        return nil
    end
    
    local match, err = ngx.re.match(str, unicode_pattern, "jo")
    if not match then
        return nil
    end
    local result, n, err = ngx.re.gsub(str, "\\\\u([0-9A-Fa-f]{4})", function(m)
        local code = tonumber(m[1], 16)
        if not code then return "" end
        if code < 0x80 then
            return string.char(code)
        elseif code < 0x800 then
            return string.char(0xC0 + bit.rshift(code, 6), 0x80 + bit.band(code, 0x3F))
        else
            return string.char(
                0xE0 + bit.rshift(code, 12),
                0x80 + bit.band(bit.rshift(code, 6), 0x3F),
                0x80 + bit.band(code, 0x3F)
            )
        end
    end, "jo")
    
    return err and nil or result
end


-- 递归提取XML树中的所有键值对
local function extract_xml_values(tbl, result, prefix)
    result = result or {}
    prefix = prefix or ""
    
    for k, v in pairs(tbl) do
        -- 跳过XML属性和特殊字段
        if k ~= "_attr" and k ~= "_name" and k ~= "_type" then
            local key = prefix == "" and k or (prefix .. "." .. k)
            
            if type(v) == "table" then
                -- 检查是否是数组
                if v[1] ~= nil then
                    -- 数组类型，提取每个元素
                    for i, item in ipairs(v) do
                        if type(item) == "table" then
                            extract_xml_values(item, result, key)
                        else
                            result[key] = result[key] or {}
                            table.insert(result[key], tostring(item))
                        end
                    end
                else
                    -- 递归提取嵌套的table
                    extract_xml_values(v, result, key)
                end
            else
                -- 字符串或数字值
                local value = tostring(v)
                -- 去除首尾空白
                value = ngx.re.sub(value, "^\\s+|\\s+$", "", "jo")
                if value ~= "" then
                    result[k] = value
                end
            end
        end
    end
    
    return result
end

-- XML解码 - 提取所有标签名和值
function decode.xml_decode(str)
    if not str or str == "" then
        return nil
    end
    if xml_lib_available then
        local handler = XmlHandler:new()
        local options = {
            stripWS = 1,
            expandEntities = 1,
            errorHandler = function(errMsg, pos)
                return nil
            end
        }
        local parser = XmlParser.new(handler, options)
        local success, err = pcall(function()
            parser:parse(str)
        end)
        if success and handler.root then
            local result = extract_xml_values(handler.root)
            if next(result) == nil then
                return nil
            end
            return result
        end
    end
    return nil    
end


-- 检测编码类型 - 优化检测顺序和逻辑
function decode.detect_encoding(str)
    if not str or type(str)=='string' and str == ""  then
        return nil
    end
    
    local len = #str
    -- 检测Unicode编码 (优先级最高)
    if ngx.re.match(str, unicode_pattern, "jo") then
        return "unicode"
    end
    
    -- 检测URL编码
    if ngx.re.match(str, url_pattern, "jo") then
        return "url"
    end
    
    -- 检测Hex编码 (优化检测逻辑)
    if len >= 2 and len % 2 == 0 then
        local test_str = str
        if str:sub(1, 2) == "0x" then
            test_str = str:sub(3)
        end
        
        if ngx.re.match(test_str, hex_pattern, "jo") and not ngx.re.match(str, "[+/=]", "jo") then
            return "hex"
        end
    end
    
    -- 检测Base64编码
    if len > 0 and len % 4 == 0 and ngx.re.match(str, base64_pattern, "jo") and ngx.re.match(str, "[A-Za-z]", "jo") then
        return "base64"
    end
 
    -- 兼容data:image/jpeg;base64,PD9waHAgcGhwaW5mbygpOz8%2B  data:image/jsp;base64,PD9waHAgcGhwaW5mbygpOz8%2B
    if ngx.re.match(str, "^data:[^;]+;base64,", "jo") then
        return "base64"
    end
    
    if str:sub(1, 1) == "{" and str:sub(-1) == "}" then
        return "json"
    end 
	if str:sub(1, 1) == "[" and str:sub(-1) == "]" then
        return "json"
    end
    -- 检测Gzip压缩 (魔术数字)
    local s,e,f = string.byte(str,1,3)    
    if s == 31 and e == 139 and f==8 then
       return "gzip"
    end
    -- 检测XML - 更严格的XML特征检测
    -- 检查是否包含XML声明、xmlns命名空间、或典型的XML-RPC结构
    if ngx.re.match(str, "<\\?xml\\s", "jo") or 
       ngx.re.match(str, "xmlns=", "jo") or
       ngx.re.match(str, "<methodCall>", "jo") or
       ngx.re.match(str, "<methodResponse>", "jo") or
       (ngx.re.match(str, "<[a-zA-Z][\\w:]*[^>]*>.*</[a-zA-Z][\\w:]*>", "jo") and 
        ngx.re.match(str, "<[a-zA-Z][\\w:]*\\s+[a-zA-Z]", "jo")) then
        return "xml"
    end
    

    return nil
end

function decode.json_decode(str)
    -- 验证是否为有效的JSON格式
    if not str or str == "" then
        return nil
    end
    local success, result = pcall(Json.decode, str)
    if not success then
        return nil
    end
    if type(result) ~= "table" then return nil end
    if next(result) == nil then return nil end
    if Public.arrlen(result)==0 then return nil end
    return result
end

function decode.gzip_decode(str)
    local s,e = string.byte(str,1,2)
    if s == 31 or e == 139 then
       local datas=Public.ungzipbit(str)
         return datas
    end
    return nil

end 
-- 单次解码
function decode.decode_once(str)
    local encoding_type = decode.detect_encoding(str)
    if not encoding_type then
        return nil
    end
    
    if encoding_type == "base64" then
        return decode.base64_decode(str)
    elseif encoding_type == "url" then
        return decode.url_decode(str)
    elseif encoding_type == "hex" then
        return decode.hex_decode(str)
    elseif encoding_type == "unicode" then
        return decode.unicode_decode(str)
    elseif encoding_type == "json" then
        return decode.json_decode(str)
    elseif encoding_type == "xml" then
        return decode.xml_decode(str)
    elseif encoding_type == "gzip" then
        return decode.gzip_decode(str)
    end
    
    return nil
end

-- 递归解析table中的所有字符串元素
function decode.decode_table_recursive(tbl, max_layers)
    if type(tbl) ~= 'table' then
        return tbl
    end
    
    max_layers = max_layers or 3
    
    for k, v in pairs(tbl) do
        if type(v) == 'string' and v ~= "" then
            -- 对字符串进行解码
            local decoded, path = decode.decode_multi(v, max_layers)
            if decoded and decoded ~= "" and decoded ~= v then
                tbl[k] = decoded
                -- 如果解码后又是table，继续递归
                if type(decoded) == 'table' then
                    tbl[k] = decode.decode_table_recursive(decoded, max_layers)
                end
            end
        elseif type(v) == 'table' then
            -- 递归处理嵌套的table
            tbl[k] = decode.decode_table_recursive(v, max_layers)
        end
    end
    
    return tbl
end

-- 多层解码主函数
function decode.decode_multi(input_str, max_layers)
    max_layers = max_layers or 3
    
    if not input_str or input_str == "" then
        return nil, {}
    end
    
    local current = input_str
    local decode_path = {}
    local previous_results = {} -- 缓存中间结果，避免重复计算
    
    for layer = 1, max_layers do
        local encoding_type = decode.detect_encoding(current)
        if not encoding_type then
            break
        end
        local decoded = decode.decode_once(current)
        if not decoded then
            break
        end
        if type(decoded)=='table' then
            decoded = decode.decode_table_recursive(decoded, 1)
            return decoded, decode_path
        end 
        if not decoded or decoded == current then
            break
        end
        -- 检查是否出现循环解码
        for i = 1, #previous_results do
            if previous_results[i] == decoded then
                return current, decode_path -- 避免无限循环
            end
        end
        previous_results[#previous_results + 1] = current
        decode_path[#decode_path + 1] = encoding_type
        decoded = ngx.re.gsub(decoded, "^\\s+|\\s+$", "", "jo") 
        current = decoded
    end
    
    return current, decode_path
end

-- 主解码函数 - 优化性能和逻辑
function decode.decode(input_str)
    input_str = ngx.re.gsub(input_str, "^\\s+|\\s+$", "", "jo") 
    if #input_str < 8 then return "" end 
    local result, path = decode.decode_multi(input_str, 3)
    if result==nil then return "" end 
    if type(result)=='table' then return result end 
    if type(result) ~="string" then return "" end 
    if #result ~= #input_str then
        return result
    end
    return ""
end

return decode