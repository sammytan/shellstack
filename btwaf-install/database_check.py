# coding: utf-8
# +-------------------------------------------------------------------
# | 宝塔Linux面板 9.1.0 For CentOS/Debian/Ubuntu
# +-------------------------------------------------------------------
# | Copyright (c) 2024-2099 宝塔软件(http://bt.cn) All rights reserved.
# +-------------------------------------------------------------------
# | Author: lkq<lkq@bt.cn>
# +-------------------------------------------------------------------
# +--------------------------------------------------------------------
# |   清理数据库文件-整理数据库-防止数据库文件过大、查询慢、卡顿、最多保留10个tar.gz文件、每个文件大于500M删除
# +--------------------------------------------------------------------
import os
import totle_db2
import totle_db
import time,hashlib

def M2(table):
    with totle_db2.Sql() as sql:
        return sql.table(table)


def WriteFile(filename,s_body,mode='w+'):
    try:
        fp = open(filename, mode)
        fp.write(s_body)
        fp.close()
        return True
    except:
        try:
            fp = open(filename, mode,encoding="utf-8")
            fp.write(s_body)
            fp.close()
            return True
        except:
            return False

start_path = time.strftime("%Y-%m-%d_%H_%M_%S", time.localtime(time.time()))



#判断文件是否大于100M
path="/www/server/btwaf/totla_db/totla_db.db"
http_log="/www/server/btwaf/totla_db/http_log/"
#创建数据库
def create_db():
    #重命名文件、然后压缩
    if os.path.exists(path):
        cmd_str='''http_log=/www/server/btwaf/totla_db
mv $http_log/totla_db.db $http_log/totla_db.db.bak
tar -zcf $http_log/totla_db_{}.tar.gz $http_log/totla_db.db.bak
rm -rf $http_log/totla_db.db.bak
rm -rf $http_log/totla_db_bak.sh'''.format(start_path)
        WriteFile("/www/server/btwaf/totla_db/totla_db_bak.sh", cmd_str)
        os.system("nohup bash /www/server/btwaf/totla_db/totla_db_bak.sh >/dev/null 2>&1 &".format(start_path))
    if os.path.exists(http_log):
        cmd_str='''http_log=/www/server/btwaf/totla_db
mv $http_log/http_log $http_log/http_log_bak 
mkdir $http_log/http_log 
chown www:www $http_log/http_log
tar -zcf $http_log/http_log_{}.tar.gz $http_log/http_log_bak 
rm -rf $http_log/http_log_bak
rm -rf $http_log/http_log_bak.sh'''.format(start_path)
        WriteFile("/www/server/btwaf/totla_db/http_log_bak.sh", cmd_str)
        os.system("nohup bash /www/server/btwaf/totla_db/http_log_bak.sh >/dev/null 2>&1 &".format(start_path))
    time.sleep(1)
    # os.system("mkdir %s && chown -R www:www %s" %(http_log, http_log))
    totle_db2.Sql().execute("PRAGMA synchronous = 0")
    totle_db2.Sql().execute("PRAGMA page_size = 4096")
    totle_db2.Sql().execute("PRAGMA journal_mode = wal")
    totle_db2.Sql().execute("PRAGMA journal_size_limit = 1073741824")
    totle_db2.Sql().execute('''CREATE TABLE btwaf_msg (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				server_name TEXT,
				time INTEGER,
				time_localtime TEXT,
		)''')
    totle_db2.Sql().execute('''CREATE TABLE totla_log (
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
			)''')
    totle_db2.Sql().execute("CREATE INDEX time_inx ON totla_log(time)")
    totle_db2.Sql().execute("CREATE INDEX time_localtime_inx ON totla_log(time_localtime)")
    totle_db2.Sql().execute("CREATE INDEX server_name_inx ON totla_log(server_name)")
    totle_db2.Sql().execute("CREATE INDEX ip_ipx ON totla_log(ip)")
    totle_db2.Sql().execute("CREATE INDEX type_inx ON totla_log(type)")
    totle_db2.Sql().execute("CREATE INDEX filter__inx ON totla_log(filter_rule)")
    totle_db2.Sql().execute("CREATE INDEX ip_country_inx ON totla_log(ip_country)")

    totle_db2.Sql().execute('''CREATE TABLE blocking_ip (
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
			)''')
    totle_db2.Sql().execute("CREATE INDEX time_ip ON blocking_ip(time)")
    totle_db2.Sql().execute("CREATE INDEX time_localtime_ip ON blocking_ip(time_localtime)")
    totle_db2.Sql().execute("CREATE INDEX server_name_ip ON blocking_ip(server_name)")
    totle_db2.Sql().execute("CREATE INDEX ip_ip ON blocking_ip(ip)")
    totle_db2.Sql().execute("CREATE INDEX blocking_ip ON blocking_ip(blocking_time)")
    totle_db2.Sql().execute("CREATE INDEX is_statu_ip ON blocking_ip(is_status)")
    os.system('chown www:www /www/server/btwaf/totla_db/totla_db.db')


