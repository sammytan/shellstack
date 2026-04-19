-- 未启用单元测试，跳过
-- if not UNIT_TEST_ON then
    -- return
-- end

-- 获取单元测试名称
local args = ngx.ctx.get_uri_args
if args['name'] == nil then
    ngx.say('缺少单元测试名称')
    return
end

-- 单元测试不存在
local filepath = WF_UNIT_TEST_PATH..args['name']..'_test.lua'
if not Public.file_exists(filepath) then
    ngx.say('单元测试 '..args['name']..' 不存在')
    return
end

local cms_path_info =Public.read_file_body(filepath)
if cms_path_info ==nil then return false end
local cmsobj=loadstring(cms_path_info)

cmsobj():run()