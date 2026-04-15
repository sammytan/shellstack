local database={}

function database.btwaf_init_db()
	database.btwaf_DbReport_init()
    if DB  then return false end
    local ok ,sqlite3 = pcall(function()
        			return  require "lsqlite3"
        		end)
	if not ok then
	    return false
    end
    local path =BTWAF_DB.."/"
	if not Public.isdir(path) then Public.mkdir(path) end
	if not Public.isdir(BTWAF_RUN_PATH..'/totla_db/http_log') then 
		Public.mkdir(BTWAF_RUN_PATH..'/totla_db/http_log')
		local www_uid=Public.getUIDByUsername("www")
		if www_uid==nil then 
			Public.chown(BTWAF_RUN_PATH..'/totla_db/http_log',1000,1000)
		else
			Public.chown(BTWAF_RUN_PATH..'/totla_db/http_log',www_uid,www_uid)
		end
	end
	local db_path = path.."totla_db.db"
	if DB == nil or not DB:isopen() then
		DB = sqlite3.open(db_path)
	end
	if DB==nil then return false end 
	local table_name = "totla_db"
	local stmt = DB:prepare("SELECT COUNT(*) FROM sqlite_master where type='table' and name=?")
	local rows = 0
	if stmt ~= nil then
		stmt:bind_values(table_name)
		stmt:step()
		rows = stmt:get_uvalues()
		stmt:finalize()
	end
	if stmt == nil or rows == 0 then
		DB:exec([[PRAGMA synchronous = 0]])
		DB:exec([[PRAGMA page_size = 4096]])
		DB:exec([[PRAGMA journal_mode = wal]])
		DB:exec([[PRAGMA journal_size_limit = 1073741824]])
        DB:exec[[
			CREATE TABLE btwaf_msg (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				server_name TEXT,
				time INTEGER,
				time_localtime TEXT,
		)]]
		DB:exec[[
			CREATE TABLE totla_log (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				time INTEGER,
				time_localtime TEXT,
				server_name TEXT,
				ip TEXT,
				ip_city TEXT,
				ip_country TEXT,
				ip_subdivisions TEXT,
				ip_continent TEXT,
				ip_longitude TEXT,
				ip_latitude TEXT,
				type TEXT,
				uri TEXT,
				user_agent TEXT,
				filter_rule TEXT,
				incoming_value TEXT,
			    value_risk TEXT,
				http_log TEXT,
				http_log_path INTEGER
			)]]
            DB:exec([[CREATE INDEX id_inx ON totla_log(id)]])
            DB:exec([[CREATE INDEX time_inx ON totla_log(time)]])
            DB:exec([[CREATE INDEX time_localtime_inx ON totla_log(time_localtime)]])
            DB:exec([[CREATE INDEX server_name_inx ON totla_log(server_name)]])
            DB:exec([[CREATE INDEX ip_ipx ON totla_log(ip)]])
            DB:exec([[CREATE INDEX type_inx ON totla_log(type)]])
            DB:exec([[CREATE INDEX filter__inx ON totla_log(filter_rule)]])
            DB:exec([[CREATE INDEX ip_country_inx ON totla_log(ip_country)]])
            DB:exec[[
			CREATE TABLE blocking_ip (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
			    time INTEGER,
				time_localtime TEXT,
				server_name TEXT,
				ip TEXT,
				ip_city TEXT,
				ip_country TEXT,
				ip_subdivisions TEXT,
				ip_continent TEXT,
				ip_longitude TEXT,
				ip_latitude TEXT,
				type TEXT,
				uri TEXT,
				user_agent TEXT,
				filter_rule TEXT,
				incoming_value TEXT,
			    value_risk TEXT,
				http_log TEXT,
				http_log_path INTEGER,
				blockade TEXT,
				blocking_time INTEGER,
				is_status INTEGER
			)]]
            DB:exec([[CREATE INDEX id_ip ON blocking_ip(id)]])
            DB:exec([[CREATE INDEX time_ip ON blocking_ip(time)]])
            DB:exec([[CREATE INDEX time_localtime_ip ON blocking_ip(time_localtime)]])
            DB:exec([[CREATE INDEX server_name_ip ON blocking_ip(server_name)]])
            DB:exec([[CREATE INDEX ip_ip ON blocking_ip(ip)]])
            DB:exec([[CREATE INDEX blocking_ip ON blocking_ip(blocking_time)]])
            DB:exec([[CREATE INDEX is_statu_ip ON blocking_ip(is_status)]])
	end
