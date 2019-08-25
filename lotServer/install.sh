#!/bin/bash
# Copyright (C) 2015 AppexNetworks
# Author:	Len
# Date:		Aug, 2015

export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"

ROOT_PATH=/appex
SHELL_NAME=lotServer.sh
PRODUCT_NAME=LotServer
PRODUCT_ID=lotServer
interactiveMode=1

[ -w / ] || {
	echo "You are not running $PRODUCT_NAME Installer as root. Please rerun as root"
	exit 1
}

if [ $# -ge 1 -a "$1" == "uninstall" ]; then
	acceExists=$(ls $ROOT_PATH/bin/acce* 2>/dev/null)
    [ -z "$acceExists" ] && {
        echo "$PRODUCT_NAME is not installed!"
        exit
    }
    $ROOT_PATH/bin/$SHELL_NAME uninstall
    exit
fi

function disp_usage() {
	echo "Usage:  $INVOKER"
	echo "   or:  $INVOKER  [-in inbound_bandwidth] [-out outbound_bandwidth] [-i interface] [-r] [-t shortRttMS] [-gso <0|1>] [-rsc <0|1>] [-b]"
	echo "   or:  $INVOKER uninstall"
	echo
	echo -e "  -b, --boot\t\tauto load $PRODUCT_NAME on linux start-up"
	echo -e "  -gso\t\t0 or 1, enable or disable gso"
	echo -e "  -h, --help\t\tdisplay this help and exit"
	echo -e "  -i\t\t\tspecify your accelerated interface(s), default eth0"
	echo -e "  -in\t\t\tinbound bandwidth, default 1000000 kbps"
	echo -e "  -out\t\t\toutbound bandwidth, default 1000000 kbps"
	echo -e "  -r\t\t\tstart $PRODUCT_NAME after installation"
	echo -e "  -rsc\t\t0 or 1, enable or disable rsc"
	echo -e "  -t\t\t\tspecify shortRttMS, default 0"
	echo -e "  uninstall\t\tuninstall $PRODUCT_NAME"
	exit 0
}

function disp_usage_lite() {
	echo "Usage: $INVOKER [-in inbound_bandwidth] [-out outbound_bandwidth] [-i interface] [-r] [-t shortRttMS] [-gso <0|1>] [-rsc <0|1>] [-b]"
	exit 0
}

initValue() {
	while [ -n "$1" ]; do
	case "$1" in
		-b|-boot)
			boot='y'
			shift 1
			;;
		-i)
			if [ -z "$2" -o "${2#-*}" != "$2" ]; then
				disp_usage_lite
			else
				accif=$2
			fi
			shift 2
			interactiveMode=0
			;;
		-r)
			startNow='y'
			shift 1
			;;
		-s)
			showDetail=1
			shift 1
			;;
		-in)
			if [ -z "$2" -o "${2#-*}" != "$2" ]; then
				disp_usage_lite
			else
				waninkbps=$2
			fi
			shift 2
			interactiveMode=0
			;;
		-out)
			if [ -z "$2" -o "${2#-*}" != "$2" ]; then
				disp_usage_lite
			else
				wankbps=$2
			fi
			shift 2
			interactiveMode=0
			;;
		-h|--help)
			disp_usage
			exit 0
			;;
		-x)
			shift 1
			;;
		-t)
			if [ -z "$2" -o "${2#-*}" != "$2" ]; then
				disp_usage_lite
			else
				shortRttMS=$2
			fi
			shift 2
			;;
		-gso)
			if [ -z "$2" -o "${2#-*}" != "$2" ]; then
				disp_usage_lite
			else
				gso=$2
			fi
			shift 2
			;;
		-rsc)
			if [ -z "$2" -o "${2#-*}" != "$2" ]; then
				disp_usage_lite
			else
				rsc=$2
			fi
			shift 2
			;;
		
		*)
			echo "$0: unrecognized option '$1'"
			echo
			disp_usage
			exit 1
			;;
	esac
	done
}

[ $# -gt 0 ] && {
	initValue "$@"
}


# Locate which
WHICH=`which ls 2>/dev/null`
[ $? -gt 0 ] && {
	echo '"which" not found, please install "which" using "yum install which" or "apt-get install which" according to your linux distribution'
	exit 1
}

IPCS=`which ipcs 2>/dev/null`
[  $? -eq 0 ] && {
    maxSegSize=`ipcs -l | awk -F= '/max seg size/ {print $2}'`
    maxTotalSharedMem=`ipcs -l | awk -F= '/max total shared memory/ {print $2}'`
    [ $maxSegSize -eq 0 -o $maxTotalSharedMem -eq 0 ] && {
        echo "$PRODUCT_NAME needs to use shared memory, please configure the shared memory according to the following link: "
        exit 1
    }
}

