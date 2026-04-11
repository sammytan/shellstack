#!/bin/bash
#这是宝塔官方的btwaf安装脚本, 用于安装btwaf的依赖库, 不能修改该脚本, 只是用来参考宝塔的btwaf安装脚本, 用于安装btwaf的依赖库
PATH=/www/server/panel/pyenv/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
install_tmp='/tmp/bt_install.pl'
pluginPath=/www/server/panel/plugin/btwaf
remote_dir="total2"
pyVersion=$(python -c 'import sys;print(sys.version_info[0]);')
py_zi=$(python -c 'import sys;print(sys.version_info[1]);')
pluginPath2=/www/server/panel/plugin/webshell_san
aacher=$(uname -a |grep -Po aarch64|awk 'NR==1')
Centos6Check=$(cat /etc/redhat-release|grep ' 6.'|grep -i centos)


Get_platform()
{
    case $(uname -s 2>/dev/null) in
        Linux )                    echo "linux" ;;
        FreeBSD )                  echo "freebsd" ;;
        *BSD* )                    echo "bsd" ;;
        Darwin )                   echo "macosx" ;;
        CYGWIN* | MINGW* | MSYS* ) echo "mingw" ;;
        AIX )                      echo "aix" ;;
        SunOS )                    echo "solaris" ;;
        * )                        echo "unknown"
    esac
}

Get_ARM() {
        if [[ $(uname -m) == "aarch64" ]]; then
                echo "当前系统是ARM64架构"
                # 检查Nginx是否为OpenResty版本
                NGINX_PATH="/www/server/nginx/sbin/nginx"
                if [[ ! -x "$NGINX_PATH" ]]; then
                        echo "错误：未找到可执行的Nginx二进制文件"
                        exit 1
                fi
                                # 获取Nginx版本信息
                VERSION_INFO=$("$NGINX_PATH" -v 2>&1)
                        # 检查是否包含"openresty"字符串
                if [[ ! "$VERSION_INFO" =~ "openresty" ]]; then

                        echo '安装失败,ARM系统需要安装openresty版本的Nginx'
                        echo '安装失败,ARM系统需要安装openresty版本的Nginx'
                        echo '10秒后结束安装进程！！！！'
                        sleep 10
                        rm -f /www/server/panel/vhost/nginx/btwaf.conf
                        rm -rf /www/server/panel/plugin/btwaf/
                        echo '安装失败,当前系统为ARM、请安装openresty后重新安装' > $install_tmp
                        exit 1
                fi
        fi
}


Remove_path()
{
    local prefix=$1
    local new_path
    new_path=$(echo "${PATH}" | sed \
        -e "s#${prefix}/[^/]*/bin[^:]*:##g" \
        -e "s#:${prefix}/[^/]*/bin[^:]*##g" \
        -e "s#${prefix}/[^/]*/bin[^:]*##g")
    export PATH="${new_path}"
}
Add_path()
{
    local prefix=$1
    local new_path
    new_path=$(echo "${PATH}" | sed \
        -e "s#${prefix}/[^/]*/bin[^:]*:##g" \
        -e "s#:${prefix}/[^/]*/bin[^:]*##g" \
        -e "s#${prefix}/[^/]*/bin[^:]*##g")
    export PATH="${prefix}:${new_path}"
}

Get_lua_version(){
    echo `/www/server/btwaf/lua515/bin/lua -e 'print(_VERSION:sub(5))'`
}


Install_LuaJIT()
{
        LUAJIT_VER="2.1.0-beta3"
        LUAJIT_INC_PATH="luajit-2.1"
        if [ ! -f '/usr/local/lib/libluajit-5.1.so' ] || [ ! -f "/usr/local/include/${LUAJIT_INC_PATH}/luajit.h" ];then
                #wget -c -O LuaJIT-${LUAJIT_VER}.tar.gz ${download_Url}/install/src/LuaJIT-${LUAJIT_VER}.tar.gz -T 10
                cd $pluginPath && tar xvf $pluginPath/LuaJIT-${LUAJIT_VER}.tar.gz
                cd $pluginPath/LuaJIT-${LUAJIT_VER}
                make linux
                make install
                cd ..
                rm -rf LuaJIT-*
                export LUAJIT_LIB=/usr/local/lib
                export LUAJIT_INC=/usr/local/include/${LUAJIT_INC_PATH}/
                ln -sf /usr/local/lib/libluajit-5.1.so.2 /usr/local/lib64/libluajit-5.1.so.2
                echo "/usr/local/lib" >> /etc/ld.so.conf
                ldconfig
        fi
}


Install_lua515(){
    local install_path="/www/server/btwaf/lua515"
    
    local version
    version=$(Get_lua_version)

        if [[ $version == *GLIBC* ]]; then
                rm -rf $install_path
        fi 
    echo "Current lua version: "$version
    if  [ -d "${install_path}/bin" ]
    then
        Add_path "${install_path}/bin"
        echo "Lua 5.1.5 has installed."
                return 1
    fi
    
    local lua_version="lua-5.1.5"
    local package_name="${lua_version}.tar.gz"
    mkdir -p $install_path
        cd $pluginPath
    tar xvzf $pluginPath/$package_name
    cd $lua_version
    platform=$(Get_platform)
    if [ "${platform}" = "unknown" ] 
    then
        platform="linux"
    fi
    make "${platform}" install INSTALL_TOP=$install_path
    Add_path "${install_path}/bin"
    #rm -rf "${pluginPath}/${lua_version}*"

    version=$(Get_lua_version)
    if [ ${version} == "5.1" ]
    then
        echo "Lua 5.1.5 has installed."
        return 1
    fi
    return 0
}


