# coding: utf-8
# +-------------------------------------------------------------------
# | 宝塔Linux面板 x6
# +-------------------------------------------------------------------
# | Copyright (c) 2015-2017 宝塔软件(http://bt.cn) All rights reserved.
# +-------------------------------------------------------------------
# | Author: lkqiang<lkq@bt.cn>
# +-------------------------------------------------------------------
# +--------------------------------------------------------------------
# |   防火墙内部扫描webshell
# +--------------------------------------------------------------------
import random
import sys

sys.path.append('/www/server/panel/class')
import json, os, time, public

os.chdir('/www/server/panel')
import requests
from requests.packages.urllib3.exceptions import InsecureRequestWarning

requests.packages.urllib3.disable_warnings(InsecureRequestWarning)
import totle_db2


class webshell_check:
    __user = {}
    __PATH = '/www/server/panel/plugin/btwaf/'
    Recycle_bin = __PATH + 'Recycle'
    Webshell_Alarm = __PATH + 'Webshell_Alarm.json'

    def __init__(self):
        if not os.path.exists(self.Recycle_bin):
            os.makedirs(self.Recycle_bin)
        try:
            self.__user = json.loads(public.ReadFile('/www/server/panel/data/userInfo.json'))
        except:
            pass

    # 移动到回收站
    def Mv_Recycle_bin(self, path):
        rPath = self.Recycle_bin
        if not os.path.exists(self.Recycle_bin):
            os.makedirs(self.Recycle_bin)
        rFile = os.path.join(rPath, path.replace('/', '_bt_') + '_t_' + str(time.time()))
        try:
            import shutil
            shutil.move(path, rFile)
            return True
        except:
            return False

    '''
    @name 获取目录下的所有php文件
    @param path 文件目录
    @return list
    '''

    def get_dir(self, path):
        return_data = []
        data2 = []
        [[return_data.append(os.path.join(root, file)) for file in files] for root, dirs, files in os.walk(path)]
        for i in return_data:
            if str(i.lower())[-4:] == '.php':
                data2.append(i)
        return data2

    '''
    @name 读取文件内容
    @param filename 文件路径
    @return 文件内容
    '''

    def ReadFile(self, filename, mode='rb'):
        import os
        if not os.path.exists(filename): return False
        try:
            fp = open(filename, mode)
            f_body = fp.read()
            fp.close()
        except Exception as ex:
            if sys.version_info[0] != 2:
                try:
                    fp = open(filename, mode, encoding="utf-8")
                    f_body = fp.read()
                    fp.close()
                except Exception as ex2:
                    return False
            else:
                return False
        return f_body

    def GetFIles(self, path):
        if not os.path.exists(path): return False
        data = {}
        data['status'] = True
        data["only_read"] = False
        data["size"] = os.path.getsize(path)
        if os.path.getsize(path) > 1024 * 1024 * 2: return False
        fp = open(path, 'rb')
        if fp:
            srcBody = fp.read()
            fp.close()
            try:
                data['encoding'] = 'utf-8'
                data['data'] = srcBody.decode(data['encoding'])
            except:
                try:
                    data['encoding'] = 'GBK'
                    data['data'] = srcBody.decode(data['encoding'])
                except:
                    try:
                        data['encoding'] = 'BIG5'
                        data['data'] = srcBody.decode(data['encoding'])
                    except:
                        return False
        return True

    '''
    @name 上传到云端判断是否是webshell
    @param filename 文件路径
    @param url 云端URL
    @return bool 
    '''

    def webshellchop(self, filename, url):
        try:
            upload_url = url
            size = os.path.getsize(filename)
            if size > 1024000: return False
            if len(self.__user) == 0: return False
            if not self.GetFIles(filename): return False
            md5s = public.Md5(filename)
            webshell_path = "/www/server/panel/data/btwaf_wubao/"
            if not os.path.exists(webshell_path):
                os.makedirs(webshell_path)
            if os.path.exists(webshell_path + md5s + ".txt"):
                return False
            info = self.ReadFile(filename)
            upload_data = {'inputfile': info, "md5": md5s, "path": filename,
                           "access_key": self.__user['access_key'], "uid": self.__user['uid'],
                           "username": self.__user["username"]}
            print("正在上传文件:%s" % (filename))
            upload_res = requests.post(upload_url, upload_data, timeout=60).json()
            if upload_res['msg'] == 'ok':
                if (upload_res['data']['data']['level'] == 5):
                    self.Mv_Recycle_bin(filename)
                    if os.path.exists(self.Webshell_Alarm):
                        public.WriteFile(self.Webshell_Alarm, "[]")
                        Alarm = []
                    else:
                        try:
                            Alarm = json.loads(public.ReadFile(self.Webshell_Alarm))
                        except:
                            Alarm = []
                    if filename not in Alarm:
                        Alarm.append(filename)
                    public.WriteFile(self.Webshell_Alarm, json.dumps(Alarm))
                    print('%s 文件为木马 ' % (filename))
                    return True
                else:
                    return False
        except:
            return False

    '''
    @name 上传文件入口
    @param filename 文件路径
    @return bool 
    '''

    def upload_file_url2(self, filename, url):
        if os.path.exists(filename):
            ret = self.webshellchop(filename, url)
            if ret:
                return True
            return False
        else:
            return False

    '''
    @name 上传文件
    @param data 文件路径集合
    @return 返回webshell 路径
    '''

    def upload_shell(self, data):
        if len(data) == 0: return []
        return_data = []
        today = time.strftime("%Y-%m-%d-%H", time.localtime())
        if not os.path.exists("/www/server/btwaf/webshell_total/" + today + ".md5"):
            public.WriteFile("/www/server/btwaf/webshell_total/" + today + ".md5", "{}")
            md5_info = {}
        else:
            try:
                md5_info = json.loads(public.ReadFile("/www/server/btwaf/webshell_total/" + today + ".md5"))
            except:
                md5_info = {}
        for i in data:
            if not os.path.exists(i): continue
            md5 = public.FileMd5(i)
            if md5 in md5_info and md5_info[md5] == 1:
                continue
            if self.upload_file_url2(i, "http://w-check.bt.cn/check.php"):
                return_data.append(i)
                md5_info[md5] = 0
            else:
                md5_info[md5] = 1
        public.writeFile("/www/server/btwaf/webshell_total/" + today + ".md5", json.dumps(md5_info))
        return return_data

    def get_white(self):
        if not os.path.exists('/www/server/panel/data/white_webshell.json'): return []
        try:
            return json.loads(public.ReadFile('/www/server/panel/data/white_webshell.json'))
        except:
            return []

    '''
    @name 扫描webshell入口函数
    @param path 需要扫描的路径
    @return  webshell 路径集合
    '''

    def san_dir(self):
        import pwd
        if not os.path.exists("/www/server/btwaf/webshell.json"):
            public.WriteFile("/www/server/btwaf/webshell.json", "[]")
        stat = os.stat("/www/server/btwaf/webshell.json")
        accept = str(oct(stat.st_mode)[-3:])
        mtime = str(int(stat.st_mtime))
        user = ''
        try:
            user = pwd.getpwuid(stat.st_uid).pw_name
        except:
            user = "root"
        if user != "root":
            public.ExecShell("chown root:root /www/server/btwaf/webshell.json")

        today = time.strftime("%Y-%m-%d", time.localtime())
        # 删除过期文件
        # 列"/www/server/btwaf/webshell_total/" 目录
        if os.path.exists("/www/server/btwaf/webshell_total/"):
            for i in os.listdir("/www/server/btwaf/webshell_total/"):
                if i.startswith(today): continue
                os.remove("/www/server/btwaf/webshell_total/" + i)
        today = time.strftime("%Y-%m-%d-%H", time.localtime())
        if os.path.exists("/www/server/btwaf/webshell_total/" + today + ".json"):
            try:
                data = []
                webshell_info = json.loads(public.ReadFile("/www/server/btwaf/webshell_total/" + today + ".json"))
                for i in webshell_info:
                    if i not in data:
                        data.append(i)
                webshell_re = self.upload_shell(data)
                if len(webshell_re) >= 1:
                    print("扫描完成 发现存在%s个木马文件 时间:%s" % (
                        len(webshell_re), time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())))
                else:
                    print("扫描完成未发现存在木马文件 时间:%s" % time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()))
                return
            except:
                pass
        print("扫描完成未发现存在木马文件 时间:%s" % time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()))

    def return_python(self):
        if os.path.exists('/www/server/panel/pyenv/bin/python'): return '/www/server/panel/pyenv/bin/python'
        if os.path.exists('/usr/bin/python'): return '/usr/bin/python'
        if os.path.exists('/usr/bin/python3'): return '/usr/bin/python3'
        return 'python'

    def M2(self, table):
        with totle_db2.Sql() as sql:
            return sql.table(table)

    def get_logs(self, get):
        import cgi
        pythonV = sys.version_info[0]
        path = get.path.strip()
        if not os.path.exists(path): return ''
        if os.path.getsize(path) > 1024 * 1024 * 1: return ''
        try:
            import html
            pythonV = sys.version_info[0]
            if 'drop_ip' in get:
                path = path
                num = 12
            else:
                path = path
                num = 10
            if not os.path.exists(path): return []
            p = 1
            if 'p' in get:
                p = int(get.p)
            start_line = (p - 1) * num
            count = start_line + num
            fp = open(path, 'rb')
            buf = ""
            try:
                fp.seek(-1, 2)
            except:
                return []
            if fp.read(1) == "\n": fp.seek(-1, 2)
            data = []
            b = True
            n = 0
            c = 0
            while c < count:
                while True:
                    newline_pos = str.rfind(buf, "\n")
                    pos = fp.tell()
                    if newline_pos != -1:
                        if n >= start_line:
                            line = buf[newline_pos + 1:]
                            if line:
                                try:
                                    tmp_data = json.loads(line)
                                    data.append(tmp_data)
                                except:
                                    c -= 1
                                    n -= 1
                                    pass
                            else:
                                c -= 1
                                n -= 1
                        buf = buf[:newline_pos]
                        n += 1
                        c += 1
                        break
                    else:
                        if pos == 0:
                            b = False
                            break
                        to_read = min(4096, pos)
                        fp.seek(-to_read, 1)
                        t_buf = fp.read(to_read)
                        if pythonV == 3: t_buf = t_buf.decode('utf-8', errors="ignore")
                        buf = t_buf + buf
                        fp.seek(-to_read, 1)
                        if pos - to_read == 0:
                            buf = "\n" + buf
                if not b: break
            fp.close()

        except:
            data = []
            return public.get_error_info()
        if len(data) >= 1:
            if (len(data[0]) >= 1):
                return data[0][0].replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>').replace("&quot;",
                                                                                                          "\"")
        return data

    def share_ip(self):
        '''
        提交拦截日志、一小时更新一次、最多只提交100个、并且排除CC攻击
        :return:
        '''
        # 获取当前时间搓
        # 获取上一次的时间搓
        path = "/www/server/panel/data/share_ip.json"
        if not os.path.exists(path):
            public.writeFile(path, json.dumps({"time": int(time.time())}))
            share_ip_info = {"time": 0}
        else:
            share_ip_info = json.loads(public.readFile(path))
        if (int(time.time()) - share_ip_info["time"]) < 3600:
            return public.returnMsg(False, "未达到时间")
        # 获取共享IP计划是否开启
        try:
            config = json.loads(public.readFile('/www/server/btwaf/config.json'))
        except:
            return False
        if not config["share_ip"]: return False
        end_time = int(time.time())
        start_time = end_time - 3600
        import requests
        count = self.M2('totla_log').field('time').where("time>? and time<? and value_risk!=?",
                                                         (start_time, end_time, "cc")).order('id desc').count()
        if type(count) == "str":
            return public.returnMsg(False, "更新失败")
        if count == 0:
            return public.returnMsg(False, "更新失败")
        # 如果大于100 则只取100
        map_info = self.M2('totla_log').field(
            'time,server_name,ip,ip_country,type,uri,user_agent,value_risk,http_log,http_log_path,filter_rule').where(
            "time>? and time<? and value_risk!=? and  value_risk!=? and  value_risk!=? and  value_risk!=? and  value_risk!=?  and  value_risk!=? and  value_risk!=? and  value_risk!=? and  value_risk!=?", (start_time, end_time, "cc","customize","user_agent","drop_abroad","other","header","url_tell","url_rule","file")).order(
            'id desc').limit("120").select()
        data = []
        if type(map_info) == "str":
            return public.returnMsg(False, "更新失败")
        for i in map_info:
            i2 = {}
            if i["http_log_path"]:
                tmp = i['http_log']
                get = public.dict_obj()
                get.path = tmp
                i['http_log'] = self.get_logs(get)
            if not i["value_risk"]:
                i["value_risk"] = i["filter_rule"]
            i2["latest_block_time"] = i["time"]
            i2["host"] = i["server_name"]
            i2["attack_ip"] = i["ip"]
            i2["uri"] = i["uri"]
            i2["attack_type"] = i["value_risk"]
            i2["request_method"] = i["type"]
            i2["ua"] = i["user_agent"]
            i2["request_body"] = i["http_log"]
            i2["block_count"] = 1
            data.append(i2)
        request_data = {
            "x_bt_token": "ODIwMjNlZmQ3OTg4MDUxMzdjN2ZhNzAy",
            "uid": "",
            "data": data
        }
        # 获取用户的UID
        user_info = public.get_user_info()
        if 'uid' in user_info:
            request_data["uid"] = user_info["uid"]
        share_ip_info["time"] = int(time.time())
        public.writeFile(path, json.dumps(share_ip_info))
        url = "https://api.bt.cn/bt_waf/submit_waf_block_logs"
        requests.post(url, json=request_data, timeout=60)
        # 设置时间搓
        return public.returnMsg(True, "更新成功")

    # 解密数据
    def _encode(self, data):
        """
        @name 解密数据
        @author cjxin
        @data string 解密数据
        """
        import urllib, binascii
        if sys.version_info[0] == 2:
            result = urllib.unquote(binascii.unhexlify(data))
        else:
            if type(data) == str: data = data.encode('utf-8')
            tmp = binascii.unhexlify(data)
            if type(tmp) != str: tmp = tmp.decode('utf-8')
            result = urllib.parse.unquote(tmp)

        if type(result) != str: result = result.decode('utf-8')

        return json.loads(result)

    def get_ip(self):
        '''
        获取共享的恶意IP库 每天更新一次
        :return:
        '''
        try:
            path = "/www/server/panel/data/share_ip_info.json"
            if not os.path.exists(path):
                public.writeFile(path, json.dumps({"time": int(time.time())}))
                share_ip_info = {"time": 0}
            else:
                try:
                    share_ip_info = json.loads(public.readFile(path))
                except:
                    public.writeFile(path, json.dumps({"time": int(time.time())}))
                    share_ip_info = {"time": 0}
            if (int(time.time()) - share_ip_info["time"]) < 86400:
                return public.returnMsg(False, "未到时间")
            import requests
            request_data = {"x_bt_token": "MzI3YjAzOGQ3Yjk3NjUxYjVlMDkyMGFm"}
            user_info = public.get_user_info()
            if 'uid' in user_info:
                request_data["uid"] = user_info["uid"]
            share_ip_info["time"] = int(time.time())
            public.writeFile(path, json.dumps(share_ip_info))
            url = "https://api.bt.cn/bt_waf/get_malicious_ip"
            info = requests.post(url, json=request_data, timeout=60).json()
            ip_info = self._encode(info["data"])
            if type(ip_info) != list:
                return public.returnMsg(False, "更新失败")
            data = {}
            for i in ip_info:
                data[i['ip']] = i['release_time']
            public.WriteFile("/www/server/btwaf/rule/malicious_ip.json", json.dumps(data))
            public.ServiceReload()
        except:
            pass
        return public.returnMsg(True, "更新成功")

    def check_xss_statu(self):
        '''
        检测xss检测是否开启
        :return:
        '''
        path = "/www/server/panel/plugin/btwaf/nginx_btwaf_xss.pid"
        shell = "/www/server/panel/plugin/btwaf/xss_decode.sh"
        try:
            if not os.path.exists(path):
                os.system("nohup sh " + shell + " start > /dev/null 2>&1 &")
            else:
                pid = public.ReadFile(path)
                if not public.process_exists(pid):
                    os.system("nohup sh " + shell + " start > /dev/null 2>&1 &")
        except:
            if os.path.exists(shell):
                os.system("nohup sh " + shell + " restart > /dev/null 2>&1 &")

    '''
        @name上报防火墙错误信息,每小时上报一次，可以更好的修复BUG 
        @time:2024-07-11 
        @auth:lkq@bt.cn
        @ps:文件不能大于1M 只会读取最后10行
    '''

    def error_upload(self):
        path = "/www/server/panel/data/btwaf_error.pl"
        if not os.path.exists(path):
            public.writeFile(path, json.dumps({"time": int(time.time()), "md5": ""}))
            share_ip_info = {"time": 0, "md5": ""}
        else:
            share_ip_info = json.loads(public.readFile(path))
        time_out = random.randint(3600, 7200)
        if (int(time.time()) - share_ip_info["time"]) < time_out:
            return public.returnMsg(False, "未达到时间")

        # 检查md5 文件是否发生变化
        file_path = "/www/wwwlogs/btwaf_debug.log"
        if not os.path.exists(file_path): return False
        # 如果文件大于2M 直接清理
        if os.path.getsize(file_path) > 1024 * 1024 * 1:
            os.remove(file_path)
            return False
        md5 = public.Md5(file_path)
        if md5 == share_ip_info["md5"]:
            return False
        # 如果文件小于100
        if os.path.getsize(file_path) < 10:
            return False
        # 读取文件的最后100行
        # 获取防火墙的版本号
        version_path = "/www/server/panel/plugin/btwaf/info.json"
        if not os.path.exists(version_path): return False
        try:
            version_info = json.loads(public.readFile(version_path))
        except:
            return False
        version = version_info["versions"]
        data = public.GetNumLines(file_path, 20)
        data2 = data.split("\n")
        if len(data2) == 0: return False
        tmp = []
        for i in data2:
            # 判断是否存在今天的日期
            if time.strftime("%Y-%m-%d") in i and '/www/server/btwaf' in i:
                tmp.append(i)
        if len(tmp) == 0: return False
        tmp2 = "\n".join(tmp)
        import requests
        url = "https://api.bt.cn/bt_waf/submit_project_error_log"
        request_data = {
            "x_bt_token": "tgPVkiWdIJAqpYSsurbCn8yHQ5XGNB3K",
            "project_name": "btwaf",
            "error": "2025-12-08:10:44 version:" + version + " infos:" + tmp2
        }
        requests.post(url, json=request_data, timeout=60)
        share_ip_info["time"] = int(time.time())
        share_ip_info["md5"] = md5
        public.WriteFile(file_path, "")
        public.writeFile(path, json.dumps(share_ip_info))

    '''
        @name 蜘蛛更新、本地蜘蛛上报
        @time:2024-07-11
        @auth:lkq@bt.cn
        @ps 一天一次
    '''
    def get_spider(self):
        path_time = "/www/server/panel/data/btwaf_spider.pl"
        if not os.path.exists(path_time):
            public.writeFile(path_time, json.dumps({"time": int(time.time())}))
            share_ip_info = {"time": 0}
        else:
            share_ip_info = json.loads(public.readFile(path_time))
        #随机数
        if (int(time.time()) - share_ip_info["time"]) < 86400:
            return public.returnMsg(False, "未达到时间")
        # 获取云端的蜘蛛、更新到本地文件
        share_ip_info["time"] = int(time.time())
        public.writeFile(path_time, json.dumps(share_ip_info))
        try:
            userInfo = json.loads(public.ReadFile('/www/server/panel/data/userInfo.json'))
        except:
            return False
        data22 = {"access_key": userInfo['access_key'], "uid": userInfo['uid']}
        data_list=[]
        try:
            flag = False
            url = 'https://www.bt.cn/api/bt_waf/btWafGetSpidersSegment'
            data_list = json.loads(public.httpPost(url, data22, timeout=60))
            if data_list:
                for spiders in data_list:
                    if spiders=="9":continue
                    spider = public.readFile('/www/server/btwaf/inc/' + spiders + '.json')
                    # 并集合
                    spider = json.loads(spider)
                    # 将列表转换为集合
                    set_spider = set(spider)
                    set_spiders = set(data_list[spiders])
                    # 取云端的蜘蛛和本地的蜘蛛的差集
                    spider_diff = set_spiders - set_spider
                    if len(spider_diff) >= 1:
                        flag = True
                        spider += list(spider_diff)
                        public.writeFile('/www/server/btwaf/inc/' + spiders + '.json', json.dumps(spider))
            if flag:
                public.ServiceReload()
        except:
            pass
        # 本地蜘蛛上报
        upload_url = 'http://www.bt.cn/api/bt_waf/addSpider'
        type_list = {"baiduspider": "1", "googlebot": "2", "sogouspider": "4", "yahoo": "5", "bing": "6",
                     "bytedance": "7", "shenmaspider": "8"}
        map_list = {
            "baiduspider": [],
            "sogouspider": [],
            "yahoo": [],
            "bing": [],
            "bytedance": [],
            "shenmaspider": []
        }
        tmp_data_list={}
        import ipaddress
        for i in data_list:
            if i not in ["1","4","5","6","7","8"]:continue
            tmp_data_list[i]=[]
            for j in data_list[i]:
                try:
                    net_ip = ipaddress.ip_network(j)
                    all_ips = [ip for ip in net_ip]
                    for ip in all_ips:
                        tmp_data_list[i].append(str(ip))
                except:
                    pass
        try:
            get_spider = json.loads(public.readFile('/www/server/btwaf/rule/get_spider.json'))
            if len(get_spider) >= 1:
                for i in get_spider:
                    if get_spider[i] in map_list:
                        #判断这个蜘蛛是否在云端存在
                        if i in tmp_data_list[type_list[get_spider[i]]]:
                            continue
                        map_list[get_spider[i]].append(i)
                for i in map_list:
                    if len(map_list[i]) == 0: continue
                    u_list = {"type": type_list[i], "ip_list": json.dumps(map_list[i]),
                              "access_key": userInfo['access_key'],
                              "uid": userInfo['uid']}
                    requests.post(url=upload_url, data=u_list)
            #最大允许200个IP
            if len(get_spider) > 5000:
                #保留1000个IP
                tmp_get_spider = {}
                for i in get_spider:
                    if len(tmp_get_spider) >= 1000: break
                    tmp_get_spider[i] = get_spider[i]
                public.writeFile('/www/server/btwaf/rule/get_spider.json', json.dumps(tmp_get_spider))
        except:
            pass

        #过期的IP清理掉、最大只允许1000个IP
        try:
            not_spider="/www/server/btwaf/rule/not_spider.json"
            infos=json.loads(public.readFile(not_spider))
            if len(infos)>5000:
                #保留1000个IP
                tmp_infos={}
                for i in infos:
                    if len(tmp_infos)>=1000:break
                    tmp_infos[i]=infos[i]
                public.writeFile(not_spider,json.dumps(tmp_infos))
        except:
            pass

    def write_site_domains(self):
        '''
            定时检查是否有新的域名绑定
            一小时检查一次
            为解决server_name 与域名不一致的问题
        '''
        path_time = "/www/server/panel/data/write_site_domains.pl"
        if not os.path.exists(path_time):
            public.writeFile(path_time, json.dumps({"time": int(time.time())}))
            share_ip_info = {"time": 0}
        else:
            share_ip_info = json.loads(public.readFile(path_time))
        if (int(time.time()) - share_ip_info["time"]) < 3600:
            return public.returnMsg(False, "未达到时间")
        share_ip_info["time"] = int(time.time())
        public.writeFile(path_time, json.dumps(share_ip_info))
        sites_count=public.M('sites').field('name,id,path').count()
        if sites_count==0:return False
        path="/www/server/btwaf/domains.json"
        if not os.path.exists(path):
            domains=[]
        else:
            try:
                domains=json.loads(public.readFile(path))
            except:
                domains=[]
        if sites_count==len(domains):
            return False
        sites=public.M('sites').field('name,id,path').select()
        my_domains = []
        for my_site in sites:
            tmp = {}
            tmp['name'] = my_site['name']
            tmp_domains = public.M('domain').where('pid=?', (my_site['id'],)).field('name').select()
            tmp['domains'] = []
            for domain in tmp_domains:
                tmp['domains'].append(domain['name'])
            binding_domains = public.M('binding').where('pid=?', (my_site['id'],)).field('domain').select()
            for domain in binding_domains:
                tmp['domains'].append(domain['domain'])
            my_domains.append(tmp)
        public.writeFile(path, json.dumps(my_domains))
        #有新的域名绑定、重新加载配置
        public.serviceReload()

    def check_bt_ipfilter(self):
        '''
            @name 检查bt_ipfilter 服务是否开启
            @time 2024-10-11
        :return:
        '''
        path_time = "/www/server/panel/data/check_bt_ipfilter.pl"
        if not os.path.exists(path_time):
            public.writeFile(path_time, json.dumps({"time": int(time.time())}))
            share_ip_info = {"time": 0}
        else:
            share_ip_info = json.loads(public.readFile(path_time))
        #随机数
        if (int(time.time()) - share_ip_info["time"]) < 600:
            return public.returnMsg(False, "未达到时间")
        share_ip_info["time"] = int(time.time())
        public.writeFile(path_time, json.dumps(share_ip_info))
        pid="/www/server/panel/logs/ipfilter.pid"
        if not os.path.exists(pid):
            public.writeFile("/dev/shm/.bt_ip_filter","")
            os.system("/etc/init.d/bt_ipfilter restart")
        else:
            pid_info=public.ReadFile(pid)
            if os.path.exists("/proc/{}/cmdline".format(pid_info)):
                return False
            public.writeFile("/dev/shm/.bt_ip_filter", "")
            os.system("/etc/init.d/bt_ipfilter restart")

    def check_picture_timeout(self):
        '''
            @name 检查图片是否过期
            @time 2024-10-11
        :return:
        '''

        path_time = "/www/server/panel/data/check_picture_timeout.pl"
        if not os.path.exists(path_time):
            public.writeFile(path_time, json.dumps({"time": int(time.time())}))
            share_ip_info = {"time": 0}
        else:
            share_ip_info = json.loads(public.readFile(path_time))
        if (int(time.time()) - share_ip_info["time"]) < 36000:
            return public.returnMsg(False, "未达到时间")
        share_ip_info["time"] = int(time.time())
        public.writeFile(path_time, json.dumps(share_ip_info))
        path = "/www/server/btwaf/picture"
        #遍历文件夹
        tmp_list=[]
        for root, dirs, files in os.walk(path):
            for file in files:
                #判断文件后缀名是否为 png jpg jpeg
                if file.endswith(".png") or file.endswith(".jpg") or file.endswith(".jpeg"):
                    file_path = os.path.join(root, file)
                    file_time = os.path.getmtime(file_path)
                    if (int(time.time()) - file_time) > 86400:
                        if len(tmp_list) >=10000:
                            break
                        tmp_list.append(file_path)
        if len(tmp_list) >= 1:
            for i in tmp_list:
                try:
                    os.remove(i)
                except:
                    pass

    def check_btwaf_status(self):
        '''
            检查BT-WAF是否开启
        :return:
        '''
        if not os.path.exists("/etc/init.d/btwaf"):return False
        main_pid = os.path.join('/www/server/panel', 'logs/btwaf_msg.pid')
        if not os.path.exists(main_pid):
            return False
        pid = public.ReadFile(main_pid)
        if not pid: return False
        infos=public.ExecShell("ps aux |grep 'BT-WAF'|grep -v grep|awk '{print $2}'")
        if pid.strip() in infos[0]:
            return True
        #如果不存在则启动
        os.system("/etc/init.d/btwaf start")
        return True

    def get_malicious_ip_database(self):
        '''
            获取恶意IP库情报库
        :return:
        '''
        path_time = "/www/server/panel/data/get_malicious_ip_database.pl"
        if not os.path.exists(path_time):
            public.writeFile(path_time, json.dumps({"time": int(time.time())}))
            share_ip_info = {"time": 0}
        else:
            share_ip_info = json.loads(public.readFile(path_time))
        if (int(time.time()) - share_ip_info["time"]) < 86400:
            return public.returnMsg(False, "未达到时间")
        try:
            config = json.loads(public.readFile('/www/server/btwaf/config.json'))
        except:
            return False
        if 'btmalibrary' not in config:return False
        if not config["btmalibrary"]: return False
        if len(self.__user) == 0: return False
        path = "/www/server/btwaf/rule/btmalibrary_malicious.json"
        #获取情报库
        url="https://www.bt.cn/api/bt_waf/get_malicious_new"
        reulst_list={}
        total=0
        data=public.get_user_info()
        if type(data)!=dict:return public.returnMsg(False, "请先登录")
        data["x_bt_token"]="SksBSpWhJE7oVRixKCAZVEsN3QDnfQBU"
        data["os"]="linux"
        for i in range(1,50):
            try:
                data["page"]=i
                result=requests.post(url,json=data,timeout=60).json()
                if result["success"]:
                    total+=len(result["res"]['list'])
                    reulst_list.update(result["res"]['list'])
                if total>=result["res"]['total']:
                    break
            except:
                break
        if len(reulst_list)>=1:
            public.WriteFile(path,json.dumps(reulst_list))
            public.ServiceReload()

if __name__ == "__main__":
    webshell_checker = webshell_check()
    webshell_checker.get_malicious_ip_database()
    webshell_checker.check_bt_ipfilter()
    webshell_checker.write_site_domains()
    webshell_checker.check_xss_statu()
    webshell_checker.share_ip()
    webshell_checker.get_ip()
    webshell_checker.san_dir()
    webshell_checker.error_upload()
    webshell_checker.get_spider()
    webshell_checker.check_picture_timeout()
    webshell_checker.check_btwaf_status()