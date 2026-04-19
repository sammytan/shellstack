# coding: utf-8
import sys, time

sys.path.append('/www/server/panel/class')
import json, os


def ReadFile(filename, mode='r'):
    """
    读取文件内容
    @filename 文件名
    return string(bin) 若文件不存在，则返回None
    """
    import os
    if not os.path.exists(filename): return False
    fp = None
    try:
        fp = open(filename, mode)
        f_body = fp.read()
    except Exception as ex:
        if sys.version_info[0] != 2:
            try:
                fp = open(filename, mode, encoding="utf-8", errors='ignore')
                f_body = fp.read()
            except:
                fp = open(filename, mode, encoding="GBK", errors='ignore')
                f_body = fp.read()
        else:
            return False
    finally:
        if fp and not fp.closed:
            fp.close()
    return f_body


def WriteFile(filename, s_body, mode='w+'):
    """
    写入文件内容
    @filename 文件名
    @s_body 欲写入的内容
    return bool 若文件不存在则尝试自动创建
    """
    try:
        fp = open(filename, mode)
        fp.write(s_body)
        fp.close()
        return True
    except:
        try:
            fp = open(filename, mode, encoding="utf-8")
            fp.write(s_body)
            fp.close()
            return True
        except:
            return False


def untar():
    import os, tarfile
    if os.path.exists("/www/server/panel/plugin/btwaf/nginx_btwaf_xss"):
        os.system("rm -rf /www/server/panel/plugin/btwaf/nginx_btwaf_xss")
    # 指定tar.gz文件路径
    tar_gz_path = '/www/server/panel/plugin/btwaf/nginx_btwaf_xss.tar.gz'
    if not os.path.exists(tar_gz_path): return False
    # 解压的目标文件夹
    extract_path = '/www/server/panel/plugin/btwaf/'
    # 打开tar.gz文件
    with tarfile.open(tar_gz_path, "r:gz") as tar:
        # 获取tar归档中的所有成员
        members = tar.getmembers()
        # 依次处理每个成员
        for member in members:
            # 打印文件名
            # 可以在这里添加额外的处理代码，例如提取某些文件，检查文件属性等
            if member.name == "nginx_btwaf_xss":
                # 解压文件
                tar.extract(member, extract_path)
    if os.path.exists("/dev/shm/xss_decode.sock"):
        os.system("rm -f /dev/shm/xss_decode.sock")
    # 判断文件
    # 删除压缩包
    os.system("rm -f " + tar_gz_path)
    file = "/www/server/panel/plugin/btwaf/nginx_btwaf_xss"
    if not os.path.exists(file):
        return False
    # 小于20M直接删除文件
    if os.path.getsize(file) < 20971520:
        os.system("rm -f " + file)
        return False


def untar_arm():
    import os, tarfile
    if os.path.exists("/www/server/btwaf/inc/bt_engine_arm.so"):
        os.remove("/www/server/btwaf/inc/bt_engine_arm.so")
    if os.path.exists("/www/server/btwaf/inc/php_engine_arm.so"):
        os.remove("/www/server/btwaf/inc/php_engine_arm.so")
    if os.path.exists("/www/server/btwaf/inc/libmaxminddb_arm.so"):
        os.remove("/www/server/btwaf/inc/libmaxminddb_arm.so")
    # 指定tar.gz文件路径
    tar_gz_path = '/www/server/btwaf/inc/arm.so.tar.gz'
    if not os.path.exists(tar_gz_path): return False
    # 解压的目标文件夹
    extract_path = '/www/server/btwaf/inc/'
    # 打开tar.gz文件
    with tarfile.open(tar_gz_path, "r:gz") as tar:
        # 获取tar归档中的所有成员
        members = tar.getmembers()
        # 依次处理每个成员
        for member in members:
            if member.name == "bt_engine_arm.so":
                tar.extract(member, extract_path)
            if member.name == "php_engine_arm.so":
                tar.extract(member, extract_path)
            if member.name == "libmaxminddb_arm.so":
                tar.extract(member, extract_path)                
    # 判断文件
    os.remove(tar_gz_path)
    file = "/www/server/btwaf/inc/bt_engine_arm.so"
    if not os.path.exists(file):
        return False
    # 小于20M直接删除文件
    if os.path.getsize(file) < 1024*1024:
        os.remove(file)
        return False