ip2long() {
	local IFS='.'
	read ip1 ip2 ip3 ip4 <<<"$1"
	echo $((ip1*(1<<24)+ip2*(1<<16)+ip3*(1<<8)+ip4))
	#echo "$ip1 $ip2 $ip3 $ip4"
}

postInstall() {
	local verName=$(cat $ROOT_PATH/etc/config | awk -F- '/^apxexe=/ {print $2}')
	local intVerName=$(ip2long $verName)
	local boundary
	
	boundary=$(ip2long '3.11.20.10')
	[ $intVerName -ge $boundary ] && {
		# if acce version greater than 3.11.20.10, set initial taskSchedDelay value to "100 100"
		if [ -n "$(grep taskSchedDelay $ROOT_PATH/etc/config)" ]; then
			sed -i "s/^taskSchedDelay=.*/taskSchedDelay=\"100 100\"/" $ROOT_PATH/etc/config
		else
			sed -i "/^txCongestObey=.*/taskSchedDelay=\"100 100\"" $ROOT_PATH/etc/config
		fi
	}
}

addStartUpLink() {
	grep -E "CentOS|Fedora|Red.Hat" /etc/issue >/dev/null
	[ $? -eq 0 ] && {
		ln -sf $ROOT_PATH/bin/$SHELL_NAME /etc/rc.d/init.d/$PRODUCT_ID
		[ -z "$boot" -o "$boot" = "n" ] && return
		CHKCONFIG=`which chkconfig`
		if [ -n "$CHKCONFIG" ]; then
			chkconfig --add $PRODUCT_ID >/dev/null 2>&1
		else
			echo "Error, Please install 'chkconfig', and run 'chkconfig --add $PRODUCT_ID' to auto start." 
		fi
	}
	grep "SUSE" /etc/issue >/dev/null
	[ $? -eq 0 ] && {
		ln -sf $ROOT_PATH/bin/$SHELL_NAME /etc/rc.d/$PRODUCT_ID
		[ -z "$boot" -o "$boot" = "n" ] && return
		CHKCONFIG=`which chkconfig`
		if [ -n "$CHKCONFIG" ]; then
			chkconfig --add $PRODUCT_ID >/dev/null 2>&1
		else
			echo "Error, Please install 'chkconfig', and run 'chkconfig --add $PRODUCT_ID' to auto start." 
		fi
	}
	grep -E "Ubuntu|Debian" /etc/issue >/dev/null
	[ $? -eq 0 ] && {
		ln -sf $ROOT_PATH/bin/$SHELL_NAME /etc/init.d/$PRODUCT_ID
		[ -z "$boot" -o "$boot" = "n" ] && return 
		CHKCONFIG=`which update-rc.d`
		if [ -n "$CHKCONFIG" ]; then
		        update-rc.d -f $PRODUCT_ID remove >/dev/null 2>&1
			update-rc.d $PRODUCT_ID defaults >/dev/null 2>&1
		else
			echo "Error, Please install 'update-rc.d', and run 'update-rc.d $PRODUCT_ID defaults' to auto start." 
		fi
	}
}

[ -d $ROOT_PATH/bin ] || mkdir -p $ROOT_PATH/bin
[ -d $ROOT_PATH/etc ] || mkdir -p $ROOT_PATH/etc
[ -d $ROOT_PATH/log ] || mkdir -p $ROOT_PATH/log
cd $(dirname $0)
dt=`date +%Y-%m-%d_%H-%M-%S`
[ -f $ROOT_PATH/etc/config ] && mv -f $ROOT_PATH/etc/config $ROOT_PATH/etc/.config_$dt.bak

cp -f apxfiles/bin/* $ROOT_PATH/bin/
cp -f apxfiles/etc/* $ROOT_PATH/etc/
chmod +x $ROOT_PATH/bin/*

[ -f $ROOT_PATH/etc/.config_$dt.bak ] && {
	while read _line; do
		item=$(echo $_line | awk -F= '/^[^#]/ {print $1}')
		val=$(echo $_line | awk -F= '/^[^#]/ {print $2}' | sed 's#\/#\\\/#g')
		[ -n "$item" -a "$item" != "accpath" -a "$item" != "apxexe" -a "$item" != "apxlic" -a "$item" != "installerID" -a "$item" != "email" -a "$item" != "serial" ] && {
			if [ -n "$(grep $item $ROOT_PATH/etc/config)" ]; then
				sed -i "s/^$item=.*/$item=$val/" $ROOT_PATH/etc/config
			else
				sed -i "/^engineNum=.*/a$item=$val" $ROOT_PATH/etc/config
			fi
		}
	done<$ROOT_PATH/etc/.config_$dt.bak
}

