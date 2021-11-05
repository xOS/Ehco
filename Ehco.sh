#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

cur_dir=`pwd`

#获取键盘输入
get_char(){
	SAVEDSTTY=`stty -g`
	stty -echo
	stty cbreak
	dd if=/dev/tty bs=1 count=1 2> /dev/null
	stty -raw
	stty echo
	stty $SAVEDSTTY
}

sh_ver="1.1.2"
#定义一些颜色
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"
mkdir /etc/ehco/
ehco_conf_path="/etc/ehco/config.json"
now_ver_file="/etc/ehco/ver.txt"

#确保本脚本在ROOT下运行
[[ $EUID -ne 0 ]] && echo -e "[${red}错误${plain}]请以ROOT运行本脚本！" && exit 1

check_sys(){
	echo "现在开始检查你的系统是否支持"
	#判断是什么Linux系统
	if [[ -f /etc/redhat-release ]]; then
		release="Centos"
	elif cat /etc/issue | grep -q -E -i "debian"; then
		release="Debian"
	elif cat /etc/issue | grep -q -E -i "ubuntu"; then
		release="Ubuntu"
	elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
		release="Centos"
	elif cat /proc/version | grep -q -E -i "debian"; then
		release="Debian"
	elif cat /proc/version | grep -q -E -i "ubuntu"; then
		release="Ubuntu"
	elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
		release="Centos"
	fi
	bit=`uname -m`
	
	#判断内核版本
	kernel_version=`uname -r | awk -F "-" '{print $1}'`
	kernel_version_full=`uname -r`
	net_congestion_control=`cat /proc/sys/net/ipv4/tcp_congestion_control | awk '{print $1}'`
	net_qdisc=`cat /proc/sys/net/core/default_qdisc | awk '{print $1}'`
	kernel_version_r=`uname -r | awk '{print $1}'`
	echo "系统版本为: $release $version $bit 内核版本为: $kernel_version_r"
	
	if [ $release = "Centos" ]
	then
		yum -y install wget jq
		sysctl_dir="/usr/lib/systemd/system/"
		full_sysctl_dir=${sysctl_dir}"ehco.service"
	elif [ $release = "Debian" ]
	then
		apt-get install wget jq -y
		sysctl_dir="/etc/systemd/system/"
		full_sysctl_dir=${sysctl_dir}"ehco.service"
	elif [ $release = "Ubuntu" ]
	then
		apt-get install wget jq -y
		sysctl_dir="/lib/systemd/system/"
		full_sysctl_dir=${sysctl_dir}"ehco.service"
	else
		echo -e "[${red}错误${plain}]不支持当前系统"
		exit 1
	fi
}
check_sys

Landing_Config(){
	clear
	echo "现在开始配置落地机"
	echo ""
	read -p "请输入落地机需要监听的本地端口:" server_port
	[ -z "${server_port}" ]
	echo ""
	read -p "请输入落地机隧道的端口:" listen_port
	[ -z "${listen_port}" ]
	echo ""
	if [ ! -f $full_sysctl_dir ]; then
		echo '
[Unit]
Description=Ehco
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service
[Service]
LimitNOFILE=32767 
Type=simple
User=root
Restart=on-failure
RestartSec=5s
DynamicUser=true
ExecStart=/usr/local/bin/ehco -l 0.0.0.0:443 -lt mwss -r 127.0.0.1:1111
[Install]
WantedBy=multi-user.target' > ehco.service
		mv ehco.service $sysctl_dir
	fi
	sed -i 's/'443'/'${listen_port}'/g' $full_sysctl_dir
	sed -i 's/'1111'/'${server_port}'/g' $full_sysctl_dir
	echo "正在本机启动Echo隧道"
	systemctl daemon-reload
	systemctl start ehco.service
	systemctl enable ehco.service
	echo ""
	clear
	echo "启动成功并已设定为开机自启。Ehco 的通信端口为 ${listen_port} 请断开SSH连接，开始中转机的配置吧！"
	sleep 3s
	start_menu
}