def untar_GeoLite2():
    print("正在更新IP库")
    import os, tarfile
    if os.path.exists("/www/server/panel/plugin/btwaf/GeoLite2-City.mmdb"):
        os.system("rm -rf /www/server/panel/plugin/btwaf/GeoLite2-City.mmdb")
    # 指定tar.gz文件路径
    tar_gz_path = '/www/server/panel/plugin/btwaf/GeoLite2-City.mmdb.tar.gz'
    if not os.path.exists(tar_gz_path): return False
    # 解压的目标文件夹
    extract_path = '/www/server/panel/plugin/btwaf/'
    # 打开tar.gz文件
    with tarfile.open(tar_gz_path, "r:gz") as tar:
        # 获取tar归档中的所有成员
        members = tar.getmembers()
        # 依次处理每个成员
        for member in members:
            # 打印文件名
            # 可以在这里添加额外的处理代码，例如提取某些文件，检查文件属性等
            if member.name == "GeoLite2-City.mmdb":
                # 解压文件
                tar.extract(member, extract_path)
    # 判断文件
    # 删除压缩包
    os.system("rm -f " + tar_gz_path)
    file = "/www/server/panel/plugin/btwaf/GeoLite2-City.mmdb"
    if not os.path.exists(file):
        os.system(
            "mv -f  /www/server/panel/plugin/btwaf/GeoLite2-City-reduce.mmdb /www/server/btwaf/inc/GeoLite2-City.mmdb")
        return False
    # 小于1
    if os.path.getsize(file) < 1 * 1024 * 1024:
        os.system("rm -f " + file)
        os.system(
            "mv -f  /www/server/panel/plugin/btwaf/GeoLite2-City-reduce.mmdb /www/server/btwaf/inc/GeoLite2-City.mmdb")
        return False

    # 计算/www/server/btwaf/inc/GeoLite2-City.mmdb 大小
    if not os.path.exists("/www/server/btwaf/inc/GeoLite2-City.mmdb"):
        # 复制文件过去
        os.system("cp -f /www/server/panel/plugin/btwaf/GeoLite2-City.mmdb /www/server/btwaf/inc/GeoLite2-City.mmdb")
    else:
        # 计算文件大小判断是否一直
        if os.path.getsize("/www/server/panel/plugin/btwaf/GeoLite2-City.mmdb") != os.path.getsize(
                "/www/server/btwaf/inc/GeoLite2-City.mmdb"):
            os.system(
                "cp -f /www/server/panel/plugin/btwaf/GeoLite2-City.mmdb /www/server/btwaf/inc/GeoLite2-City.mmdb")
    # 删除文件
    os.system("rm -f /www/server/panel/plugin/btwaf/GeoLite2-City.mmdb")
    #
    os.system("rm -f /www/server/panel/plugin/btwaf/GeoLite2-City-reduce.mmdb")
    time.sleep(1)
    print("更新IP库完成")


def get_task():
    path = "/var/spool/cron/crontabs/root"
    if not os.path.exists(path):
        path = "/var/spool/cron/root"
    if not os.path.exists(path):
        return
    # 读取文件 一行一个
    f = open(path)
    root_info = f.readlines()
    f.close()
    # 去除空格
    data = [i.strip() for i in root_info]
    # 如果开头不是*/10 就跳过
    data = [i for i in data if i.startswith("*/10")]
    # 判断长度
    if len(data) == 1:
        return
    # 如果大于2个就读取文件判断一下
    tmp = []
    if len(data) > 2:
        # 只读取
        for i in data:
            i2 = i.split()
            if len(i2) < 6: continue
            path_i = i2[5]
            if not os.path.exists(path_i): continue
            infos = ReadFile(path_i)
            if '/www/server/panel/plugin/btwaf/webshell_check.py' in infos:
                tmp.append(i)

    if len(tmp) > 1:
        os.system("chattr -i " + path)
        root_msg = ReadFile(path)
        tmp = tmp[:-1]
        for i in tmp:
            root_msg = root_msg.replace(i + "\n", "")
            root_msg = root_msg.replace(i, "")
        WriteFile(path, root_msg)


def GetRandomString(length):
    """
       @name 取随机字符串
       @author hwliang<hwl@bt.cn>
       @param length 要获取的长度
       @return string(length)
    """
    from random import Random
    strings = ''
    chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz0123456789'
    chrlen = len(chars) - 1
    random = Random()
    for i in range(length):
        strings += chars[random.randint(0, chrlen)]
    return strings