end

function database.btwaf_DbReport_init()
	if DbReport  then return false end
	local ok ,sqlite3 = pcall(function()
		return  require "lsqlite3"
		end)
	if not ok then
		return false
	end
	local path =BTWAF_DB.."/"
	local db_path = path.."total_report.db"
	if DbReport == nil or not DbReport:isopen() then
		DbReport = sqlite3.open(db_path)
	end
	if DbReport==nil then return false end 
	local table_name = "request_total"
	local stmt = DbReport:prepare("SELECT COUNT(*) FROM sqlite_master where type='table' and name=?")
	local rows = 0
	if stmt ~= nil then
		stmt:bind_values(table_name)
		stmt:step()
		rows = stmt:get_uvalues()
		stmt:finalize()
	end
	if stmt == nil or rows == 0 then
		DbReport:exec([[PRAGMA synchronous = 0]])
		DbReport:exec([[PRAGMA page_size = 4096]])
		DbReport:exec([[PRAGMA journal_mode = wal]])
		DbReport:exec([[PRAGMA journal_size_limit = 1073741824]])
        DbReport:exec[[
		CREATE TABLE request_total (id INTEGER  PRIMARY KEY AUTOINCREMENT,
		date DATE,
		hour INT (3) DEFAULT (0),
		minute INT (3) DEFAULT (0),
		server_name VARCHAR (64),
		request INT (11) DEFAULT (0),
		err_502 INT (11) DEFAULT (0),
		err_499 INT (11) DEFAULT (0),
		sec_request INT (11) DEFAULT (0),
		proxy_count INT (11) DEFAULT (0),
		ip_count INT (11) DEFAULT (0),
		flow INT (11) DEFAULT (0),
		static_flow INT (11) DEFAULT (0),
		session_count INT (11) DEFAULT (0)
		)]]
		DbReport:exec([[CREATE INDEX date_new ON request_total(date)]])
	end
	local table_info = DbReport:prepare("PRAGMA table_info(request_total)")
	if table_info==nil then return end
	local ip_count_exist = false
	local flow = false
	local static_flow=false
	local session_count=false
	for row in table_info:nrows() do
		if row.name == "ip_count" then
			ip_count_exist = true
		end
		if row.name == "flow" then
			flow = true
		end
		if row.name == "static_flow" then
			static_flow = true
		end
		if row.name == "session_count" then
			session_count = true
		end
	end
	table_info:finalize()
	if not ip_count_exist then
		DbReport:exec([[ALTER TABLE request_total ADD COLUMN ip_count INT (11) DEFAULT (0)]])
	end
	if not flow then
		DbReport:exec([[ALTER TABLE request_total ADD COLUMN flow INT (11) DEFAULT (0)]])
	end
	if not static_flow then
		DbReport:exec([[ALTER TABLE request_total ADD COLUMN static_flow INT (11) DEFAULT (0)]])
	end
	if not session_count then
		DbReport:exec([[ALTER TABLE request_total ADD COLUMN session_count INT (11) DEFAULT (0)]])
	end
end 


function database.ReportInsert()
	local today,hour,minute = Public.get_pre_minute()
	for k,_ in pairs(Site_config) do
		database.get_site_req_total_sql(k,today,hour,minute)
	end
	database.get_site_req_total_sql("global",today,hour,minute)
end

