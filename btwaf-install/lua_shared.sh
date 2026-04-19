#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

SPIDER_MEM="10m"
BTWAF_MEM="30m"
DROP_IP_MEM="10m"
DROP_SUM_MEM="30m"
BTWAF_DATA_MEM="30m"
IPINFO_MEM="10m";
CC_MEM="30m";
IP_MEM="10m";
CHECKLRU="30m";
IP_TMP_MEM="25m";
MEM_TOTAL=$(free -m | grep Mem | awk '{print  $2}')
if [[ "${MEM_TOTAL}" -gt 4000 && "${MEM_TOTAL}" -le 8000 ]];then
	SPIDER_MEM="10m"
	BTWAF_MEM="50m"
	DROP_IP_MEM="20m"
	DROP_SUM_MEM="35m"
	BTWAF_DATA_MEM="50m"
	IPINFO_MEM="30m";
	CC_MEM="30m";
	IP_MEM="30m";
	IP_TMP_MEM="30m";
	CHECKLRU="40m";
elif [[ "${MEM_TOTAL}" -gt 8000 && "${MEM_TOTAL}" -le 16000 ]]; then
	SPIDER_MEM="15m"
	BTWAF_MEM="50m"
	DROP_IP_MEM="20m"
	DROP_SUM_MEM="40m"
	BTWAF_DATA_MEM="80m"
	IPINFO_MEM="40m";
	CC_MEM="35m";
	IP_MEM="40m";
	IP_TMP_MEM="40m";
	CHECKLRU="80m";
elif [[ "${MEM_TOTAL}" -gt 16000 && "${MEM_TOTAL}" -le 32000 ]]; then
	SPIDER_MEM="20m"
	BTWAF_MEM="60m"
	DROP_IP_MEM="30m"
	DROP_SUM_MEM="45m"
	BTWAF_DATA_MEM="100m"
	IPINFO_MEM="50m";
	IPINFO="50m";
	CC_MEM="40m";
	CHECKLRU="90m";
	IP_MEM="50m";
	IP_TMP_MEM="50m";
elif [[ "${MEM_TOTAL}" -gt 32000 && "${MEM_TOTAL}" -le 64000 ]]; then
	SPIDER_MEM="25m"
	BTWAF_MEM="100m"
	DROP_IP_MEM="30m"
	DROP_SUM_MEM="50m"
	BTWAF_DATA_MEM="120m"
	IPINFO_MEM="60m";
	CC_MEM="45m";
	IP_MEM="60m";
	IP_TMP_MEM="60m";
	CHECKLRU="100m";
elif [[ "${MEM_TOTAL}" -gt 64000 && "${MEM_TOTAL}" -le 128000 ]]; then
	SPIDER_MEM="30m"
	BTWAF_MEM="130m"
	DROP_IP_MEM="30m"
	DROP_SUM_MEM="60m"
	BTWAF_DATA_MEM="180m"
	IPINFO_MEM="80m";
	CC_MEM="70m";
	IP_MEM="50m";
	IP_TMP_MEM="70m";
	CHECKLRU="150m";
elif [ "${MEM_TOTAL}" -gt 128000 ]; then
	SPIDER_MEM="30m"
	BTWAF_MEM="200m"
	DROP_IP_MEM="30m"
	DROP_SUM_MEM="70m"
	BTWAF_DATA_MEM="250m"
	IPINFO_MEM="100m";
	CC_MEM="100m";
	IP_MEM="50m";
	IP_TMP_MEM="80m";
	CHECKLRU="200m";
fi

sed -i "s/spider 10m/spider ${SPIDER_MEM}/g" /www/server/panel/vhost/nginx/btwaf.conf
sed -i "s/btwaf 30m/btwaf ${BTWAF_MEM}/g" /www/server/panel/vhost/nginx/btwaf.conf
sed -i "s/drop_ip 10m/drop_ip ${DROP_IP_MEM}/g" /www/server/panel/vhost/nginx/btwaf.conf
sed -i "s/drop_sum 30m/drop_sum ${DROP_SUM_MEM}/g" /www/server/panel/vhost/nginx/btwaf.conf
sed -i "s/btwaf_data 30m/btwaf_data ${BTWAF_DATA_MEM}/g" /www/server/panel/vhost/nginx/btwaf.conf
sed -i "s/ipinfo 10m/ipinfo ${IPINFO_MEM}/g" /www/server/panel/vhost/nginx/btwaf.conf
sed -i "s/cc 30m/cc ${CC_MEM}/g" /www/server/panel/vhost/nginx/btwaf.conf
sed -i "s/ip 10m/ip ${IP_MEM}/g" /www/server/panel/vhost/nginx/btwaf.conf
sed -i "s/checklru 30m/checklru ${CHECKLRU}/g" /www/server/panel/vhost/nginx/btwaf.conf
sed -i "s/ip_tmp 25m/ip_tmp ${IP_TMP_MEM}/g" /www/server/panel/vhost/nginx/btwaf.conf