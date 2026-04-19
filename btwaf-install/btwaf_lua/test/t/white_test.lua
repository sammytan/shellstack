-- 各类黑白名单测试用例
local iresty_test    = require "iresty_test"
Json = require "cjson"
local ipmatcher = require "ipmatcher"

local tb = iresty_test.new({unit_name="white"})

-- 初始化
function tb:init(  )
    self:log("init complete")
end

function tb:test_ip_white_v4()
    self:log("init test_ip_white_v4")
    ngx.ctx.ip="127.0.0.1"
    ngx.ctx.iplong=2130706433
    BTWAF_RULES.ip_white_rules=Json.decode("[[2130706433, 2130706687]]")
    assert(BTWAF_OBJS.white_balck.ip_white() == true)

    ngx.ctx.ip="192.168.10.1"
    ngx.ctx.iplong=3232238081
    assert(BTWAF_OBJS.white_balck.ip_white() == false)
end

function tb:test_ip_white_v6()
    self:log("start test_ip_white_v6")
    local ipv6_w={}
    table.insert(ipv6_w, "FF::/64")
    ngx.ctx.ip="00FF:0000:0000:0000:FFFF:FFFF:FFFF:FFFF"
    BTWAF_RULES.ipv6_white_count=1
    BTWAF_RULES.ipv6_white = ipmatcher.new(ipv6_w)
    assert(BTWAF_OBJS.white_balck.ip_white() == true)
    ngx.ctx.ip="01FF:0000:0000:0000:FFFF:FFFF:FFFF:FFFF"
    assert(BTWAF_OBJS.white_balck.ip_white() == false)
end

function tb:test_ip_black_v4()
    self:log("init test_ip_black_v4")
    ngx.ctx.ip="127.0.0.1"
    ngx.ctx.iplong=2130706433
    BTWAF_RULES.ip_black_rules=Json.decode("[[2130706433, 2130706687]]")
    -- assert(BTWAF_OBJS.white_balck.ip_black() == true)

    ngx.ctx.ip="192.168.10.1"
    ngx.ctx.iplong=3232238081
    assert(BTWAF_OBJS.white_balck.ip_black() == false)
end

function tb:test_ip_black_v6()
    self:log("start test_black_v6")
    local ipv6_w={}
    table.insert(ipv6_w, "FF::/64")
    ngx.ctx.ip="00FF:0000:0000:0000:FFFF:FFFF:FFFF:FFFF"
    BTWAF_RULES.ipv6_black_count=1
    BTWAF_RULES.ipv6_black = ipmatcher.new(ipv6_w)
    -- assert(BTWAF_OBJS.white_balck.ip_black() == true)
    ngx.ctx.ip="01FF:0000:0000:0000:FFFF:FFFF:FFFF:FFFF"
    assert(BTWAF_OBJS.white_balck.ip_black() == false)
end


function tb:test_ua_white()
    Config['ua_white']={"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36","Mozilla","Windows"}
    ngx.ctx.ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"
    assert(BTWAF_OBJS.white_balck.ua_white() == true)

    ngx.ctx.ua="windows"
    assert(BTWAF_OBJS.white_balck.ua_white() == true)

    ngx.ctx.ua="aaaazillaaaaaadsaMozilladada"
    assert(BTWAF_OBJS.white_balck.ua_white() == true)

end



function tb:test_ua_black()
    Config['ua_black']={"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36","Mozilla","Windows"}
    ngx.ctx.ua="curl /1/1"
    assert(BTWAF_OBJS.white_balck.ua_black() == false)

    ngx.ctx.ua="windows"
    -- assert(BTWAF_OBJS.white_balck.ua_black() == true)

    ngx.ctx.ua="aaaazillaaaaaadsaMozilladada"
    -- assert(BTWAF_OBJS.white_balck.ua_black() == true)

end

function tb:test_drop()
    self:log("start test_drop")
    ngx.shared.drop_ip:set("192.168.100.1",1,100)
    ngx.ctx.ip="192.168.100.2"
    assert(BTWAF_OBJS.white_balck.drop() == false)
end 


function tb:test_is_check_header()
    self:log("start test_is_check_header")
    ngx.ctx.request_header={}

    for i=0,600 do 
        table.insert(ngx.ctx.request_header,i)
    end 
    assert(BTWAF_OBJS.header.is_check_header() == false)
end 


function tb:test_reptile_entrance()
    ngx.ctx.ip="42.236.50.205"
    assert(IpInfo.reptile_entrance() == true)
    ngx.ctx.ip="42.236.10.10"
    assert(IpInfo.reptile_entrance() == false)
end 



return tb