function database.get_site_req_total_sql(server_name,today,hour,minute)
	if server_name ==nil  then
        return false
    end
	if server_name=="127.0.0.1" then return false end 
	if server_name=="未绑定域名" then return false end
	local date_key = today .. '_' .. hour .. '_' .. minute
	local req_key = 'req_' .. date_key
	local request = Public.logs_get(server_name,req_key)
	local err_502 = Public.logs_get(server_name,'err_502_' .. date_key)
	local err_499 = Public.logs_get(server_name,'err_499_' .. date_key)
	local static_flow = Public.logs_get(server_name,'static_flow_' .. date_key)
	local flow = Public.logs_get(server_name,'flow_' .. date_key)
	local ip_count = Public.logs_get(server_name,'ip_count_' .. date_key)
    local sec_request = Public.int(request / 60)
	local proxy_count = Public.logs_get(server_name,"proxy_count"..req_key)
	local session_count = Public.logs_get(server_name,"session_count"..req_key)

	if request == 0 and err_502 == 0 and err_499 == 0 and sec_request == 0 and proxy_count == 0 then
		return false
	end
	if DbReport==nil then return false end
	local stmt=DbReport:prepare[[insert into request_total(date,hour,minute,server_name,request,err_502,err_499,sec_request,proxy_count,ip_count,flow,static_flow,session_count) values(:date,:hour,:minute,:server_name,:request,:err_502,:err_499,:sec_request,:proxy_count,:ip_count,:flow,:static_flow,:session_count)]]
	if stmt == nil then
		return false
	end
	DbReport:exec([[BEGIN TRANSACTION]])
	stmt:bind_names{
		date=today,
		hour=hour,
		minute=minute,
		server_name=server_name,
		request=request,
		err_502=err_502,
		err_499=err_499,
		sec_request=sec_request,
		proxy_count=proxy_count,
		ip_count=ip_count,
		flow=flow,
		static_flow=static_flow,
		session_count=session_count
	}
	stmt:step()
	stmt:reset()
	stmt:finalize()
	DbReport:exec([[COMMIT]])
	return true
end

