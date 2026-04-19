-- 各类URL拦截测试
local iresty_test    = require "iresty_test"
Json = require "cjson"
local tb = iresty_test.new({unit_name="url"})




-- 初始化
function tb:init(  )
    self:log("init URL拦截")
end


function tb:test_url_find()
    ngx.ctx.ip="192.168.10.1"
    Config['uri_find']={"你好啊"}
    -- ngx.ctx.request_uri="/index.php?11=datas"
    -- assert(BTWAF_OBJS.args.url_find()==true)

    ngx.ctx.request_uri="/bbs/search.php?mod=forum&searchid=737&orderby=lastpost&ascdesc=desc&searchsubmit=yes&kw=你好"
    -- assert(BTWAF_OBJS.args.url_find()==false)
end


function tb:test_url_request_mode()
    local test="[{\"url\": \"/update\", \"type\": \"refuse\", \"mode\": {\"POST\": \"POST\", \"GET\": \"GET\", \"PUT\": \"PUT\", \"OPTIONS\": \"OPTIONS\", \"HEAD\": \"HEAD\", \"DELETE\": \"DELETE\", \"TRACE\": \"TRACE\", \"PATCH\": \"PATCH\", \"MOVE\": \"MOVE\", \"COPY\": \"COPY\", \"LINK\": \"LINK\", \"UNLINK\": \"UNLINK\", \"WRAPPED\": \"WRAPPED\", \"PROPFIND\": \"PROPFIND\", \"CONNECT\": \"CONNECT\", \"SRARCH\": \"SRARCH\"}}]"
    BTWAF_RULES.url_request=Json.decode(test)
    ngx.ctx.request_method="POST"
    ngx.ctx.uri="/update"
    ngx.ctx.url_split="/dadaupdate222"
    -- assert(BTWAF_OBJS.args.url_request_mode()==false)

    ngx.ctx.url_split="/update222"
    -- assert(BTWAF_OBJS.args.url_request_mode()==true)
end


function tb:test_header_len_check_method()
    ngx.ctx.method="POST"
    ngx.ctx.ip="192.168.6.1"
    -- Config['method_type']=Json.decode("[[\"POST\", false], [\"GET\", false], [\"PUT\", true], [\"OPTIONS\", true], [\"HEAD\", true], [\"DELETE\", true], [\"TRACE\", true], [\"PATCH\", true], [\"MOVE\", true], [\"COPY\", true], [\"LINK\", true], [\"UNLINK\", true], [\"WRAPPED\", true], [\"PROPFIND\", true], [\"PROPPATCH\", true], [\"MKCOL\", true], [\"CONNECT\", true], [\"SRARCH\", true]]")

    -- BTWAF_OBJS.header.header_len_check(ngx.ctx.request_header)

    -- assert(BTWAF_OBJS.header.method_type_check(ngx.ctx.method)==false)
end


function tb:test_cc_uri_frequency()
    self:log("init test_cc_uri_frequency")
    Config['cc_uri_frequency']["/datas"]={}
    --60秒内访问60次
    Config['cc_uri_frequency']["/datas"]["frequency"]="60"
    Config['cc_uri_frequency']["/datas"]["cycle"]="60"
    ngx.ctx.ip="192.168.100.1"
    ngx.ctx.url_split="/datas"
    --伪造60次请求
    for i=1,50 do
        -- BTWAF_OBJS.cc.cc_uri_frequency()
    end
    --验证IP是否被封
    assert(ngx.shared.drop_ip:get(ngx.ctx.ip)==nil)
    
end

--检测API拦截
--["^/api/get_info$"]
function tb:test_url_white_api()
    --已经加入URL白名单的情况下。需要对某些接口进行检测。
    Config['url_white_chekc']={"^/api/get_info$"}

    --URL白名单中添加 ["^/api"]
    BTWAF_RULES.url_white_rules={"^/api"}
    --验证是否被拦截
    ngx.ctx.request_uri="/api/get_info"
    ngx.ctx.url_split="/api/get_info"
    assert(BTWAF_OBJS.white_balck.url_white()==false)
end

-- 禁止海外
function tb:test_drop_abroad2()
    -- 
    ngx.ctx.country=IpInfo.get_country("114.114.114.114")
    --验证是否被拦截
    assert(BTWAF_OBJS.white_balck.drop_abroad()==false)
    

end


-- 禁止国内
function tb:test_drop_abroad3()
    -- 
    ngx.ctx.country=IpInfo.get_country("8.8.8.8")
    --验证是否被拦截
    assert(BTWAF_OBJS.white_balck.drop_china()==false)

    --日本DNS
    ngx.ctx.country=IpInfo.get_country("202.12.27.33")
    assert(BTWAF_OBJS.white_balck.drop_china()==false)

end


--自定义拦截地区
function tb:test_reg_tions()
    -- ngx.ctx.country=IpInfo.get_country("202.12.27.33")

    ngx.ctx.country="中国"
    BTWAF_RULES.reg_tions_rules=Json.decode("[{\"site\": {\"192.168.1.72\": \"1\"}, \"types\": \"refuse\", \"region\": {\"\\u65e5\\u672c\": \"1\"}}]")
    -- Public.logs(BTWAF_OBJS.city.reg_tions())
    assert(BTWAF_OBJS.city.reg_tions()==false)
    
end

--自定义拦截国内的城市地区
function tb:test_reg_city()
    --禁止上海访问
    BTWAF_RULES.reg_city_rules=Json.decode("[{\"site\": {\"192.168.1.72\": \"1\"}, \"types\": \"refuse\", \"region\": {\"\\u4e0a\\u6d77\": \"1\"}}]")
    ngx.ctx.ip="211.136.150.66"
    ngx.ctx.country=IpInfo.get_country("211.136.150.66")
    -- Public.logs(ngx.ctx.country)
    -- Public.logs(BTWAF_OBJS.city.reg_city())
    -- assert(BTWAF_OBJS.city.reg_city()==true)


    --只允许上海访问
    BTWAF_RULES.reg_city_rules=Json.decode("[{\"site\": {\"192.168.1.72\": \"1\"}, \"types\": \"accept\", \"region\": {\"\\u4e0a\\u6d77\": \"1\"}}]")
    ngx.ctx.ip="211.136.150.66"
    ngx.ctx.country=IpInfo.get_country("211.136.150.66")
    assert(BTWAF_OBJS.city.reg_city()==false)

    --测试浙江dns

    ngx.ctx.ip="211.140.188.188"
    ngx.ctx.country=IpInfo.get_country("211.140.188.188")
    -- assert(BTWAF_OBJS.city.reg_city()==false)
end

function tb:test_user_agent()
    ngx.ctx.ip="192.168.10.1"
    ngx.ctx.ua="user_agent"

    assert(BTWAF_OBJS.user_agent.user_agent()==false)

    
end


return tb