Install_sqlite3_for_nginx()
{
    if [ true ];then
                luarocks_output=$(luarocks |grep "/www/server/btwaf/lua515/bin/lua")
                if echo "$luarocks_output" | grep -q "/www/server/btwaf/lua515/bin/lua"; then
                        echo "luarocks已经安装"
                else
                        cd $pluginPath
                        tar xf $pluginPath/luarocks-3.5.0.tar.gz
                        cd $pluginPath/luarocks-3.5.0
                        ./configure --with-lua-include=/www/server/btwaf/lua515/include --with-lua-bin=/www/server/btwaf/lua515/bin
                        make -I/www/server/btwaf/lua515/bin
                        make install 
                fi
    fi
    if [ true ];then
                #如果存在/www/server/btwaf/inc/lsqlite3.so 则判断这个文件是否大于20KB
                if [ -f '/www/server/btwaf/inc/lsqlite3.so' ];then
                        usranso=$(ls -l /www/server/btwaf/inc/lsqlite3.so | awk '{print $5}')
                        if [ $usranso -lt 20000 ];then
                                rm -rf /www/server/btwaf/inc/lsqlite3.so
                        fi
                        cd /www/server/btwaf/inc
                        is_jit_cjson=$(luajit -e "require 'lsqlite3'" 2>&1|grep 'undefined')
                        if [ "$is_jit_cjson" != "" ];then
                                rm -rf /www/server/btwaf/inc/lsqlite3.so
                        fi
                        # 如果文件还存在、则不再重新安装
                        if [ -f '/www/server/btwaf/inc/lsqlite3.so' ];then
                                echo "sqlite3安装成功"
                                return 1
                        fi
                fi
        yum install -y sqlite-devel readline-devel ncurses-devel 
        apt install -y libsqlite3-dev libreadline-dev libncurses-dev
                cd $pluginPath && rm -rf $pluginPath/lsqlite3_fsl09y
        cd $pluginPath && unzip $pluginPath/lsqlite3_fsl09y.zip && cd lsqlite3_fsl09y 
                echo '正在编译lsqlite3模块'
                gcc -O2 -fPIC -I/www/server/btwaf/lua515/include -c lsqlite3.c -o lsqlite3.o -DLSQLITE_VERSION='"0.9.5"' -I/usr/include
                gcc -shared -o lsqlite3.so lsqlite3.o -L/usr/lib -Wl,-rpath,/usr/lib -lsqlite3
                sleep 1
        if [ -f '/www/server/panel/plugin/btwaf/lsqlite3_fsl09y/lsqlite3.so' ];then
                    echo "sqlite3安装成功"
                        mkdir -p /www/server/btwaf/inc/
            \cp -a -r $pluginPath/lsqlite3_fsl09y/lsqlite3.so /www/server/btwaf/inc/lsqlite3.so
                        chmod 755 /usr/local/lib/lua/5.1/lsqlite3.so
        else
                        echo "sqlite3解压失败"
        fi

                #检查lsqlite3的可用性
        cd /www/server/btwaf/inc
        is_jit_cjson=$(luajit -e "require 'lsqlite3'" 2>&1|grep 'undefined symbol: ')
        if [ "$is_jit_cjson" != "" ];then
            cd /tmp
                        rm -rf /www/server/btwaf/inc/lsqlite3.so
                        cp -a -r /usr/local/lib/lua/5.1/lsqlite3.so /www/server/btwaf/inc/lsqlite3.so
        fi
    fi
    if [ -f /usr/local/lib/lua/5.1/cjson.so ];then
                cd /www/server/btwaf/inc
        is_jit_cjson=$(luajit -e "require 'cjson'" 2>&1|grep 'undefined symbol: ')
        if [ "$is_jit_cjson" != "" ];then
            cd /tmp
                        rm -rf /www/server/btwaf/inc/cjson.so
            luarocks install lua-cjson
                        cp -a -r /usr/local/lib/lua/5.1/cjson.so /www/server/btwaf/inc/cjson.so
        fi
    fi
        chmod 755 /www/server/btwaf/inc/lsqlite3.so
}

install_mbd(){
        #如果没有文件
        echo ""
}


Install_white_ip()
{
cat >$pluginPath/white.py<< EOF
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
EOF
}




Get_Pack_Manager(){
        if [ -f "/usr/bin/yum" ] && [ -d "/etc/yum.repos.d" ]; then
                PM="yum"
        elif [ -f "/usr/bin/apt-get" ] && [ -f "/usr/bin/dpkg" ]; then
                PM="apt-get"
        fi
}

Service_Add(){
        Get_Pack_Manager
        if [ "${PM}" == "yum" ] || [ "${PM}" == "dnf" ]; then
                chkconfig --add btwaf
                chkconfig --level 2345 btwaf on
                Centos9Check=$(cat /etc/redhat-release |grep ' 9')
                if [ "${Centos9Check}" ];then
            cp -a -r /www/server/panel/plugin/btwaf/btwaf.service /usr/lib/systemd/system/btwaf.service
                        chmod +x /usr/lib/systemd/system/btwaf.service
                        systemctl enable btwaf
                fi
        elif [ "${PM}" == "apt-get" ]; then
                update-rc.d btwaf defaults
        fi 
}


bt_syssafe_stop() {
        if [ -f "/etc/init.d/bt_syssafe" ]; then
                status=$`/etc/init.d/bt_syssafe status`
                if [[ $status == *"already running"* ]]; then
                        echo '存在系统加固临时关闭中'
                        /etc/init.d/bt_syssafe stop
                        touch /tmp/.bt_syssafe_stop
                fi
        fi
}

bt_syssafe_start() {
        if [ -f "/tmp/.bt_syssafe_stop" ]; then
                status=$`/etc/init.d/bt_syssafe status`
                if [[ $status == *"not running"* ]]; then
                        echo '系统加固重新启动'
                        /etc/init.d/bt_syssafe start
                fi
                rm -f /tmp/.bt_syssafe_stop
        fi
}


Install_btwaf_task()
{
        #检查
        bt_syssafe_stop
        chmod +x /www/server/panel/plugin/btwaf/btwaf.sh
        \cp -a -r /www/server/panel/plugin/btwaf/btwaf.sh  /etc/init.d/btwaf
        chmod +x /etc/init.d/btwaf

        if [ -f "/etc/init.d/btwaf" ]; then
                Service_Add
                bt_syssafe_start
        else
                bt_syssafe_start
                echo '安装失败,请先关闭系统加固后重试、或者其他安全软件例如'
                echo '5秒后结束安装进程！！！！'
                sleep 5
                echo '安装失败,可能存在一些安全软件导致了防火墙计划任务启动失败' > $install_tmp
                exit 1
        fi 
}

Checkgeoip2()
{
        # 检查是否安装了geoip2模块
        geoip2_check=$(btpython -c "import geoip2" 2>&1)
        if [[ $geoip2_check == *"No module named"* ]] || [[ $geoip2_check == *"ModuleNotFoundError"* ]]; then
                echo "geoip2模块未安装，正在安装..."
                btpip install geoip2 
                echo "geoip2模块安装完成"
        else
                echo "geoip2模块已安装"
        fi
}