function database.totla_log_insert(is_log,server_name,ip,type,uri,user_agent,filter_rule,incoming_value,value_risk,http_log,blockade,blocking_time)
	if filter_rule==nil then filter_rule='目录保护' end
	database.btwaf_init_db()
	if DB==nil then return false end 
    local stmt2=""
	if is_log=='log' then 
		stmt2 = DB:prepare[[INSERT INTO totla_log(
    		time,time_localtime,server_name,ip, ip_city,ip_country,ip_subdivisions,ip_continent,ip_longitude,ip_latitude,type,uri,user_agent,filter_rule,incoming_value,value_risk,http_log,http_log_path) 
    		VALUES(:time,:time_localtime,:server_name,:ip,:ip_city,:ip_country,:ip_subdivisions,:ip_continent,:ip_longitude, :ip_latitude,:type,:uri,:user_agent,:filter_rule,:incoming_value,:value_risk,:http_log,:http_log_path)]]
        if stmt2 == nil then 
			Public.logs("数据库写入失败totla_log")
			DB=nil
			return
		end
	elseif is_log=='ip' then 
	        stmt2 = DB:prepare[[INSERT INTO blocking_ip(
    		time,time_localtime,server_name,ip, ip_city,ip_country,ip_subdivisions,ip_continent,ip_longitude,ip_latitude,type,uri,user_agent,filter_rule,incoming_value,value_risk,http_log,http_log_path,blockade,blocking_time,is_status) 
    		VALUES(:time,:time_localtime,:server_name,:ip,:ip_city,:ip_country,:ip_subdivisions,:ip_continent,:ip_longitude,:ip_latitude,:type,:uri,:user_agent,:filter_rule,:incoming_value,:value_risk,:http_log,:http_log_path,:blockade,:blocking_time,:is_status)]]
	    if stmt2 == nil then  
			Public.logs("数据库写入失败blocking_ip")
			DB=nil
			return
		end
	end
	DB:exec([[BEGIN TRANSACTION]])
	local get_ip_position=IpInfo.get_ip_position_data(ip)
    local ip_city=''
    local ip_country='未知位置'
    local ip_subdivisions=''
    local  ip_continent=''
    local ip_longitude=''
    local ip_latitude=''
	if get_ip_position=="3" then
	    ip_city=''
        ip_country='未知位置'
        ip_subdivisions=''
        ip_continent=''
        ip_longitude=''
        ip_latitude=''
    elseif 	get_ip_position=="2" then 
        if Public.is_internal_ip(ip) then
            ip_city=''
            ip_country='内网地址'
            ip_subdivisions=''
            ip_continent=''
            ip_longitude=''
            ip_latitude=''
        else
            ip_city=''
            ip_country='未知位置'
            ip_subdivisions=''
            ip_continent=''
            ip_longitude=''
            ip_latitude=''
        end
    else
        if get_ip_position['country'] then 
            if get_ip_position['country']['city'] then 
                ip_city=get_ip_position['country']['city']
            else
                 ip_city=''
            end 
        end
        if get_ip_position['country'] then 
            if get_ip_position['country']['country'] then 
                ip_country=get_ip_position['country']['country']
            else
                ip_country=''
            end 
        end
        
        if get_ip_position['country'] then 
            if get_ip_position['country']['province'] then 
                ip_subdivisions=get_ip_position['country']['province']
            else
                ip_subdivisions=''
            end
        end
        ip_continent=''
        if get_ip_position['country'] then 
            if get_ip_position['country']['longitude'] then 
                ip_longitude=get_ip_position['country']['longitude']
            else
                ip_longitude=''
            end 
            
        end
        if get_ip_position['country'] then 
            if get_ip_position['country']['latitude'] then 
                ip_latitude=get_ip_position['country']['latitude']
            else
                ip_latitude=''
            end 
        end
    end
	local random_token="BT_WAF_ACCESS_random"
    if Config['access_token']~=nil then 
        random_token=Config['access_token']
    end
    local http_log_path=1
    local http_log_body=""
    if ngx.req.get_method()=='POST' then
        http_log_path=1
        http_log_body=BTWAF_RUN_PATH..'/totla_db/http_log/'..ngx.md5(http_log..random_token)..'.log'
    else
        http_log_path=1
        http_log_body=BTWAF_RUN_PATH..'/totla_db/http_log/'..ngx.md5(http_log..random_token)..'.log'
    end 
        -- 如果 incoming_value 太长了
    if incoming_value~=nil and #incoming_value>210 then 
        incoming_value=incoming_value:sub(1, 200)
    end 
    if user_agent~=nil and  #user_agent>210 then 
        user_agent=user_agent:sub(1,200)
    end 
    
    if is_log=='log' then 
    	stmt2:bind_names{
    		time=os.time(),
    		time_localtime=ngx.localtime(),
    		server_name=server_name,
    	    ip=ip,
    	    ip_city=ip_city,
    	    ip_country=ip_country,
    	    ip_subdivisions=ip_subdivisions,
    	    ip_continent=ip_continent,
    	    ip_longitude=ip_longitude,
    	    ip_latitude=ip_latitude,
    	    type=type,
    	    uri=uri,
    	    user_agent=user_agent,
    	    filter_rule=filter_rule,
    	    incoming_value=incoming_value,
    	    value_risk=value_risk,
    	    http_log=http_log_body,
    	    http_log_path=http_log_path
    	}
    elseif is_log=='ip' then 
        stmt2:bind_names{
    		time=os.time(),
    		time_localtime=ngx.localtime(),
    		server_name=server_name,
    	    ip=ip,
    	    ip_city=ip_city,
    	    ip_country=ip_country,
    	    ip_subdivisions=ip_subdivisions,
    	    ip_continent=ip_continent,
    	    ip_longitude=ip_longitude,
    	    ip_latitude=ip_latitude,
    	    type=type,
    	    uri=uri,
    	    user_agent=user_agent,
    	    filter_rule=filter_rule,
    	    incoming_value=incoming_value,
    	    value_risk=value_risk,
    	    http_log=http_log_body,
    	    http_log_path=http_log_path,
    	    blockade=blockade,
    	    blocking_time=blocking_time,
    	    is_status=true
	    }
    end 
    
	stmt2:step()
	stmt2:reset()
	stmt2:finalize()
	DB:execute([[COMMIT]])
	if http_log_path==1 then 
    	local filename = http_log_body
    	local fp = io.open(filename,'wb')
    	if fp == nil then return false end
    	local logtmp = {http_log}
    	local logstr = Json.encode(logtmp)
    	fp:write(logstr)
    	fp:flush()
    	fp:close()
    end
