#!/bin/bash

# 关闭clash服务
PID_NUM=`ps -ef | grep [c]lash-linux-a | wc -l`
PID=`ps -ef | grep [c]lash-linux-a | awk '{print $2}'`
if [ $PID_NUM -ne 0 ]; then
	kill -9 $PID
	# ps -ef | grep [c]lash-linux-a | awk '{print $2}' | xargs kill -9
fi


echo -e "请手动执行命令加载环境变量: source /etc/profile.d/clash.sh\n"
echo -e "\n服务关闭成功，请执行以下命令关闭系统代理：proxyoff\n"