#更新脚本
Update_Shell(){
	echo -e "当前版本为 [ ${sh_ver} ]，开始检测最新版本..."
	sh_new_ver=$(wget --no-check-certificate -qO- "https://cdn.jsdelivr.net/gh/xOS/Ehco/Ehco.sh"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1)
	[[ -z ${sh_new_ver} ]] && echo -e "${Error} 检测最新版本失败 !" && start_menu
	if [[ ${sh_new_ver} != ${sh_ver} ]]; then
		echo -e "发现新版本[ ${sh_new_ver} ]，是否更新？[Y/n]"
		read -p "(默认: y):" yn
		[[ -z "${yn}" ]] && yn="y"
		if [[ ${yn} == [Yy] ]]; then
			wget -N --no-check-certificate https://cdn.jsdelivr.net/gh/xOS/Ehco/Ehco.sh && chmod +x Ehco.sh
			echo -e "脚本已更新为最新版本[ ${sh_new_ver} ] !"
            sleep 3s
            start_menu
		else
			echo && echo "	已取消..." && echo
            sleep 3s
            start_menu
		fi
	else
		echo -e "当前已是最新版本[ ${sh_new_ver} ] !"
		sleep 3s
        start_menu
	fi
}

Forward_Config(){
	clear
	echo "现在开始配置中转机"
	echo ""
	echo "第二次执行代表添加第二个隧道中转"
	read -p "请输入落地机的IP地址或者域名:" ip
	[ -z "${ip}" ]
	echo ""
	read -p "请输入落地机的通信端口:" landing_port
	[ -z "${landing_port}" ]
	echo ""
	read -p "请输入本机的中转/监听端口(任意未被占用的端口即可):" local_port
	[ -z "${local_port}" ]
	echo ""
	if [ ! -f "/etc/ehco/config.json" ]; then
		echo '
		{
		"web_port": 9000,
  "web_token": "",
  "enable_ping": false,

  "relay_configs": [
  ]
}' > /etc/ehco/config.json
	fi
	JSON='{"listen":"0.0.0.0:local_port","listen_type":"raw","transport_type":"raw","tcp_remotes":["raw://ip:landing_port"],"udp_remotes":["ip:landing_port"]}'
	JSON=${JSON/local_port/$local_port};
	JSON=${JSON/landing_port/$landing_port};
	JSON=${JSON/landing_port/$landing_port};
	JSON=${JSON/ip/$ip};
	JSON=${JSON/ip/$ip};
	temp=`jq --argjson groupInfo $JSON '.relay_configs += [$groupInfo]' /etc/ehco/config.json`
	echo $temp > /etc/ehco/config.json
	if [ ! -f $full_sysctl_dir ]; then
		echo '
[Unit]
Description=Ehco
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service
[Service]
LimitNOFILE=32767 
Type=simple
User=root
Restart=on-failure
RestartSec=5s
DynamicUser=true
ExecStart=/usr/local/bin/ehco -c /etc/ehco/config.json
[Install]
WantedBy=multi-user.target' > ehco.service
		mv ehco.service $sysctl_dir
	fi
	echo "正在本机启动 Echo"
	systemctl daemon-reload
	systemctl start ehco.service
	systemctl enable ehco.service
	systemctl restart ehco.service
	echo ""
	clear
	echo "启动成功并已设定为开机自启。Ehco 的连接端口为 ${local_port} ！"
	sleep 3s
	start_menu
}

#获取 Ehco 进程 ID
check_pid(){
	PID=$(ps -ef| grep "ehco"| awk '{print $2}')
}