end

function database.btwaf_monitor_init()
	-- if Dbmonitor  then return false end
	local Dbmonitor=nil
	local ok ,sqlite3 = pcall(function()
		return  require "lsqlite3"
		end)
	if not ok then
		return nil
	end
	local path =BTWAF_DB.."/"
	local db_path = path.."total_monitor.db"
	if Dbmonitor == nil or not Dbmonitor:isopen() then
		Dbmonitor = sqlite3.open(db_path)
	end
	if Dbmonitor==nil then return nil end 
	local table_name = "ip_total"
	local stmt = Dbmonitor:prepare("SELECT COUNT(*) FROM sqlite_master where type='table' and name=?")
	local rows = 0
	if stmt ~= nil then
		stmt:bind_values(table_name)
		stmt:step()
		rows = stmt:get_uvalues()
		stmt:finalize()
	end
	if stmt == nil or rows == 0 then
		Dbmonitor:exec([[PRAGMA synchronous = 1]])
		Dbmonitor:exec([[PRAGMA page_size = 4096]])
		Dbmonitor:exec([[PRAGMA journal_mode = wal]])
		Dbmonitor:exec([[PRAGMA journal_size_limit = 1073741824]])
		Dbmonitor:exec([[PRAGMA wal_autocheckpoint = 500]])
        Dbmonitor:exec[[
		CREATE TABLE ip_total (id INTEGER  PRIMARY KEY AUTOINCREMENT,
		date DATE,
		server_name VARCHAR (128),
		ip VARCHAR (128),
		count INT (11) DEFAULT (0),
		static_count INT (11) DEFAULT (0),
		traffic INT (11) DEFAULT (0),
		static_traffic INT (11) DEFAULT (0),
		session_count INT (11) DEFAULT (0)
		)]]
		Dbmonitor:exec([[CREATE INDEX date_new ON ip_total(date)]])
		Dbmonitor:exec([[CREATE INDEX ip_new ON ip_total(ip)]])

        Dbmonitor:exec[[
		CREATE TABLE url_total (id INTEGER  PRIMARY KEY AUTOINCREMENT,
		date DATE,
		server_name VARCHAR (128),
		url VARCHAR (255),
		content_type VARCHAR (128),
		count INT (11) DEFAULT (0),
		static_count INT (11) DEFAULT (0),
		traffic INT (11) DEFAULT (0),
		static_traffic INT (11) DEFAULT (0),
		session_count INT (11) DEFAULT (0)
		)]]
		Dbmonitor:exec([[CREATE INDEX url_total_new ON url_total(date)]])
	end
	local table_info = Dbmonitor:prepare("PRAGMA table_info(ip_total)")
	if table_info~=nil then 
		local session_count = false
		for row in table_info:nrows() do
			if row.name == "session_count" then
				session_count=true
			end 
		end 
		table_info:finalize()
		if not session_count then
			Dbmonitor:exec([[ALTER TABLE ip_total ADD COLUMN session_count INT (11) DEFAULT (0)]])
		end
	end
	local table_info2 = Dbmonitor:prepare("PRAGMA table_info(url_total)")
	if table_info2~=nil then 
		local session_count = false
		for row in table_info2:nrows() do
			if row.name == "session_count" then
				session_count=true
			end 
		end 
		table_info2:finalize()
		if not session_count then
			Dbmonitor:exec([[ALTER TABLE url_total ADD COLUMN session_count INT (11) DEFAULT (0)]])
		end
	end

	return Dbmonitor
end

