#!/bin/bash
# chkconfig: 2345 55 25
# description: BT-WAF Task Service

### BEGIN INIT INFO
# Provides:          BT-WAF Task Service
# Required-Start:    $all
# Required-Stop:     $all
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: starts BT-WAF Task Service
# Description:       starts the BT-WAF Task Service
### END INIT INFO
target_dir=/www/server/panel/plugin/btwaf
cd $target_dir

if [ -d $target_dir/logs ];then
  echo ''
else
  mkdir $target_dir/logs
fi

server_start()
{
        isStart=$(ps aux |grep 'BT-WAF'|grep -v grep|awk '{print $2}')
        log_file=$target_dir/logs/logs.log
        if [ "$isStart" == '' ];then
                echo -e "Starting BT-WAF ... \c"
                chmod +x $target_dir/BT-WAF
                nohup $target_dir/BT-WAF >> $log_file 2>&1 &
                echo $! > $target_dir/BT-WAF.pid

                sleep 0.2
                isStart=$(ps aux |grep 'BT-WAF'|grep -v grep|awk '{print $2}')
                if [ "$isStart" == '' ];then
                        echo -e "\033[31mfailed\033[0m"
                        echo '------------------------------------------------------'
                        tail -n 20 $log_file
                        echo '------------------------------------------------------'
                        echo -e "\033[31mError: BT-Notice service startup failed.\033[0m"
                        return;
                fi
                echo -e "       \033[32mdone\033[0m"
        else
                echo "Starting BT-WAF..  (pid $isStart) already running"
        fi
}

service_stop()
{
    echo -e "Stopping BT-WAF...\c";
    pids=$(ps aux |grep 'BT-WAF'|grep -v grep|awk '{print $2}')
    arr=($pids)
    for p in ${arr[@]}
    do
            kill -9 $p
    done
    echo -e "   \033[32mdone\033[0m"
}

service_status()
{
        isStart=$(ps aux |grep 'BT-WAF'|grep -v grep|awk '{print $2}')
        if [ "$isStart" != '' ];then
                echo -e "\033[32mBT-WAF  (pid $(echo $isStart)) already running\033[0m"
        else
                echo -e "\033[31mBT-WAF  not running\033[0m"
        fi
#        $target_dir/tools get_status
}

case "$1" in
        'start')
                server_start
                ;;
        'stop')
                service_stop
                ;;
        'restart')
                service_stop
                sleep 1
                server_start
                ;;
        'status')
                service_status
                ;;
        'default')
                                # echo "Usage: $0 {start|stop|restart|status}"
                ;;
esac