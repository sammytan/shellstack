# coding: utf-8
import sys,os
os.chdir('/www/server/panel')
sys.path.append("class/")
import json

def ReadFile(filename,mode = 'r'):
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
                fp = open(filename, mode,encoding="utf-8",errors='ignore')
                f_body = fp.read()
            except:
                fp = open(filename, mode,encoding="GBK",errors='ignore')
                f_body = fp.read()
        else:
            return False
    finally:
        if fp and not fp.closed:
            fp.close()
    return f_body

def WriteFile(filename,s_body,mode='w+'):
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
            fp = open(filename, mode,encoding="utf-8")
            fp.write(s_body)
            fp.close()
            return True
        except:
            return False 
def ip2long(ip):
    ips = ip.split('.')
    if len(ips) != 4: return 0
    iplong = 2 ** 24 * int(ips[0]) + 2 ** 16 * int(ips[1]) + 2 ** 8 * int(ips[2]) + int(ips[3])
    return iplong
def zhuanhuang(aaa):
    ac = []
    cccc = 0
    list = []
    list2 = []
    for i in range(len(aaa)):
        for i2 in aaa[i]:
            dd = ''
            coun = 0
            for i3 in i2:
                if coun == 3:
                    dd += str(i3)
                else:
                    dd += str(i3) + '.'
                coun += 1
            list.append(ip2long(dd))
            cccc += 1
            if cccc % 2 == 0:
                aa = []
                bb = []
                aa.append(list[0])
                bb.append(list[1])
                cc = []
                cc.append(aa)
                cc.append(bb)
                ac.append(list)
                list = []
                list2 = []
    return ac
def main():
    try:
        aaa = json.loads(ReadFile("/www/server/btwaf/rule/ip_white.json"))
        if not aaa:return  False
        if type(aaa[0][0])==list:
            f = open('/www/server/btwaf/rule/ip_white.json', 'w')
            f.write(json.dumps(zhuanhuang(aaa)))
            f.close()
    except:
        WriteFile("/www/server/btwaf/rule/ip_white.json", json.dumps([]))

    try:
        aaa = json.loads(ReadFile("/www/server/btwaf/rule/ip_black.json"))
        if not aaa: return False
        if type(aaa[0][0]) == list:
            f = open('/www/server/btwaf/rule/ip_black.json', 'w')
            f.write(json.dumps(zhuanhuang(aaa)))
            f.close()
    except:
        WriteFile("/www/server/btwaf/rule/ip_black.json", json.dumps([]))
main()

def update_city():
    try:
        import PluginLoader,public
        get = public.dict_obj()
        get.plugin_get_object = 1
        gets = public.dict_obj()
        fun_obj = PluginLoader.plugin_run("btwaf", "get_reg_tions", get)
        fun_obj(gets)
    except:
        pass

if os.path.exists("/www/server/panel/logs/ipfilter.log"):
    #读取文件大小
    size = os.path.getsize("/www/server/panel/logs/ipfilter.log")
    #大于10M清空
    if size > 1024 * 1024 * 10:
        WriteFile("/www/server/panel/logs/ipfilter.log", "")

update_city()
print("转换ip格式")