function database.ip_total_insert()
	local Dbmonitor=database.btwaf_monitor_init()
	if Dbmonitor==nil then return false end
	local tmp_list={}
	local today,hour,minute = Public.get_pre_minute()
	for k,_ in pairs(Site_config) do
		tmp_list[k]=true
	end
	local local_time=ngx.time()
	local today_expire_time = Public.get_today_end_time_logs() - local_time
	local keys = ngx.shared.ip:get_keys(100000) 
	if keys==nil then return false end
	local insert_count=0
	for i, key in ipairs(keys) do
		local key_value=Public.split(key,"|")
		if key_value and Public.arrlen(key_value)==2 then 
			local ip=key_value[1]
			local server_name=key_value[2]
			if tmp_list[server_name] then 
				local values=ngx.shared.ip:get(key)
				local values_data=Public.split(values,"|")
				if values_data and Public.arrlen(values_data)>5 then
					local count =tonumber(values_data[1])
					local static=tonumber(values_data[2])
					local traffic=tonumber(values_data[3])
					local static_traffic=tonumber(values_data[4])
					local session_count=tonumber(values_data[5])
					local update_time=tonumber(values_data[6])
					if  (count-static>100 and traffic-static_traffic>524288) or  (static>500 and static_traffic>524288) or count>500 or static_traffic>10*1024*1024 or traffic-static_traffic>3*1024*1024 then
						insert_count=insert_count+1
						database.get_ip_total_sql(Dbmonitor,today,server_name,ip,count,static,traffic,static_traffic,session_count)
						ngx.shared.ip:set(key,"0|0|0|0|0|"..local_time,today_expire_time)
					elseif local_time-update_time>600 and traffic<1024*1024 and count<100 then
						ngx.shared.ip:delete(key)
					elseif local_time-update_time>1200 then
						ngx.shared.ip:delete(key)
					end
				else
					ngx.shared.ip:delete(key)
				end 
			end 
		end 
	end

	for k,_ in pairs(tmp_list) do
		local server_name_ip_top1000=database.ip_top1000(Dbmonitor,today,k)
		if server_name_ip_top1000~=nil then 
			for ip,value in pairs(server_name_ip_top1000) do
				local count=value["count"]
				local traffic=value["traffic"]
				local token=ip.."|"..k
				if count>50  then 
					ngx.shared.spider:set(token,count,360)
					ngx.shared.spider:set(token.."|traffic",traffic,360)
				end
			end
		end
	end
	if insert_count>=1 and Dbmonitor~=nil then 
		Dbmonitor:exec("PRAGMA wal_checkpoint(FULL);")
        Dbmonitor:exec("PRAGMA wal_checkpoint(TRUNCATE);")
	end 
	Dbmonitor:close()
end

function database.ip_top1000(Dbmonitor,today,server_name)
	if Dbmonitor==nil then return nil end
	local ip_list={}
	local stmt=Dbmonitor:prepare("SELECT ip,count,traffic from ip_total where date=? and server_name=? order by count desc limit 500")
	if stmt == nil then
		return nil
	end
	stmt:bind_values(today,server_name)
	for row in stmt:nrows() do
		if row.ip~=nil and row.count~=nil then 
			ip_list[row.ip]={}
			ip_list[row.ip]["count"]=row.count
			ip_list[row.ip]["traffic"]=row.traffic
		end
	end
	stmt:finalize()
	return ip_list
end