def Md5(strings):
    """
        @name    生成MD5
        @author hwliang<hwl@bt.cn>
        @param strings 要被处理的字符串
        @return string(32)
    """
    if type(strings) != bytes:
        strings = strings.encode()
    import hashlib
    m = hashlib.md5()
    m.update(strings)
    return m.hexdigest()



if os.path.exists(path):
    #设置文件全选为www:www
    os.system('chown www:www /www/server/btwaf/totla_db/totla_db.db')
    size = os.path.getsize(path)
    flag =False

    #遍历/www/server/btwaf/totla_db 目录 查找是否有tar.gz文件
    path_tar_list=os.listdir("/www/server/btwaf/totla_db/")
    #path_tar_list 中获取.tar.gz文件
    tmp=[]
    for i in path_tar_list:
        if i.find(".tar.gz")!=-1:
            tmp.append(i)

    #最多保留10个tar.gz文件
    if len(tmp)>120:
        tmp.sort(key=lambda x: os.path.getctime("/www/server/btwaf/totla_db/"+x))
        if os.path.exists("/www/server/btwaf/totla_db/"+tmp[0]):
            os.remove("/www/server/btwaf/totla_db/"+tmp[0])

    # 每个文件大于500M 删除
    for i in tmp:
        if not os.path.exists("/www/server/btwaf/totla_db/" + i):continue
        if os.path.getsize("/www/server/btwaf/totla_db/" + i) > 500 * 1024 * 1024:
            os.remove("/www/server/btwaf/totla_db/" + i)

    if size > 500*1024*1024:
        print("防火墙数据库文件大于500M,开始清理数据库文件、整理数据库大约1~2分钟，请稍后...")
        count = M2('totla_log').count()
        if count>200:
            start_time = time.strftime("%Y-%m-%d", time.localtime(time.time()))
            end_time = start_time
            start_time = start_time + ' 00:00:00'
            end_time2 = end_time + ' 23:59:59'
            start_timestamp = int(time.mktime(time.strptime(start_time, '%Y-%m-%d %H:%M:%S')))
            end_timestamp = int(time.mktime(time.strptime(end_time2, '%Y-%m-%d %H:%M:%S')))
            print("正在获取尾部100条数据")
            infos=[]
            for i in range(0,100,100):
                id=count-i
                id2=id-100
                info=M2('totla_log').where("id>? and id<?",(id2,id)).select()
                if type(info) == list:
                    infos+=info
            print("获取尾部100条数据完成")
            logs_path="/www/server/btwaf/totla_db/http_log/"
            disallow = []
            create_db()
            print("清理遗留的日志文件")
            if type(infos) == list:
                for i in infos:
                    if i['http_log_path']=='1' or i['http_log_path']==1:
                        disallow.append(i['http_log'])
                    else:
                        i['http_log_path']=1
                        md5=Md5(i['http_log'])
                        log_path=logs_path+md5+".txt"
                        WriteFile(log_path,i['http_log'])
                        i['http_log'] = log_path
                        disallow.append(i['http_log'])
            print("清理遗留的日志文件完成")
            print("正在重建数据库")
            print("正在插入数据")
            if type(infos) == list:
                for i in infos:
                    M2("totla_log").insert(i)
            print("插入数据完成")
            print("数据库整理完成")
        else:
            create_db()