Install_btwaf()
{ 

        Get_ARM
        #如果是ARM的系统。需要判断安装Nginx是否为openresty
        Install_btwaf_task
        Checkgeoip2
        if [ -f /www/server/panel/vhost/nginx/total.conf ];then
                chattr -i /www/server/panel/vhost/nginx/total.conf
                sleep 0.5
                rm -rf /www/server/panel/vhost/nginx/total.conf
        fi
        mkdir -p $pluginPath
        if [ -d '/www/server/btwaf/' ];then
                echo ""
        else 
                mkdir -p /www/server/btwaf/inc
        fi 
        cd /www/server/panel/plugin/btwaf &&  /www/server/panel/pyenv/bin/python database_check.py

        wget -O $pluginPath/btwaf_static.zip  https://download.bt.cn/btwaf_rule/btwaf_static_2025_10.zip
        sleep 0.5
        ls /www/server/panel/plugin/btwaf/btwaf_static.zip
    count=$( ls --block-size=1 -l /www/server/panel/plugin/btwaf/btwaf_static.zip 2>/dev/null | awk '{print $5}' )
        echo "下载的资源包大小:"$count;
        if [ $count -lt 20038116 ];then
                echo '下载资源包失败' > $install_tmp
                echo 'ERROR:安装失败' > $install_tmp
                echo '安装失败,可以重新安装一次试试'
                echo '5秒后结束安装进程！！！！'
                sleep 5
                echo '安装失败,下载资源包失败、请重新尝试一次' > $install_tmp
                exit 1
        fi 
        if [ -d $pluginPath/btwaf_static ];then
                rm -rf $pluginPath/btwaf_static
        fi
        cd $pluginPath  && unzip $pluginPath/btwaf_static.zip

        if [ -d $pluginPath/btwaf_static ];then
                echo "解压成功"
        else
                echo '解压失败' > $install_tmp
                echo 'ERROR:安装失败' > $install_tmp
        fi


        #覆盖静态文件
        rm -rf $pluginPath/static/src $pluginPath/static/fonts  $pluginPath/static/moment $pluginPath/static/img $pluginPath/static/esri $pluginPath/static/dojo
        mv $pluginPath/btwaf_static/static/src $pluginPath/static/
        mv $pluginPath/btwaf_static/static/moment $pluginPath/static/
        #mv $pluginPath/btwaf_static/static/esri $pluginPath/static/
        #mv $pluginPath/btwaf_static/static/dojo $pluginPath/static/
        mv $pluginPath/btwaf_static/static/img $pluginPath/static/
        mv $pluginPath/btwaf_static/static/fonts $pluginPath/static/

        rm -rf $pluginPath/btwaf_static/static
        mv -f $pluginPath/btwaf_static/* $pluginPath/
        rm -rf $pluginPath/btwaf_static/

        #覆盖
        rm -rf $pluginPath/btwaf_static.zip
        #mv -f  $pluginPath/GeoLite2-City-reduce.mmdb /www/server/btwaf/inc/GeoLite2-City.mmdb


        if [ -f /www/server/btwaf/httpd.lua ];then
                rm -rf /www/server/btwaf
        fi



        en=''
        grep "English" /www/server/panel/config/config.json >> /dev/null
        if [ "$?" -eq 0 ];then
                en='_en'
        fi
        usranso2=`ls -l /usr/local/lib/lua/5.1/cjson.so | awk '{print $5}'`
        if [ $usranso2 -eq 0 ];then
                rm -rf /usr/local/lib/lua/5.1/cjson.so
        fi
        rm -rf /www/server/panel/vhost/nginx/free_waf.conf
        rm -rf /www/server/free_waf
        rm -rf /www/server/panel/plugin/free_waf
        yum install sqlite-devel net-tools -y
        apt install sqlite-devel libreadline-dev net-tools -y 
        #Install_socket


        yum install lua-socket readline-devel -y
        yum install lua-json  -y 
        apt-get install lua-socket -y
        apt-get install lua-cjson -y
        Install_lua515
        Install_cjson
        #Install_luarocks

        Install_sqlite3_for_nginx
        echo '正在安装脚本文件...' > $install_tmp
        Install_white_ip
        python $pluginPath/send_vilidate.py
        python $pluginPath/black.py
        if [ ! -f /www/server/btwaf/captcha/num2.json ];then
                unzip -o $pluginPath/captcha.zip  -d /www/server/btwaf/inc > /dev/null
                rm -rf $pluginPath/captcha.zip
        fi
        \cp -a -r $pluginPath/waf2monitor_data.conf /www/server/panel/vhost/nginx/waf2monitor_data.conf
        \cp -a -r $pluginPath/0.btwaf_log_format.conf  /www/server/panel/vhost/nginx/0.btwaf_log_format.conf
                if [ ! -f /www/server/panel/vhost/nginx/speed.conf ];then
                \cp -a -r $pluginPath/btwaf.conf  /www/server/panel/vhost/nginx/btwaf.conf
        else
                \cp -a -r $pluginPath/btwaf2.conf  /www/server/panel/vhost/nginx/btwaf.conf
        fi
        #机器配置不同、配置文件也需要增加
        bash $pluginPath/lua_shared.sh
        btwaf_path=/www/server/btwaf
        mkdir -p $btwaf_path/html
        rm -rf /www/server/btwaf/cms
        rm -rf $btwaf_path/xss_parser
        chattr -ia  /www/server/btwaf/*.lua
        if [ ! -f $btwaf_path/html/limit.json ];then
                \cp -a -r $pluginPath/btwaf_lua/html/limit.json $btwaf_path/html/limit.json
                \cp -a -r $pluginPath/btwaf_lua/html/limit.html $btwaf_path/html/limit.html
        fi

        if [ ! -f $btwaf_path/html/url.html ];then
                \cp -a -r $pluginPath/btwaf_lua/html/url.html $btwaf_path/html/url.html
                \cp -a -r $pluginPath/btwaf_lua/html/ip.html $btwaf_path/html/ip.html
        fi


        if [ ! -f $btwaf_path/html/get.html ];then
                \cp -a -r $pluginPath/btwaf_lua/html/get.html $btwaf_path/html/get.html
                \cp -a -r $pluginPath/btwaf_lua/html/get.html $btwaf_path/html/post.html
                \cp -a -r $pluginPath/btwaf_lua/html/get.html $btwaf_path/html/cookie.html
                \cp -a -r $pluginPath/btwaf_lua/html/get.html $btwaf_path/html/user_agent.html
                \cp -a -r $pluginPath/btwaf_lua/html/get.html $btwaf_path/html/other.html
        fi
        if [ ! -f $btwaf_path/html/city.html ];then
                \cp -a -r $pluginPath/btwaf_lua/html/city.html $btwaf_path/html/city.html
        fi

        mkdir -p $btwaf_path/rule
        \cp -a -r $pluginPath/btwaf_lua/rule/cn.json $btwaf_path/rule/cn.json
        \cp -a -r $pluginPath/btwaf_lua/rule/lan.json $btwaf_path/rule/lan.json

        \cp -a -r $pluginPath/btwaf_lua/html/fingerprint2.js $btwaf_path/html/fingerprint2.js
        \cp -a -r $pluginPath/btwaf_lua/html/default_return.html $btwaf_path/html/default_return.html
        \cp -a -r $pluginPath/btwaf_lua/html/aes_gcm.html $btwaf_path/html/aes_gcm.html
        \cp -a -r $pluginPath/btwaf_lua/html/forge.min.js $btwaf_path/html/forge.min.js
        \cp -a -r $pluginPath/btwaf_lua/html/aes_cbc.html $btwaf_path/html/aes_cbc.html
        \cp -a -r $pluginPath/btwaf_lua/html/aes_ctr.html $btwaf_path/html/aes_ctr.html
        \cp -a -r $pluginPath/btwaf_lua/html/aes_ofb.html $btwaf_path/html/aes_ofb.html
        \cp -a -r $pluginPath/btwaf_lua/html/aes_gcm.html $btwaf_path/html/aes_gcm.html

        \cp -a -r $pluginPath/btwaf_lua/html/aes_cbc_customize.html $btwaf_path/html/aes_cbc_customize.html
        \cp -a -r $pluginPath/btwaf_lua/html/aes_ctr_customize.html $btwaf_path/html/aes_ctr_customize.html
        \cp -a -r $pluginPath/btwaf_lua/html/aes_ofb_customize.html $btwaf_path/html/aes_ofb_customize.html
        \cp -a -r $pluginPath/btwaf_lua/html/aes_gcm_customize.html $btwaf_path/html/aes_gcm_customize.html
        \cp -a -r $pluginPath/btwaf_lua/html/timeout.html $btwaf_path/html/timeout.html
        \cp -a -r $pluginPath/btwaf_lua/html/timeout_user.html $btwaf_path/html/timeout_user.html


        if [ ! -f $btwaf_path/rule/limit.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/limit.json $btwaf_path/rule/limit.json
        fi

        if [ ! -f $btwaf_path/rule/btmalibrary_malicious.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/btmalibrary_malicious.json $btwaf_path/rule/btmalibrary_malicious.json
        fi


        if [ ! -f $btwaf_path/rule/ip_white_v6.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/ip_white_v6.json $btwaf_path/rule/ip_white_v6.json
                \cp -a -r $pluginPath/btwaf_lua/rule/ip_black_v6.json $btwaf_path/rule/ip_black_v6.json
        fi



        if [ ! -f $btwaf_path/rule/malicious_ip.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/malicious_ip.json $btwaf_path/rule/malicious_ip.json
        fi 

        rm -rf /www/server/panel/data/share_ip_info.json
        btpython $pluginPath/webshell_check.py >/dev/null 
        nohup btpython $pluginPath/free_total_update.py >/dev/null 2>&1 &
        if [ ! -f $btwaf_path/rule/post.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/url.json $btwaf_path/rule/url.json
                \cp -a -r $pluginPath/btwaf_lua/rule/post.json $btwaf_path/rule/post.json
                \cp -a -r $pluginPath/btwaf_lua/rule/cookie.json $btwaf_path/rule/cookie.json
                \cp -a -r $pluginPath/btwaf_lua/rule/head_white.json $btwaf_path/rule/head_white.json
                \cp -a -r $pluginPath/btwaf_lua/rule/user_agent.json $btwaf_path/rule/user_agent.json
                \cp -a -r $pluginPath/btwaf_lua/rule/cn.json $btwaf_path/rule/cn.json
                \cp -a -r $pluginPath/btwaf_lua/rule/ip_white.json $btwaf_path/rule/ip_white.json
                \cp -a -r $pluginPath/btwaf_lua/rule/scan_black.json $btwaf_path/rule/scan_black.json
                \cp -a -r $pluginPath/btwaf_lua/rule/url_black.json $btwaf_path/rule/url_black.json
                \cp -a -r $pluginPath/btwaf_lua/rule/ip_black.json $btwaf_path/rule/ip_black.json
                \cp -a -r $pluginPath/btwaf_lua/rule/url_white.json $btwaf_path/rule/url_white.json

        fi
        if [ ! -f $btwaf_path/rule/args.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/args.json $btwaf_path/rule/args.json
        fi 
        #微信支付、支付宝支付、pay
        \cp -a -r $pluginPath/btwaf_lua/rule/pay.json $btwaf_path/rule/pay.json
        # 蜘蛛IP都更新 

        \cp -a -r $pluginPath/btwaf_lua/inc/1.json $btwaf_path/inc/1.json
        \cp -a -r $pluginPath/btwaf_lua/inc/2.json $btwaf_path/inc/2.json
        \cp -a -r $pluginPath/btwaf_lua/inc/3.json $btwaf_path/inc/3.json
        \cp -a -r $pluginPath/btwaf_lua/inc/4.json $btwaf_path/inc/4.json
        \cp -a -r $pluginPath/btwaf_lua/inc/5.json $btwaf_path/inc/5.json
        \cp -a -r $pluginPath/btwaf_lua/inc/6.json $btwaf_path/inc/6.json
        \cp -a -r $pluginPath/btwaf_lua/inc/7.json $btwaf_path/inc/7.json
        \cp -a -r $pluginPath/btwaf_lua/inc/8.json $btwaf_path/inc/8.json
        \cp -a -r $pluginPath/btwaf_lua/inc/9.json $btwaf_path/inc/9.json

        if [ ! -f $btwaf_path/rule/customize.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/customize.json $btwaf_path/rule/customize.json
        fi

        if [ ! -f $btwaf_path/rule/customize_count.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/customize_count.json $btwaf_path/rule/customize_count.json
        fi

        if [ ! -f $btwaf_path/rule/url_white_senior.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/url_white_senior.json $btwaf_path/rule/url_white_senior.json
        fi

        if [ ! -f $btwaf_path/rule/not_spider.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/not_spider.json $btwaf_path/rule/not_spider.json
        fi

        if [ ! -f $btwaf_path/rule/get_spider.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/get_spider.json $btwaf_path/rule/get_spider.json
        fi

        #if [ ! -f $btwaf_path/rule/args.json ];then
        #每次都会更新args.json
        \cp -a -r $pluginPath/btwaf_lua/rule/args.json $btwaf_path/rule/args.json
        #fi
        if [ ! -f $btwaf_path/rule/post.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/post.json $btwaf_path/rule/post.json
        fi 

        \cp -a -r $pluginPath/btwaf_lua/rule/url.json $btwaf_path/rule/url.json
        if [ ! -f $btwaf_path/rule/cookie.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/cookie.json $btwaf_path/rule/cookie.json
        fi
        if [ ! -f $btwaf_path/rule/user_agent.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/user_agent.json $btwaf_path/rule/user_agent.json
        fi 
        \cp -a -r $pluginPath/btwaf_lua/rule/password.json $btwaf_path/rule/password.json
        \cp -a -r $pluginPath/btwaf_lua/rule/username_top.json $btwaf_path/rule/username_top.json


        if [ ! -f $btwaf_path/rule/cc_uri_white.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/cc_uri_white.json $btwaf_path/rule/cc_uri_white.json
        fi

        if [ ! -f $btwaf_path/rule/reg_tions.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/reg_tions.json $btwaf_path/rule/reg_tions.json
        fi

        if [ ! -f $btwaf_path/rule/reg_city.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/reg_city.json $btwaf_path/rule/reg_city.json
        fi

        if [ ! -f $btwaf_path/rule/url_request_mode.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/url_request_mode.json $btwaf_path/rule/url_request_mode.json
        fi



        if [ ! -f /dev/shm/stop_ip.json ];then
                \cp -a -r $pluginPath/btwaf_lua/stop_ip.json /dev/shm/stop_ip.json
        fi
        chmod 777 /dev/shm/stop_ip.json
        chown www:www /dev/shm/stop_ip.json

        if [ ! -f $btwaf_path/site.json ];then
                \cp -a -r $pluginPath/btwaf_lua/site.json $btwaf_path/site.json
        fi


        if [ ! -f $btwaf_path/config.json ];then
                \cp -a -r $pluginPath/btwaf_lua/config.json $btwaf_path/config.json
        fi

        if [ ! -f $btwaf_path/domains.json ];then
                \cp -a -r $pluginPath/btwaf_lua/domains.json $btwaf_path/domains.json
        fi

        if [ ! -f $btwaf_path/total.json ];then
                \cp -a -r $pluginPath/btwaf_lua/total.json $btwaf_path/total.json
        fi

        if [ ! -f $btwaf_path/rule/rule_hit_list.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/rule_hit_list.json $btwaf_path/rule/rule_hit_list.json
        fi

        if [ ! -f $btwaf_path/btwaf_rule_hit.json ];then
                \cp -a -r $pluginPath/btwaf_lua/btwaf_rule_hit.json $btwaf_path/btwaf_rule_hit.json
        fi
        chown www:www $btwaf_path/btwaf_rule_hit.json


        if [ ! -f $btwaf_path/rule/rule_hit_list.json ];then
                \cp -a -r $pluginPath/btwaf_lua/rule/rule_hit_list.json $btwaf_path/rule/rule_hit_list.json
        fi

        if [ ! -f $btwaf_path/drop_ip.log ];then

                \cp -a -r $pluginPath/btwaf_lua/drop_ip.log $btwaf_path/drop_ip.log
        fi

        if [ -d '/www/server/btwaf/picture' ];then
                echo ""
        else 
                mkdir -p /www/server/btwaf/picture
        fi 

        mkdir -p $btwaf_path/inc
        \cp -a -r $pluginPath/btwaf_lua/inc/bt_engine.so $btwaf_path/inc/bt_engine.so
        \cp -a -r $pluginPath/btwaf_lua/inc/arm.so.tar.gz $btwaf_path/inc/arm.so.tar.gz
        \cp -a -r $pluginPath/btwaf_lua/inc/libmaxminddb.so $btwaf_path/inc/libmaxminddb.so
        #\cp -a -r $pluginPath/btwaf_lua/inc/libmaxminddb_arm.so $btwaf_path/inc/libmaxminddb_arm.so
        \cp -a -r $pluginPath/btwaf_lua/inc/php_engine.so $btwaf_path/inc/php_engine.so
        #\cp -a -r $pluginPath/btwaf_lua/inc/php_engine_arm.so $btwaf_path/inc/php_engine_arm.so

        #处理被锁的情况
        #如果有这个目录 则去掉锁
        if [ -d '/www/server/btwaf/lib' ];then
                chattr -R  -ia /www/server/btwaf/lib
                rm -rf  /www/server/btwaf/lib
        fi
        \cp -a -r $pluginPath/btwaf_lua/lib $btwaf_path


        if [ -d '/www/server/btwaf/modules' ];then
                chattr -R  -ia /www/server/btwaf/modules
                rm -rf  /www/server/btwaf/modules
        fi
        \cp -a -r $pluginPath/btwaf_lua/modules $btwaf_path


        if [ -d '/www/server/btwaf/public' ];then
                chattr -R  -ia /www/server/btwaf/public
                rm -rf  /www/server/btwaf/public
        fi
        sleep 1

        \cp -a -r $pluginPath/btwaf_lua/public /www/server/btwaf/

        if [ ! -d '/www/server/btwaf/public' ];then
                echo "/www/server/btwaf/public 目录不存在"
        fi

        if [ ! -d '/www/server/btwaf/inc/cms' ];then
                \cp -a -r $pluginPath/btwaf_lua/inc/cms $btwaf_path/inc/cms
        fi

        if [ -d '/www/server/btwaf/inc/nday' ];then
                chattr -R  -ia /www/server/btwaf/inc/nday
                rm -rf  /www/server/btwaf/inc/nday
        fi
        \cp -a -r $pluginPath/btwaf_lua/inc/nday $btwaf_path/inc/nday

        \cp -a -r $pluginPath/btwaf_lua/LICENSE $btwaf_path/LICENSE

        if [ -d '/www/server/btwaf/body.lua' ];then
                chattr -ia /www/server/btwaf/body.lua
        fi
        if [ -d '/www/server/btwaf/header.lua' ];then
                chattr -ia /www/server/btwaf/header.lua
        fi
        if [ -d '/www/server/btwaf/init.lua' ];then
                chattr -ia /www/server/btwaf/init.lua
        fi
        if [ -d '/www/server/btwaf/waf.lua' ];then
                chattr -ia /www/server/btwaf/waf.lua
        fi

        \cp -a -r $pluginPath/btwaf_lua/body.lua $btwaf_path/body.lua

        \cp -a -r $pluginPath/btwaf_lua/header.lua $btwaf_path/header.lua

        \cp -a -r $pluginPath/btwaf_lua/init.lua $btwaf_path/init.lua
        \cp -a -r $pluginPath/btwaf_lua/waf.lua $btwaf_path/waf.lua
        \cp -a -r $pluginPath/btwaf_lua/logs.lua $btwaf_path/logs.lua
        \cp -a -r $pluginPath/btwaf_lua/worker.lua $btwaf_path/worker.lua

        chmod +x $btwaf_path/waf.lua
        chmod +x $btwaf_path/init.lua
        chmod +x $btwaf_path/body.lua
        chmod +x $btwaf_path/header.lua
        chmod +x $btwaf_path/logs.lua
        mkdir -p /www/wwwlogs/btwaf
        mkdir -p /www/server/btwaf/webshell_total

        chmod 777 /www/wwwlogs/btwaf
        chmod -R 755 /www/server/btwaf
        chmod -R 644 /www/server/btwaf/rule
        chmod -R 666 /www/server/btwaf/total.json
        chmod -R 666 /www/server/btwaf/drop_ip.log
        echo '' > /www/server/nginx/conf/luawaf.conf
        chown -R root:root /www/server/btwaf/
        chown www:www /www/server/btwaf/*.json
        chown www:www /www/server/btwaf/drop_ip.log
        install_mbd
        mkdir -p /www/server/btwaf/totla_db/http_log
        if [ ! -f /www/server/btwaf/totla_db/totla_db.db ];then
                \cp -a -r $pluginPath/btwaf_lua/totla_db/totla_db.db $btwaf_path/totla_db/totla_db.db
                chown www:www /www/server/btwaf/totla_db/totla_db.db
                chmod 755 $btwaf_path/totla_db/totla_db.db
        fi
        chown www:www /www/server/btwaf/totla_db/totla_db.db
        /www/server/panel/pyenv/bin/python $pluginPath/white.py
        /www/server/panel/pyenv/bin/python $pluginPath/black.py
        /www/server/panel/pyenv/bin/python $pluginPath/update_btwaf.py

        if [ ! -f $btwaf_path/resty/memcached.lua ];then
                #做软连
                if [ -f /www/server/nginx/lualib/resty/memcached.lua ];then
                        #openrestry 兼容
                        echo "openresty兼容"
                        ln -s /www/server/nginx/lualib/resty  /www/server/btwaf
                fi 
        fi 
        chown www:www /www/server/btwaf/totla_db/totla_db.db
        rm -rf /www/server/btwaf/ngx
        rm -rf /www/server/btwaf/resty



        #安装bt_ipfter
        #关闭
        /etc/init.d/bt_ipfilter stop
        cd $pluginPath/bt_ipfilter
        bash bt_ipfilter_install.sh
        isStart=$(ps aux |grep -E "(bt-ipfilter)"|grep -v grep|grep -v "/etc/init.d/bt_ipfilter"|awk '{print $2}'|xargs)
        if [ "$isStart" == '' ];then
                bash bt_ipfilter_install.sh
        fi
        /etc/init.d/bt_ipfilter restart
        chmod 755 /www/server/btwaf/rule
        chmod 755 /www/server/btwaf/
        rm -rf /www/server/btwaf/ffijson.lua
        chown www:www -R /www/server/btwaf/totla_db/
        #chown www:www -R /www/server/btwaf/total/
        rm -rf /www/server/panel/plugin/btwaf/*.so

        chown www:www -R /www/server/btwaf/totla_db/http_log
        chown www:www -R /www/server/btwaf/totla_db/
        chown www:www -R  /www/server/btwaf/webshell_total

        chown www:www /www/server/btwaf/totla_db
        #chown www:www /www/server/btwaf/http_log
        chmod 755 /www/server/btwaf/totla_db
        chown root:root /www/server/btwaf/config.json
        chown root:root /www/server/btwaf/domains.json
        chown root:root /www/server/btwaf/site.json
        #chown root:root /www/server/btwaf/zhi.json
        chown root:root /www/server/btwaf/inc/1.json
        chown root:root /www/server/btwaf/inc/2.json
        chown root:root /www/server/btwaf/inc/3.json
        chown root:root /www/server/btwaf/inc/4.json
        chown root:root /www/server/btwaf/inc/5.json
        chown root:root /www/server/btwaf/inc/6.json
        chown root:root /www/server/btwaf/inc/7.json
        chown root:root /www/server/btwaf/inc/8.json
        chown www:www  /www/server/btwaf/rule/not_spider.json
        chown www:www  /www/server/btwaf/rule/get_spider.json
        rm -rf $pluginPath/bt_ipfilter

        #删除遗留文件
        rm -rf /www/server/btwaf/captcha
        rm -rf /www/server/btwaf/cms
        rm -rf /www/server/btwaf/js
        rm -rf /www/server/btwaf/total
        rm -rf /www/server/btwaf/1.json
        rm -rf /www/server/btwaf/2.json
        rm -rf /www/server/btwaf/3.json
        rm -rf /www/server/btwaf/4.json
        rm -rf /www/server/btwaf/5.json
        rm -rf /www/server/btwaf/6.json
        rm -rf /www/server/btwaf/7.json
        rm -rf /www/server/btwaf/ElementNode.lua
        rm -rf /www/server/btwaf/GeoLite2-City.mmdb
        rm -rf /www/server/btwaf/base.lua
        rm -rf /www/server/btwaf/bt_engine.lua
        rm -rf /www/server/btwaf/bt_engine.so
        rm -rf /www/server/btwaf/cjson.so
        rm -rf /www/server/btwaf/dns.lua
        rm -rf /www/server/btwaf/ipmatcher.lua
        rm -rf /www/server/btwaf/libmaxminddb.so
        rm -rf /www/server/btwaf/lsqlite3.so
        rm -rf /www/server/btwaf/maxminddb.lua
        rm -rf /www/server/btwaf/multipart.lua
        rm -rf /www/server/btwaf/php_engine.so
        rm -rf /www/server/btwaf/shell_check.json
        rm -rf /www/server/btwaf/webshell.json
        rm -rf /www/server/btwaf/webshell_url.json
        rm -rf /www/server/btwaf/xss_engine.lua
        rm -rf /www/server/btwaf/uuid.lua
        #rm -rf /www/server/btwaf/zhizhu*.json
        rm -rf /www/server/btwaf/zhi.lua
        rm -rf /www/server/btwaf/nday
        rm -rf /www/server/btwaf/zhi.json
        #rm -rf /www/server/btwaf/webshell.json
        rm -rf /www/server/btwaf/libbtengine.lua
        rm -rf /www/server/btwaf/libinjection.lua
        rm -rf /www/server/btwaf/libinjection.so
        rm -rf /www/server/btwaf/libphp.so
        rm -rf /www/server/btwaf/php_engine.lua
        rm -rf /www/server/panel/plugin/btwaf/.git
        rm -rf /www/server/btwaf/zhizhu1.json
        rm -rf /www/server/btwaf/zhizhu2.json
        rm -rf /www/server/btwaf/zhizhu3.json
        rm -rf /www/server/btwaf/zhizhu4.json
        rm -rf /www/server/btwaf/zhizhu5.json
        rm -rf /www/server/btwaf/zhizhu6.json
        rm -rf /www/server/btwaf/GeoLite2-Country.mmdb
        chown www:www -R /www/server/btwaf/picture

        chown www:www $btwaf_path/rule/customize_count.json

        cd /www/
        NGINX_VER=$(/www/server/nginx/sbin/nginx -v 2>&1|grep -oE 1.2[3456])
        if [ "${NGINX_VER}" ];then
                sed -i "/lua_package_path/d" /www/server/nginx/conf/nginx.conf
                \cp -rpa /www/server/nginx/lib/lua/* /www/server/btwaf
        fi
        NGINX_VER=$(/www/server/nginx/sbin/nginx -v 2>&1|grep -oE openresty)
        if [ "${NGINX_VER}" ];then
                sed -i "/lua_package_path/d" /www/server/nginx/conf/nginx.conf
                \cp -rpa /www/server/nginx/lualib/* /www/server/btwaf
        fi
        /etc/init.d/nginx restart
        /etc/init.d/nginx restart
        sleep 2
        para5=$(ps -aux |grep nginx |grep  /www/server/nginx/conf/nginx.conf | awk 'NR==2')
        if [ ! -n "$para5" ]; then 
                pkill -9 nginx
                /etc/init.d/nginx restart
        fi
        sleep 2
        para1=$(ps -aux |grep nginx |grep  /www/server/nginx/conf/nginx.conf | awk 'NR==2')
        parc2=$(netstat -nltp|grep nginx| grep 80|wc -l)
        if [ ! -n "$para1" ]; then 
                if [ $parc2 -eq 0 ]; then 
                        Cjson2
                        echo '正在修复中'
                        Install_LuaJIT
                        Install_sqlite3_for_nginx
                        luarocks install lua-cjson
                        /etc/init.d/nginx restart
                        para1=$(ps -aux |grep nginx |grep  /www/server/nginx/conf/nginx.conf | awk 'NR==2')
                        parc2=$(netstat -nltp|grep nginx| grep 80|wc -l)
                        if [ ! -n "$para1" ]; then 
                                /etc/init.d/nginx restart
                                parc2=$(netstat -nltp|grep nginx| grep 80|wc -l)
                                if [ $parc2 -eq 0 ]; then 
                                        /etc/init.d/nginx restart
                                fi
                        fi
                fi
        fi
        /etc/init.d/btwaf restart


        rm -rf $pluginPath/btwaf_lua
        rm -rf $pluginPath/LuaJIT-2.1.0-beta*
        rm -rf $pluginPath/lua-5.1.5*
        rm -rf $pluginPath/captcha.zip
        rm -rf $pluginPath/luarocks-3.5.0*
        rm -rf $pluginPath/GeoLite2-City.mmdb
        rm -rf $pluginPath/lsqlite3_fsl09y*
        rm -rf $pluginPath/lua-cjson-2.1.0*

        #检查btwaf.conf 配置文件是否存在
        if [ ! -f /www/server/panel/vhost/nginx/btwaf.conf ];then
                rm -rf /www/server/panel/plugin/btwaf
                echo '安装失败,配置文件不存在'
                echo '安装失败,建议重新安装一次试试'
                echo '5秒后结束安装进程！！！！'
                sleep 5
                echo '安装失败,配置文件不存在' > $install_tmp
                exit 1
        fi

        #检查0.btwaf_log_format.conf
        if [ ! -f /www/server/panel/vhost/nginx/0.btwaf_log_format.conf ];then
                rm -rf /www/server/panel/plugin/btwaf
                echo '安装失败,0.btwaf_log_format.conf配置文件不存在'
                echo '安装失败,建议重新安装一次试试'
                echo '5秒后结束安装进程！！！！'
                sleep 5
                echo '安装失败,0.btwaf_log_format.conf配置文件不存在' > $install_tmp
                exit 1
        fi

        #判断IP库文件是否安装成功
        if [ ! -f /www/server/btwaf/inc/GeoLite2-City.mmdb ];then
                rm -rf /www/server/panel/vhost/nginx/btwaf.conf
                /etc/init.d/nginx restart
                rm -rf /www/server/panel/plugin/btwaf
                echo '安装失败,IP库文件缺失'
                echo '安装失败,建议重新安装一次试试'
                echo '5秒后结束安装进程！！！！'
                sleep 5
                echo '安装失败,可能存在一些安全软件导致了IP库文件安装失败' > $install_tmp
                exit 1
        fi 

        #检查bt_engine.so 文件是否安装成功
        if [ ! -f /www/server/btwaf/inc/bt_engine.so ];then
                rm -rf /www/server/panel/vhost/nginx/btwaf.conf
                /etc/init.d/nginx restart
                rm -rf /www/server/panel/plugin/btwaf
                echo '安装失败,语义分析模块安装失败'
                echo '安装失败,建议可以先关闭云锁或其他的安全软件再安装一次'
                echo '5秒后结束安装进程！！！！'
                sleep 5
                echo '安装失败,存在云锁或者其他安全软件阻止了安装' > $install_tmp
                exit 1
        fi 
        #检查lsqlite3.so 文件是否安装成功
        if [ ! -f /www/server/btwaf/inc/lsqlite3.so ];then
                rm -rf /www/server/panel/vhost/nginx/btwaf.conf
                /etc/init.d/nginx restart
                rm -rf /www/server/panel/plugin/btwaf
                echo '安装失败,sqlite3数据库模块安装失败'
                echo '安装失败,建议可以先关闭云锁或其他的安全软件再安装一次'
                echo '5秒后结束安装进程！！！！'
                sleep 5
                echo '安装失败,存在云锁或者其他安全软件阻止了安装' > $install_tmp
                exit 1
        fi 

        #检查cjson.so 文件是否安装成功
        if [ ! -f /www/server/btwaf/inc/cjson.so ];then
                rm -rf /www/server/panel/vhost/nginx/btwaf.conf
                /etc/init.d/nginx restart
                rm -rf /www/server/panel/plugin/btwaf
                echo '安装失败,cjson模块安装不成功'
                echo '安装失败,建议可以先关闭云锁或其他的安全软件再安装一次'
                echo '5秒后结束安装进程！！！！'
                sleep 5
                echo '安装失败,存在云锁或者其他安全软件阻止了安装' > $install_tmp
                exit 1
        fi 
        #检查libmaxminddb.so php_engine.so 文件是否存在
        if [ ! -f /www/server/btwaf/inc/php_engine.so ];then
                rm -rf /www/server/panel/vhost/nginx/btwaf.conf
                /etc/init.d/nginx restart
                rm -rf /www/server/panel/plugin/btwaf
                echo '安装失败,可能存在云锁等其他的安全软件'
                echo '安装失败,建议可以先关闭云锁或其他的安全软件再安装一次'
                echo '5秒后结束安装进程！！！！'
                sleep 5
                echo '安装失败,存在云锁或者其他安全软件阻止了安装' > $install_tmp
                exit 1
        fi 

        if [ ! -f /www/server/btwaf/inc/libmaxminddb.so ];then
                rm -rf /www/server/panel/vhost/nginx/btwaf.conf
                /etc/init.d/nginx restart
                rm -rf /www/server/panel/plugin/btwaf
                echo '安装失败,可能存在云锁等其他的安全软件'
                echo '安装失败,建议可以先关闭云锁或其他的安全软件再安装一次'
                echo '5秒后结束安装进程！！！！'
                sleep 5
                echo '安装失败,存在云锁或者其他安全软件阻止了安装' > $install_tmp
                exit 1
        fi 



        curl http://127.0.0.1 > /dev/null 2>&1
        is_status=$(netstat -nltp|grep nginx| grep 80|wc -l)
        if [ $is_status -eq 0 ]; then 
                rm -rf /www/server/panel/vhost/nginx/btwaf.conf
                /etc/init.d/nginx restart
                rm -rf /www/server/panel/plugin/btwaf
                echo '安装失败,可以重新安装一次试试'
                echo '安装失败,可能不兼容该Nginx、请切换一个Nginx版本后重新安装'
                echo '5秒后结束安装进程！！！！'
                sleep 7
                echo '安装失败,可能不兼容该Nginx、请切换一个Nginx版本后重新安装' > $install_tmp
        else
                echo '安装完成'
                echo '安装完成' > $install_tmp
        fi

}


Cjson2()
{
        cd $pluginPath/
        tar zxvf lua-cjson-2.1.0.tar.gz
        cd $pluginPath/lua-cjson-2.1.0
        make clean
        make 
        make install
        cd ..
        #rm -rf lua-cjson-2.1.0
        cp -a -r /usr/local/lib/lua/5.1/cjson.so /www/server/btwaf/inc/cjson.so
}

Install_cjson()
{
        #判断/www/server/btwaf/inc/ 目录是否存在不存在则创建
        if [ ! -d /www/server/btwaf/inc/ ];then
                mkdir -p /www/server/btwaf/inc/
        fi
        #/usr/lib/lua/5.1/ 没有这个目录则创建
        if [ ! -d /usr/lib/lua/5.1/ ];then
                mkdir -p /usr/lib/lua/5.1/
        fi
        Install_LuaJIT
        if [ -f /usr/bin/yum ];then
                isInstall=`rpm -qa |grep lua-devel`
                if [ "$isInstall" == "" ];then
                        yum install lua lua-devel -y
                        yum install lua-socket -y
                fi
        else
                isInstall=`dpkg -l|grep liblua5.1-0-dev`
                if [ "$isInstall" == "" ];then
                        apt-get install lua5.1 lua5.1-dev -y
                fi
        fi

        if [ -f /usr/local/lib/lua/5.1/cjson.so ];then
                        is_jit_cjson=$(luajit -e "require 'cjson'" 2>&1|grep 'undefined symbol: ')
                        if [ "$is_jit_cjson" != "" ];then
                                rm -f /usr/local/lib/lua/5.1/cjson.so
                                rm -rf /www/server/btwaf/inc/cjson.so
                        fi
        fi

        if [ ! -f /www/server/btwaf/inc/cjson.so ];then
                cd $pluginPath/
                echo "安装Cjson"
                tar zxvf lua-cjson-2.1.0.tar.gz
                #rm -f lua-cjson-2.1.0.tar.gz
                cd $pluginPath/lua-cjson-2.1.0
                make clean
                make 
                make install
                echo "安装完Cjson"
                sleep 1
                is_jit_cjson=$(luajit -e "require 'cjson'")
                echo $is_jit_cjson
                echo `md5sum cjson.so`
                cp -a -r $pluginPath/lua-cjson-2.1.0/cjson.so /www/server/btwaf/inc/cjson.so
                cp -a -r $pluginPath/lua-cjson-2.1.0/cjson.so /usr/lib64/lua/5.1/cjson.so
                cp -a -r $pluginPath/lua-cjson-2.1.0/cjson.so /usr/lib/lua/5.1/cjson.so
                cd ..
                #rm -rf lua-cjson-2.1.0

        else
                if [ -d "/usr/lib64/lua/5.1" ];then
                        ln -sf /usr/local/lib/lua/5.1/cjson.so /usr/lib64/lua/5.1/cjson.so
                fi

                if [ -d "/usr/lib/lua/5.1" ];then
                        ln -sf /usr/local/lib/lua/5.1/cjson.so /usr/lib/lua/5.1/cjson.so
                fi
        fi
        cd /www/server/btwaf/inc
        is_jit_cjson=$(luajit -e "require 'cjson'" 2>&1|grep 'undefined symbol: ')
        if [ "$is_jit_cjson" != "" ];then
                echo "Cjson置换"
                rm -f /usr/local/lib/lua/5.1/cjson.so
                chmod +x $pluginPath/cjson.so
                \cp -a -r $pluginPath/cjson.so /www/server/btwaf/inc/cjson.so
                \cp -a -r $pluginPath/cjson.so /usr/local/lib/lua/5.1/cjson.so
        fi 
}


Install_socket()
{
        if [ ! -f /usr/local/lib/lua/5.1/socket/core.so ];then
                wget -O luasocket-master.zip $download_Url/install/src/luasocket-master.zip -T 20
                unzip luasocket-master.zip
                rm -f luasocket-master.zip
                cd luasocket-master
                export C_INCLUDE_PATH=/usr/local/include/luajit-2.0:$C_INCLUDE_PATH
                make
                make install
                cd ..
                rm -rf luasocket-master
        fi
        rm -rf /usr/share/lua/5.1/socket

        if [ ! -d /usr/share/lua/5.1/socket ]; then
                if [ -d /usr/lib64/lua/5.1 ];then
                        mkdir /usr/lib64/lua/5.1/
                        rm -rf /usr/lib64/lua/5.1/socket /usr/lib64/lua/5.1/mime
                        ln -sf /usr/local/lib/lua/5.1/socket /usr/lib64/lua/5.1/socket
                        ln -sf /usr/local/lib/lua/5.1/mime /usr/lib64/lua/5.1/mime
                else
                        rm -rf /usr/lib/lua/5.1/socket /usr/lib/lua/5.1/mime
                        mkdir -p /usr/lib/lua/5.1/
                        ln -sf /usr/local/lib/lua/5.1/socket /usr/lib/lua/5.1/socket
                        ln -sf /usr/local/lib/lua/5.1/mime /usr/lib/lua/5.1/mime
                fi
                rm -rf /usr/share/lua/5.1/mime.lua /usr/share/lua/5.1/socket.lua /usr/share/lua/5.1/socket
                mkdir -p /usr/share/lua/5.1/ 
                mkdir -p /www/server/btwaf/
                ln -sf /usr/local/share/lua/5.1/mime.lua /usr/share/lua/5.1/mime.lua
                ln -sf /usr/local/share/lua/5.1/socket.lua /usr/share/lua/5.1/socket.lua
                ln -sf /usr/local/share/lua/5.1/socket /usr/share/lua/5.1/socket

                ln -sf /usr/local/share/lua/5.1/mime.lua /www/server/btwaf/mime.lua
                ln -sf /usr/local/share/lua/5.1/socket.lua /www/server/btwaf/socket.lua
                ln -sf /usr/local/share/lua/5.1/socket /www/server/btwaf/socket
        fi
}

Uninstall_btwaf()
{
        /etc/init.d/btwaf stop
        #卸载计划任务
        btpython /www/server/panel/plugin/btwaf/uninstall.py
        rm -rf /www/server/panel/static/btwaf
        rm -f /www/server/panel/vhost/nginx/btwaf.conf
        rm -rf /www/server/panel/plugin/btwaf/
        #rm -rf /usr/local/lib/lua/5.1/cjson.so
        #rm -rf /www/server/btwaf/lsqlite3.so
        NGINX_VER=$(/www/server/nginx/sbin/nginx -v 2>&1|grep -oE 1.2[345])
        if [ "${NGINX_VER}" ];then
                sed -i '/include proxy\.conf;/a \        lua_package_path "/www/server/nginx/lib/lua/?.lua;;";' /www/server/nginx/conf/nginx.conf
                rm -rf /www/server/btwaf/ngx/
                rm -rf /www/server/btwaf/resty/
        fi
        NGINX_VER=$(/www/server/nginx/sbin/nginx -v 2>&1|grep -oE openresty)
        if [ "${NGINX_VER}" ];then
                #sed -i "/lua_package_path/d" /www/server/nginx/conf/nginx.conf
                rm -rf /www/server/btwaf/ngx/
                rm -rf /www/server/btwaf/resty/
                rm -rf /www/server/btwaf/librestysignal.so
                rm -rf /www/server/btwaf/rds
                rm -rf /www/server/btwaf/redis
                rm -rf /www/server/btwaf/tablepool.lua
        fi
        /etc/init.d/nginx reload
        echo '-,0.0.0.0' >/dev/shm/.bt_ip_filter
}

Check_install(){
if [ ! -d /www/server/btwaf/socket ]; then
        Install_btwaf
fi

}

if [ "${1}" == 'install' ];then
        Install_btwaf
elif  [ "${1}" == 'update' ];then
        Install_btwaf
elif [ "${1}" == 'uninstall' ];then
        Uninstall_btwaf