function database.get_ip_total_sql(Dbmonitor,today,server_name,ip,count,static,traffic,static_traffic,session_count)
	if server_name=="127.0.0.1" then return false end 
	if server_name=="未绑定域名" then return false end
	if Dbmonitor==nil then return false end
	local rows = 0
	local stmt_sel=Dbmonitor:prepare("SELECT COUNT(*) FROM ip_total where date=? and server_name=? and ip=?")
	if stmt_sel ~= nil then
		stmt_sel:bind_values(today,server_name,ip)
		stmt_sel:step()
		rows = stmt_sel:get_uvalues()
		stmt_sel:finalize()
	end
	if stmt_sel == nil then
		return
	end
	if rows>0 then
		local stmt_up=Dbmonitor:prepare[[update ip_total set count=count+:count,static_count=static_count+:static_count,traffic=traffic+:traffic,static_traffic=static_traffic+:static_traffic,session_count=session_count+:session_count where date=:date and server_name=:server_name and ip=:ip]]
		if stmt_up == nil then
			return
		end 
		Dbmonitor:exec([[BEGIN TRANSACTION]])
		stmt_up:bind_names{
			date=today,
			server_name=server_name,
			ip=ip,
			count=count,
			static_count=static,
			traffic=traffic,
			static_traffic=static_traffic,
			session_count=session_count
		}
		stmt_up:step()
		Dbmonitor:exec([[COMMIT]])
		stmt_up:reset()
		stmt_up:finalize()
		return
	end
	local stmt2=Dbmonitor:prepare[[insert into ip_total(date,server_name,ip,count,static_count,traffic,static_traffic,session_count) values(:date,:server_name,:ip,:count,:static_count,:traffic,:static_traffic,:session_count)]]
	if stmt2 == nil then
		return
	end
    Dbmonitor:exec([[BEGIN TRANSACTION]])
	stmt2:bind_names{
		date=today,
		server_name=server_name,
		ip=ip,
		count=count,
		static_count=static,
		traffic=traffic,
		static_traffic=static_traffic,
		session_count=session_count
	}
	stmt2:step()
	Dbmonitor:exec([[COMMIT]])
	stmt2:reset()
	stmt2:finalize()
end

function database.url_total_insert()
	local Dbmonitor=database.btwaf_monitor_init()
	if Dbmonitor==nil then return false end
	local tmp_list={}
	for k,_ in pairs(Site_config) do
		tmp_list[k]=true
	end
	local today,hour,minute = Public.get_pre_minute()
	local local_time=ngx.time()
	local today_expire_time = Public.get_today_end_time_logs() - local_time
	local keys = ngx.shared.url:get_keys(50000)
	if keys==nil then return false end
	for i, key in ipairs(keys) do
		local key_value=Public.split(key,"|")
		if key_value and Public.arrlen(key_value)==2 then 
			local server_name=key_value[1]
			local url=key_value[2]
			if tmp_list[server_name] then 
				local values=ngx.shared.url:get(key)
				local values_data=Public.split(values,"|")
				if values_data and Public.arrlen(values_data)>6 then
					local count=tonumber(values_data[1])
					local static_count=tonumber(values_data[2])
					local traffic=tonumber(values_data[3])
					local static_traffic=tonumber(values_data[4])
					local session_count=tonumber(values_data[5])
					local update_time=tonumber(values_data[6])
					local content_type=values_data[7]
					if traffic>1024*1024 and count>100 then 
						database.get_url_total_sql(Dbmonitor,today,server_name,url,count,static_count,traffic,static_traffic,content_type,session_count)
						ngx.shared.url:set(key,"0|0|0|0|0|"..local_time.."|",today_expire_time)
					elseif count>2000 then 
						database.get_url_total_sql(Dbmonitor,today,server_name,url,count,static_count,traffic,static_traffic,content_type,session_count)
						ngx.shared.url:set(key,"0|0|0|0|0|"..local_time.."|",today_expire_time)
					elseif local_time-update_time>600 and traffic<1024*1024 and count<100 then
						ngx.shared.url:delete(key)
					elseif local_time-update_time>1200 then 
						ngx.shared.url:delete(key)
					end
				else
					ngx.shared.url:delete(key)
				end 
			end 
		end 
	end 
	Dbmonitor:close()
end