postInstall

[ -f apxfiles/expiredDate ] && {
    echo -n "Expired date: "
    cat apxfiles/expiredDate
    echo
}

echo "Installation done!"
echo
 
# Set acc inf
echo ----
echo You are about to be asked to enter information that will be used by $PRODUCT_NAME,
echo there are several fields and you can leave them blank,
echo 'for all fields there will be a default value.'
echo ----

[ $interactiveMode -eq 1 -a -z "$accif" ] && {
	# Set acc inf
	echo -n "Enter your accelerated interface(s) [eth0]: "
	read accif
}
[ $interactiveMode -eq 1 -a -z "$wankbps" ] && {
	echo -n "Enter your outbound bandwidth [1000000 kbps]: "
	read wankbps
}
[ $interactiveMode -eq 1 -a -z "$waninkbps" ] && {
	echo -n "Enter your inbound bandwidth [1000000 kbps]: "
	read waninkbps
}
[ $interactiveMode -eq 1 -a -z "$shortRttMS" ] && {
	echo -e "\033[30;40;1m"
	echo 'Notice:After set shorttRtt-bypass value larger than 0,' 
	echo 'it will bypass(not accelerate) all first flow from same 24-bit'
	echo 'network segment and the flows with RTT lower than the shortRtt-bypass value'
	echo -e "\033[0m"
	echo -n "Configure shortRtt-bypass [0 ms]: "
	read shortRttMS
}

[ -z "$shortRttMS" ] || [ -n "${shortRttMS//[0-9]}" ] && shortRttMS=0

[ -n "$accif" ] && sed -i "s/^accif=.*/accif=\"$accif\"/" $ROOT_PATH/etc/config
[ -n "$wankbps" ] && {
	wankbps=$(echo $wankbps | tr -d "[:alpha:][:space:]")
	sed -i "s/^wankbps=.*/wankbps=\"$wankbps\"/" $ROOT_PATH/etc/config
}
[ -n "$waninkbps" ] && {
	waninkbps=$(echo $waninkbps | tr -d "[:alpha:][:space:]")
	sed -i "s/^waninkbps=.*/waninkbps=\"$waninkbps\"/" $ROOT_PATH/etc/config
}
[ -n "$shortRttMS" ] && {
	shortRttMS=$(echo $shortRttMS | tr -d "[:alpha:][:space:]")
	sed -i "s/^shortRttMS=.*/shortRttMS=\"$shortRttMS\"/" $ROOT_PATH/etc/config
}

[ -n "$gso" ] && {
	gso=$(echo $gso | tr -d "[:alpha:][:space:]")
	[ "$gso" = "1" ] && gso=1 || gso=0
	sed -i "s/^gso=.*/gso=\"$gso\"/" $ROOT_PATH/etc/config
}

[ -n "$rsc" ] && {
	rsc=$(echo $rsc | tr -d "[:alpha:][:space:]")
	[ "$rsc" = "1" ] && rsc=1 || rsc=0
	sed -i "s/^rsc=.*/rsc=\"$rsc\"/" $ROOT_PATH/etc/config
}

[ $interactiveMode -eq 1 -a -z "$boot" ] && {
	while [ "$boot" != 'y' -a "$boot" != 'n' -a "$boot" != 'Y' -a "$boot" != 'N'  ]; do
		echo -n "Auto load $PRODUCT_NAME on linux start-up? [n]:"
		read boot
		[ -z "$boot" ] && boot=n
	done
	[ "$boot" = "N" ] && boot=n 
}

addStartUpLink

[ $interactiveMode -eq 1 -a -z "$startNow" ] && {
	while [ "$startNow" != 'y' -a "$startNow" != 'n' -a "$startNow" != 'Y' -a "$startNow" != 'N'  ]; do
		echo -n "Run $PRODUCT_NAME now? [y]:"
		read startNow
		[ -z "$startNow" ] && startNow=y
	done
}

[ "$startNow" = "y" -o "$startNow" = "Y" ] && {
	$ROOT_PATH/bin/$SHELL_NAME stop >/dev/null 2>&1
	$ROOT_PATH/bin/$SHELL_NAME start 
}
