--公共函数测试
local iresty_test    = require "iresty_test"
Json = require "cjson"
local tb = iresty_test.new({unit_name="cc"})




-- 初始化
function tb:init(  )
    self:log("init CC")
end

function tb:test_cc()
    ngx.ctx.ip="192.168.100.3"
    ngx.ctx.uri="/11.php"
    ngx.ctx.url_split="/11.php"

    ngx.ctx.limit=60
    ngx.ctx.cycle=60
    ngx.ctx.endtime=60
    ngx.ctx.retry=60
    ngx.ctx.retry_time=60
    ngx.ctx.retry_cycle=60
    ngx.ctx.site_cc=true
    --执行50次
    for i=1,59 do
        BTWAF_OBJS.cc.cc()
    end
    -- assert(BTWAF_OBJS.cc.cc()==false)

end



return tb