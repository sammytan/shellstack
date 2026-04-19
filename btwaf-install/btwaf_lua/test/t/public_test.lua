--公共函数测试
local iresty_test    = require "iresty_test"
Json = require "cjson"
local tb = iresty_test.new({unit_name="public"})




-- 初始化
function tb:init(  )
    self:log("init URL拦截")
end



return tb