function database.get_url_total_sql(Dbmonitor,today,server_name,url,count,static_count,traffic,static_traffic,content_type,session_count)
	if server_name=="127.0.0.1" then return false end 
	if server_name=="未绑定域名" then return false end
	if Dbmonitor==nil then return false end
	local rows = 0
	local stmt_sel=Dbmonitor:prepare("SELECT COUNT(*) FROM url_total where date=? and server_name=? and url=?")
	if stmt_sel ~= nil then
		stmt_sel:bind_values(today,server_name,url)
		stmt_sel:step()
		rows = stmt_sel:get_uvalues()
		stmt_sel:finalize()
	end
	if stmt_sel == nil then
		return
	end
	if rows>0 then
		local stmt_up=Dbmonitor:prepare[[update url_total set count=count+:count,static_count=static_count+:static_count,traffic=traffic+:traffic,static_traffic=static_traffic+:static_traffic,session_count=session_count+:session_count where date=:date and server_name=:server_name and url=:url]]
		if stmt_up == nil then
			return
		end 
		Dbmonitor:exec([[BEGIN TRANSACTION]])
		stmt_up:bind_names{
			date=today,
			server_name=server_name,
			url=url,
			count=count,
			static_count=static_count,
			traffic=traffic,
			static_traffic=static_traffic,
			session_count=session_count
		}
		stmt_up:step()
		stmt_up:reset()
		Dbmonitor:exec([[COMMIT]])
		stmt_up:finalize()
		return
	end
	local stmt2=Dbmonitor:prepare[[insert into url_total(date,server_name,url,count,static_count,traffic,static_traffic,content_type,session_count) values(:date,:server_name,:url,:count,:static_count,:traffic,:static_traffic,:content_type,:session_count)]]
	if stmt2 == nil then
		return
	end

	if content_type=="" then 
		local end_fix=Public.get_end_fix(url)
		if Logs.static_ext[end_fix]~=nil then 
			content_type=Logs.static_ext[end_fix]
		else
			content_type="text/html"
		end
	end

	Dbmonitor:exec([[BEGIN TRANSACTION]])
	stmt2:bind_names{
		date=today,
		server_name=server_name,
		url=url,
		count=count,
		static_count=static_count,
		traffic=traffic,
		static_traffic=static_traffic,
		content_type=content_type,
		session_count=session_count
	}
	stmt2:step()
	Dbmonitor:exec([[COMMIT]])
	stmt2:reset()
	stmt2:finalize()
end


-- 获取当前小时的+前一天小时的平均值
function database.get_total_report(DbReport,server_name)
	if DbReport==nil then return nil end
	local stmt=DbReport:prepare("select request,ip_count,flow,static_flow from request_total where server_name=? and hour=? and  (date=? or date=?)")
	if stmt == nil then
		return nil
	end
	local time_str = ngx.localtime()
    local hour  = tonumber(string.sub(time_str, 12, 13))
	local get_yesterday=os.date("%Y-%m-%d", os.time() - 86400)
	stmt:bind_values(server_name,hour,ngx.today(),get_yesterday)
	local total_request=0
	local total_ip_count=0
	local total_flow=0
	local total_static_flow=0
	local total_count=0
	local count=0
	local request_max=0
	for row in stmt:nrows() do
		count=count+1
		if row.request~=nil then 
			total_request=total_request+row.request
			total_count=total_count+1
			-- 找到请求数的最大值
			if row.request>request_max then 
				request_max=row.request
			end 
		end
		if row.ip_count~=nil then 
			total_ip_count=total_ip_count+row.ip_count
		end
		if row.flow~=nil then 
			total_flow=total_flow+row.flow
		end
		if row.static_flow~=nil then 
			total_static_flow=total_static_flow+row.static_flow
		end
		

	end
	stmt:finalize()
	-- 如果count
	if count<60 then return nil end
	-- 如果 total_count 等于0 则直接返回nil
	if total_count==0 then return nil end
	local avg_request=Public.int(total_request/count)
	local avg_ip_count=Public.int(total_ip_count/count)
	local avg_flow=Public.int(total_flow/count)
	local avg_static_flow=Public.int(total_static_flow/count)
	return {avg_request=avg_request,avg_ip_count=avg_ip_count,avg_flow=avg_flow,avg_static_flow=avg_static_flow,request_max=request_max}
end


function database.get_total_report_hour()
	if DbReport==nil then database.btwaf_DbReport_init() end
	if DbReport==nil then return false end
	for k,_ in pairs(Site_config) do
		if Site_config[k]~=nil and Site_config[k]['smart_cc']~=nil and Site_config[k]['smart_cc']['open']~=nil and Site_config[k]['smart_cc']['open']==true then 
			local report_data=database.get_total_report(DbReport,k)
			if report_data~=nil then 
				local cache_key="total_report_"..k
				ngx.shared.spider:set(cache_key,Json.encode(report_data),3600)
			end
		end
	end
end

return database