def check_rule():
    '''
        @name 检查各项配置文件是否为json格式
    :return:
    '''
    config = {
        "scan": {
            "status": 444,
            "ps": "过滤常见扫描测试工具的渗透测试",
            "open": True,
            "reqfile": ""
        },
        "cc": {
            "status": 444,
            "ps": "过虑CC攻击",
            "increase": True,
            "limit": 120,
            "endtime": 7200,
            "open": True,
            "reqfile": "",
            "cycle": 60
        },
        "share_ip": True,
        "logs_path": "/www/wwwlogs/btwaf",
        "open": True,
        "reqfile_path": "/www/server/btwaf/html",
        "retry": 20,
        "log": True,
        "access_token": GetRandomString(32),
        "session_token": GetRandomString(64),
        "cc_token": GetRandomString(64),
        "token_time": int(time.time()),
        "cc_automatic": False,
        "user-agent": {
            "status": 403,
            "ps": "通常用于过滤浏览器、蜘蛛及一些自动扫描器",
            "open": True,
            "reqfile": "user_agent.html"
        },
        "other": {
            "status": 403,
            "ps": "其它非通用过滤",
            "reqfile": "other.html"
        },
        "uri_find": [],
        "cc_retry_cycle": "600",
        "cc_time": "60",
        "ua_black": [],
        "drop_abroad": {
            "status": 444,
            "ps": "禁止中国大陆以外的地区访问站点",
            "open": True,
            "reqfile": ""
        },
        "retry_cycle": 120,
        "get": {
            "status": 403,
            "ps": "过滤uri、uri参数中常见sql注入、xss等攻击",
            "open": True,
            "reqfile": "get.html"
        },
        "body_character_string": [],
        "start_time": 0,
        "cookie": {
            "status": 403,
            "ps": "过滤利用Cookie发起的渗透攻击",
            "open": True,
            "reqfile": "cookie.html"
        },
        "retry_time": 86400,
        "post": {
            "status": 403,
            "ps": "过滤POST参数中常见sql注入、xss等攻击",
            "open": True,
            "reqfile": "post.html"
        },
        "scan_conf": {
            "open": True,
            "limit": 240,
            "cycle": 60
        },
        "ua_white": [],
        "body_regular": [],
        "log_save": 30
    }

    try:
        infos = json.loads(ReadFile("/www/server/btwaf/config.json"))
        if len(infos) < 10:
            infos = config
        infos["access_token"] = GetRandomString(32)
        if not 'session_token' in infos:
            infos['session_token'] = GetRandomString(64)
        if not 'cc_token' in infos:
            infos['cc_token'] = GetRandomString(64)
        if not 'token_time' in infos:
            infos['token_time'] = int(time.time())
        if int(time.time()) - int(infos['token_time']) > 86400 * 120:
            if not 'session_token' in infos:
                infos['session_token'] = GetRandomString(64)
            if not 'cc_token' in infos:
                infos['cc_token'] = GetRandomString(64)
            if not 'token_time' in infos:
                infos['token_time'] = int(time.time())
        if 'cms_rule_open' not in infos:
            infos['cms_rule_open'] = False
        WriteFile("/www/server/btwaf/config.json", json.dumps(infos))
    except:
        WriteFile("/www/server/btwaf/config.json", json.dumps(config))
    try:
        json.loads(ReadFile("/www/server/btwaf/site.json"))
    except:
        WriteFile("/www/server/btwaf/site.json", json.dumps({}))


def getzhizhu():
    path = "/www/server/btwaf/inc/"
    if not os.path.exists(path):
        os.makedirs(path, 0o755)

    for i in range(1, 10):
        old_path = "/www/server/panel/plugin/btwaf_lua/inc/" + str(i) + ".json"
        if os.path.exists(old_path):
            continue
        zhizhu = path + str(i) + ".json"
        if not os.path.exists(zhizhu):
            os.system("cp -a -r " + old_path + " " + zhizhu)
            continue
        if os.path.getsize(old_path) > os.path.getsize(zhizhu):
            os.system("cp -a -r " + old_path + " " + zhizhu)


def main():
    try:
        untar_arm()
    except:
        pass
    try:
        untar_GeoLite2()
    except:
        pass
    try:
        getzhizhu()
    except:
        pass
    try:
        check_rule()
    except:
        pass
    try:
        get_task()
    except:
        pass
    try:
        untar()
    except:
        pass

    # 蜘蛛拦截配置
    try:
        aaa = json.loads(ReadFile("/www/server/btwaf/rule/rule_hit_list.json"))
        if "蜘蛛拦截" not in aaa:
            aaa["蜘蛛拦截"] = True
        if "自定义拦截" not in aaa:
            aaa["自定义拦截"] = True
            WriteFile("/www/server/btwaf/rule/rule_hit_list.json", json.dumps(aaa))
    except:
        data = {
            "IP白名单": True,
            "IP黑名单": True,
            "URI白名单": True,
            "URI黑名单": True,
            "UA白名单": True,
            "UA黑名单": True,
            "云端恶意IP库": True,
            "地区限制": True,
            "蜘蛛拦截": True
        }
        WriteFile("/www/server/btwaf/rule/rule_hit_list.json", json.dumps(data))


main()