#更新 Ehco
Update_Ehco(){
    new_ver=$(wget -qO- https://api.github.com/repos/Ehco1996/ehco/releases| grep "tag_name"| head -n 1| awk -F ":" '{print $2}'| sed 's/\"//g;s/,//g;s/ //g;s/v//g')
	now_ver=$(cat ${now_ver_file})
	if [[ "${now_ver}" != "${new_ver}" ]]; then
		echo -e "${Info} 发现 Ehco 已有新版本 [ ${new_ver} ]，旧版本 [ ${now_ver} ]"
		read -e -p "是否更新 ? [Y/n] :" yn
		[[ -z "${yn}" ]] && yn="y"
		if [[ $yn == [Yy] ]]; then
			check_pid
			[[ ! -z $PID ]] && kill -9 ${PID}
			if [[ ${bit} == "x86_64" ]]; then
  	wget -N --no-check-certificate "https://github.com/Ehco1996/ehco/releases/download/v${new_ver}/ehco_${new_ver}_linux_amd64" -O ehco && chmod +x ehco && mv -f ehco /usr/local/bin/ehco 
  	echo "${new_ver}" > ${now_ver_file}
	fi
	if [[ ${bit} == "aarch64" ]]; then
  	wget -N --no-check-certificate "https://github.com/Ehco1996/ehco/releases/download/v${new_ver}/ehco_${new_ver}_linux_arm64" -O ehco && chmod +x ehco && mv -f ehco /usr/local/bin/ehco 
  	echo "${new_ver}" > ${now_ver_file}
	fi
            echo -e "-------${Green_font_prefix} Ehco 更新成功! ${Font_color_suffix}-------"
            sleep 3s
            start_menu
		fi
        sleep 3s
        start_menu
	else
		echo -e "${Info} 当前 Ehco 已是最新版本 [ ${new_ver} ]"
        sleep 3s
        start_menu
	fi
}

# 安装 Ehco
Install_Ehco(){
if [ ! -f "/usr/bin/ehco" ]; then
	echo -e "现在开始安装Ehco"
	new_ver=$(wget -qO- https://api.github.com/repos/Ehco1996/ehco/releases| grep "tag_name"| head -n 1| awk -F ":" '{print $2}'| sed 's/\"//g;s/,//g;s/ //g;s/v//g')
  	mkdir /etc/ehco
	if [[ ${bit} == "x86_64" ]]; then
  	wget -N --no-check-certificate "https://github.com/Ehco1996/ehco/releases/download/v${new_ver}/ehco_${new_ver}_linux_amd64" -O ehco && chmod +x ehco && mv ehco /usr/local/bin/ehco 
  	echo "${new_ver}" > ${now_ver_file}
	fi
	if [[ ${bit} == "aarch64" ]]; then
  	wget -N --no-check-certificate "https://github.com/Ehco1996/ehco/releases/download/v${new_ver}/ehco_${new_ver}_linux_arm64" -O ehco && chmod +x ehco && mv ehco /usr/local/bin/ehco 
  	echo "${new_ver}" > ${now_ver_file}
	fi
fi
echo "恭喜你，Echo已经安装完毕，现在开始配置并启动Echo服务"
echo ""
sleep 3s
        start_menu
}

#卸载Ehco
Uninstall_Ehco(){
    if test -o /usr/local/bin/ehco -o /etc/systemd/system/ehco.service -o /etc/ehco/config.json;then
    sleep 3s
	systemctl stop ehco.service
	systemctl disable ehco.service
    `rm -rf /usr/local/bin/ehco`
    `rm -rf /etc/systemd/system/ehco.service`
    echo "------------------------------"
    echo -e "-------${Green_font_prefix} Ehco 卸载成功! ${Font_color_suffix}-------"
    echo "------------------------------"
    sleep 3s
    start_menu
    else
    echo -e "-------${Red_font_prefix}Ehco 没有安装,卸载个锤子！${Font_color_suffix}-------"
    sleep 3s
    start_menu
    fi
}

start_menu(){
		clear
		echo && echo -e "Echo 安装脚本
————————————功能选择————————————
${green}1.${plain} 安装 Ehco
${green}2.${plain} 更新 Ehco
${green}3.${plain} 卸载 Ehco
${green}4.${plain} 配置中转机
${green}5.${plain} 配置落地机
${green}6.${plain} 永久关闭
${green}8.${plain} 重新启用
${green}7.${plain} 重启 Ehco
${green}9.${plain} 更新脚本
${green}0.${plain} 退出脚本
————————————————————————————————"
	read -p "请输入数字: " num
	case "$num" in
	1)
		Install_Ehco
		;;
	2)
		Update_Ehco
		;;
	3)
		Uninstall_Ehco
		;;
	4)
		Forward_Config
		;;
	5)
		Landing_Config
		;;
	6)
		systemctl stop ehco.service
		systemctl disable ehco.service
		sleep 2s
        start_menu
		;;
	7)
		systemctl start ehco.service
		systemctl enable ehco.service
		sleep 2s
        start_menu
		;;
	8)
		systemctl restart ehco.service
		sleep 2s
        start_menu
		;;
	9)
		Update_Shell
		;;
	0)
		exit 1
		;;
	*)
		clear
		echo -e "[${red}错误${plain}]:请输入正确数字[0-5]"
		sleep 3s
		start_menu
		;;
	esac
}
start_menu 
