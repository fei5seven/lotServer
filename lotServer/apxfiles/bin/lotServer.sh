#!/bin/bash
# Copyright (C) 2017 AppexNetworks
# Author:	Len
# Date:		May, 2017
# Version:	1.7.5.5
#
# chkconfig: 2345 20 15
# description: LotServer, accelerate your network
#
### BEGIN INIT INFO
# Provides: lotServer
# Required-Start: $network
# Required-Stop:
# Default-Start: 2 3 5
# Default-Stop: 0 1 6
# Description: Start LotServer daemon.
### END INIT INFO

[ -w / ] || {
	echo "You are not running LotServer as root. Please rerun as root" >&2
	exit 1
}

ROOT_PATH=/appex
SHELL_NAME=lotServer.sh
PRODUCT_NAME=LotServer
PRODUCT_ID=lotServer

[ -f $ROOT_PATH/etc/config ] || { echo "Missing config file: $ROOT_PATH/etc/config" >&2; exit 1; }
. $ROOT_PATH/etc/config 2>/dev/null

getCpuNum() {
	[ $usermode -eq 1 ] && {
		CPUNUM=1
		return
	}
	[ $VER_STAGE -eq 1 ] && {
		CPUNUM=1
		return
	}
	local num=$(cat /proc/stat | grep cpu | wc -l)
	local X86_64=$(uname -a | grep -i x86_64)
	
	if [ $VER_STAGE -ge 4 -a -n "$cpuID" ]; then
		CPUNUM=$(echo $cpuID | awk -F, '{print NF}')
	else
		CPUNUM=$(($num - 1))
		[ -n "$engineNum" ] && {
			[ $engineNum -gt 0 -a $engineNum -lt $num ] && CPUNUM=$engineNum
		}
	
		[ -z "$X86_64" -a $CPUNUM -gt 4 ] && CPUNUM=4
	fi
	[ -n "$1" -a -n "$X86_64" -a $CPUNUM -gt 4 ] && {
		local memTotal=$(cat /proc/meminfo | awk '/MemTotal/ {print $2}')
		local used=$(($CPUNUM * 800000)) #800M
		local left=$(($memTotal - $used))
		[ $left -lt 2000000 ] && {
			echo -en "$HL_START"
			echo "$PRODUCT_NAME Warning: $CPUNUM engines will be launched according to the config file. Your system's total RAM is $memTotal(KB), which might be insufficient to run all the engines without performance penalty under extreme network conditions. "
			echo -en "$HL_END"
		}
	}
}

function unloadModule() {
	lsmod | grep "appex$1 " >/dev/null && rmmod appex$1 2>/dev/null
}

userCancel() {
	echo
	pkill -0 $KILLNAME 2>/dev/null
	[ $? -ne 0 ] && exit 0
	
	getCpuNum
	for enum in $(seq $CPUNUM); do
		freeIf $((enum - 1))
	done
	
	pkill $KILLNAME
	for i in $(seq 30); do
		pkill -0 $KILLNAME
		[ $? -gt 0 ] && break
		sleep 1
		[ $i -eq 6 ] && echo 'It takes a long time than usual, please wait for a moment...'
		[ $i -eq 30 ] && pkill -9 $KILLNAME
	done
	
	local enum=0
	for enum in $(seq $CPUNUM); do
		unloadModule $((enum - 1))
	done
	[ -f $OFFLOAD_BAK ] && {
		chmod +x $OFFLOAD_BAK && /bin/bash $OFFLOAD_BAK 2>/dev/null
	}
	[ -f /var/run/$PRODUCT_ID.pid ] && {
		kill -9 $(cat /var/run/$PRODUCT_ID.pid)
		rm -f /var/run/$PRODUCT_ID.pid
	}
}

function activate() {
	local activate
	echo "$PRODUCT_NAME is not activated."
	printf "You can register an account from ${HL_START}http://$HOST${HL_END}\n"
	echo -en "If you have account already, type ${HL_START}y${HL_END} to continue: [y/n]"
	read activate
	[ $activate = 'y' -o $activate = 'Y' ] && $ROOT_PATH/bin/activate.sh
}

function configCPUId() {
	local eth=$accif
	[ -z "$eth" ] && return
	# if there are 2 or more acc interfaces, assemble RE for awk
	[ $(echo $eth | wc -w) -gt 1 ] && eth=$(echo $eth | tr ' ' '|')
	local intAffinities=0
	local selectedPhysicalCpu=''
	local pBitmask
	local match
	local matchedPhysicalCpu
	local suggestCpuID=''
	# if cpuID has been specified, return
	[ -n "$cpuID" ] && return
	local physicalCpuNum=$(cat /proc/cpuinfo | grep 'physical id' | sort | uniq | wc -l)
	[ $physicalCpuNum -eq 0 ] && {
		echo -en "$HL_START"
		echo "$PRODUCT_NAME Warning: failed to detect physical CPU info, option 'detectInterrupt' will be ignored."
		echo -en "$HL_END"
		return
		#which dmidecode>/dev/null 2>&1 && dmidecode | grep -i product | grep 'VMware Virtual' >/dev/null &&
	}
	# if there's only one physical cpu, return
	[ $physicalCpuNum -eq 1 ] && return
	local processorNum=$(cat /proc/cpuinfo | grep processor | wc -l)
	local processorNumPerCpu=$(($processorNum / $physicalCpuNum))
	
	local affinities=$(cat /proc/interrupts  | awk -v eth="(${eth}).*TxRx" ' {if($NF ~ eth) {sub(":", "", $1); print $1}}')
	local val
	for affinity in $affinities; do
	    [ -f /proc/irq/$affinity/smp_affinity ] && {
	        val=$(cat /proc/irq/$affinity/smp_affinity | sed -e 's/^[0,]*//')
	        [ -n "$val" ] && intAffinities=$((0x$val | $intAffinities))
	    }
	done
	[ $intAffinities -eq 0 ] && return
	
	for processor in $(seq 0 $processorNum); do
	    pBitmask=$((1 << $processor))
	    match=$(($pBitmask & $intAffinities))
	    [ $match -gt 0 ] && {
	        #matchedPhysicalCpu=$(($processor / $processorNumPerCpu))
			matchedPhysicalCpu=$(cat /proc/cpuinfo | grep 'physical id' | awk -v row=$processor -F: ' NR == row + 1 {print $2}')
			matchedPhysicalCpu=$(echo $matchedPhysicalCpu)
	        [  -z "$selectedPhysicalCpu" ] && selectedPhysicalCpu=$matchedPhysicalCpu
	        # if nic interrupts cross more than one physical cpu, return
	        [ $selectedPhysicalCpu -ne $matchedPhysicalCpu ] && return
	        [ -n "$suggestCpuID" ] && suggestCpuID="${suggestCpuID},"
	        suggestCpuID="${suggestCpuID}${processor}"
	    	[ $engineNum -gt 0 ] && {
	    		[ $(echo $suggestCpuID | tr ',' ' ' | wc -w) -ge $engineNum ] && continue
	    	}
	    }
	done
	[ -z $suggestCpuID ] && return
	cpuID=$suggestCpuID
}

initConf() {
	bn=$(basename $0)
	HL_START="\033[37;40;1m"
	HL_END="\033[0m"
	OFFLOAD_BAK=$ROOT_PATH/etc/.offload
	RUNCONFIG_BAK=$ROOT_PATH/etc/.runconfig
	CPUNUM=0
	VER_STAGE=1
	HOST=lotserver.cn
	[ "$bn" != "rtt" ] && trap "userCancel;" 1 2 3 6 9 15
	
	BOOTUP=color
	RES_COL=60
	MOVE_TO_COL="echo -en \\033[${RES_COL}G"
	SETCOLOR_SUCCESS="echo -en \\033[1;32m"
	SETCOLOR_FAILURE="echo -en \\033[1;31m"
	SETCOLOR_WARNING="echo -en \\033[1;33m"
	SETCOLOR_NORMAL="echo -en \\033[0;39m"

	RTT_VER_STAGE=1

	local rst=0
	[ -n "$accif" ] && accif=$(echo $accif)
	[ -n "$lanif" ] && lanif=$(echo $lanif) || lanif=''
		
	[ -z "$acc" ] && acc=1
	[ -z "$advacc" ] && advacc=1
	[ -z "$advinacc" ] && advinacc=0

	[ -z "$csvmode" ] && csvmode=0
	[ -z "$highcsv" ] && highcsv=0
	[ -z "$subnetAcc" ] && subnetAcc=0
	[ -z "$maxmode" ] && maxmode=0
	[ -z "$maxTxEffectiveMS" ] && maxTxEffectiveMS=0
	[ -z "$shaperEnable" ] && shaperEnable=1
	[ -z "$accppp" ] && accppp=0
	[ -n "$byteCache" ] && byteCacheEnable=$byteCache
	[ -z "$byteCacheEnable" ] && byteCacheEnable=0
	[ "$byteCache" = "1" ] && byteCacheEnable=1
	[ -z "$dataCompEnable" ] && {
		if [ $byteCacheEnable -eq 0 ]; then
			dataCompEnable=0
		else
			dataCompEnable=1
		fi
	}
	[ -n "$httpComp" ] && httpCompEnable=$httpComp
	[ -z "$httpCompEnable" ] && httpCompEnable=1
	[ $byteCacheEnable -eq 1 -a -z "$byteCacheMemory" ] && {
		echo "ERROR(CONFIG): missing config: byteCacheMemory"
		rst=1
	}
	[ $byteCacheEnable -eq 1 ] && {
		[ -n "$diskDev" -a -d "$diskDev" ] && {
			echo "ERROR(CONFIG): diskDev should be a file"
			rst=1
		}
	} 
	
	[ -z "$packetWrapper" ] && packetWrapper=256
	[ -z "$byteCacheDisk" ] && byteCacheDisk=0
	[ -z "$txcsum" ] && txcsum=0
	[ -z "$rxcsum" ] && rxcsum=0
	[ -z "$pcapEnable" ] && pcapEnable=0
	[ -z "$bypassOverFlows" ] && bypassOverFlows=0
	[ -z "$initialCwndWan" ] && initialCwndWan=18
	[ -z "$tcpFlags" ] && tcpFlags=0x0
	[ -z "$shortRttMS" ] && shortRttMS=15
	
	[ -z "$licenseGen" ] && licenseGen=0
	[ -z "$usermode" ] && usermode=0
	[ -z "$accpath" ] && accpath="/proc/net/appex"
	[ -z "$dropCache" ] && dropCache="0"
	[ -z "$shrinkOSWmem" ] && shrinkOSWmem="0"
	[[ -n "$pmtu" && "$pmtu" != "0" ]] && {
		echo "ERROR(CONFIG): pmtu can only be empty or zero"
		rst=1
	}
	[ -z "$apxexe" ] && {
		echo "ERROR(CONFIG): missing config: apxexe"
		rst=1
	}
	[ -f "$rttko" ] && rtt=1
	
	[ -z "$initialCwndLan" ] && initialCwndLan=1024
	
	if [ -z "$apxlic" ]; then
		if [ -f $ROOT_PATH/bin/activate.sh ]; then
			#not actived
			rst=2
		else
			echo "ERROR(CONFIG): missing config: apxlic"
			rst=1
		fi
	fi
	if [ -f $apxexe ]; then
		KILLNAME=$(echo $(basename $apxexe) | sed "s/-\[.*\]//")
		[ -z "$KILLNAME" ] && KILLNAME="acce-";
		KILLNAME=acce-[0-9.-]+\[.*\]
	else
		echo "ERROR(CONFIGFILE): missing file: $apxexe"
		rst=1
	fi

	# Locate ethtool
	ETHTOOL=$(which ethtool)
	[ "$nic_offload" != "1" ] && [ -z "$ETHTOOL" ] && {
		[ -f $ROOT_PATH/bin/ethtool ] && {
			ETHTOOL=$ROOT_PATH/bin/ethtool
		} || {
			echo 'ERROR(ETHTOOL): "ethtool" not found, please install "ethtool" using "yum install ethtool" or "apt-get install ethtool" according to your linux distribution'
			rst=1
		}
	}
	[ -z "$afterLoad" ] && afterLoad=/appex/bin/afterLoad
	[ "$detectInterrupt" = "1" ] && configCPUId
	
	# rtt init
	rttWork=/etc/rtt
	
	[ $rst -eq 1 ] && exit 1
	return $rst
}

# Log that something succeeded
success() {
    [ "$BOOTUP" = "color" ] && $MOVE_TO_COL
    echo -n "["
    [ "$BOOTUP" = "color" ] && $SETCOLOR_SUCCESS
    echo -n $"  OK  "
    [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
    echo -n "]"
    echo -ne "\r"
    return 0
}

# Log that something failed
failure() {
    [ "$BOOTUP" = "color" ] && $MOVE_TO_COL
    echo -n "["
    [ "$BOOTUP" = "color" ] && $SETCOLOR_FAILURE
    echo -n $"FAILED"
     [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
     echo -n "]"
     echo -ne "\r"
     return 1
}

ip2long() {
  local IFS='.'
  read ip1 ip2 ip3 ip4 <<<"$1"
  echo $((ip1*(1<<24)+ip2*(1<<16)+ip3*(1<<8)+ip4))
  #echo "$ip1 $ip2 $ip3 $ip4"
}

getVerStage() {
	local verName=$(echo $apxexe | awk -F- '{print $2}')
	local intVerName=$(ip2long $verName)
	local boundary=0
	local boundary2=0
	
	boundary=$(ip2long '3.11.49.10')
	[ $intVerName -ge $boundary ] && {
		# halfCwndLowLimit
		VER_STAGE=35
		return
	}
	
	boundary=$(ip2long '3.11.42.203')
	[ $intVerName -ge $boundary ] && {
		#IPv6, and related config
		VER_STAGE=33
		return
	}

	boundary=$(ip2long '3.11.29.0')
	[ $intVerName -ge $boundary ] && {
		#lanif
		VER_STAGE=31
		return
	}
	
	boundary=$(ip2long '3.11.27.63')
	[ $intVerName -ge $boundary ] && {
		#initialCwndLan
		VER_STAGE=30
		return
	}
	
	boundary=$(ip2long '3.11.27.0')
	[ $intVerName -eq $boundary ] && {
		#lanif
		VER_STAGE=29
		return
	}
	
	boundary=$(ip2long '3.11.20.10')
	[ $intVerName -ge $boundary ] && {
		# set initial taskSchedDelay value to 100 100
		VER_STAGE=28
		
		[ -n "$updatedAt" ] && {
			updatedAt=
			taskSchedDelay="100 100"
			sed -i "s/^taskSchedDelay=.*/taskSchedDelay=\"100 100\"/" $ROOT_PATH/etc/config 2>/dev/null
			sed -i '/^updatedAt=.*/d' $ROOT_PATH/etc/config 2>/dev/null
		}
		
		return
	}
	
	boundary=$(ip2long '3.11.19.11')
	[ $intVerName -ge $boundary ] && {
		#mpoolMaxCache
		VER_STAGE=27
		return
	}
	
	boundary=$(ip2long '3.11.10.0')
	[ $intVerName -ge $boundary ] && {
		#synRetranMS
		VER_STAGE=26
		return
	}
	
	boundary=$(ip2long '3.11.9.1')
	[ $intVerName -ge $boundary ] && {
		#ipHooks
		VER_STAGE=24
		return
	}
	
	boundary=$(ip2long '3.11.5.1')
	[ $intVerName -ge $boundary ] && {
		#Azure support
		VER_STAGE=22
		return
	}
	
	boundary=$(ip2long '3.10.66.30')
	[ $intVerName -ge $boundary ] && {
		#dropCache
		VER_STAGE=20
		return
	}
	
	boundary=$(ip2long '3.10.66.21')
	[ $intVerName -ge $boundary ] && {
		#move shortRtt to cmd
		VER_STAGE=19
		return
	}
	
	boundary=$(ip2long '3.10.66.18')
	[ $intVerName -ge $boundary ] && {
		#add acc/noacc parameter to shortRttBypass
		VER_STAGE=17
		return
	}
	
	boundary=$(ip2long '3.10.66.16')
	[ $intVerName -ge $boundary ] && {
		#support specify key generate method
		VER_STAGE=16
		return
	}
	
	boundary=$(ip2long '3.10.66.6')
	[ $intVerName -ge $boundary ] && {
		#support kernel module options
		VER_STAGE=15
		return
	}
	
	boundary=$(ip2long '3.10.65.3')
	[ $intVerName -ge $boundary ] && {
		#add udptun for vxlan
		VER_STAGE=14
		return
	}
	
	boundary=$(ip2long '3.10.62.0')
	[ $intVerName -ge $boundary ] && {
		#free wanIf when wanIf down
		VER_STAGE=13
		return
	}
	
	boundary=$(ip2long '3.10.61.0')
	[ $intVerName -ge $boundary ] && {
		#add acc/noacc parameter to lanSegment 
		VER_STAGE=12
		return
	}
	
	boundary=$(ip2long '3.10.54.2')
	[ $intVerName -ge $boundary ] && {
		#suport taskSchedDelay tobe set to '0 0'
		VER_STAGE=11
		return
	}
	
	boundary=$(ip2long '3.10.45.0')
	[ $intVerName -ge $boundary ] && {
		#suport highcsv
		VER_STAGE=10
		return
	}

	boundary=$(ip2long '3.10.39.8')
	[ $intVerName -ge $boundary ] && {
		#added short-rtt gso rsc
		VER_STAGE=9
		return
	}

	boundary=$(ip2long '3.10.37.0')
	[ $intVerName -ge $boundary ] && {
		#added minSsThresh dbcRttThreshMS smMinKbps in config
		VER_STAGE=8
		return
	}

	boundary=$(ip2long '3.10.23.1')
	[ $intVerName -ge $boundary ] && {
		#added ultraBoostWin
		VER_STAGE=7
		return
	}

	boundary=$(ip2long '3.9.10.43')
	[ $intVerName -ge $boundary ] && {
		#added smBurstMS
		VER_STAGE=6
		return
	}

	boundary=$(ip2long '3.9.10.34')
	[ $intVerName -ge $boundary ] && {
		#support output session restriction msg
		VER_STAGE=5
		return
	}

	boundary=$(ip2long '3.9.10.30')
	[ $intVerName -ge $boundary ] && {
		#support specify cpuid
		VER_STAGE=4
		return
	}

	boundary=$(ip2long '3.9.10.23')
	[ $intVerName -ge $boundary ] && {
		#support 256 interfaces
		VER_STAGE=3
		return
	}

	boundary=$(ip2long '3.9.10.10')
	[ $intVerName -ge $boundary ] && {
		#support multiple cpu
		VER_STAGE=2
		return
	}
}

bakOffload() {
	[ -s $OFFLOAD_BAK ] && {
		sed -i "1 i $ETHTOOL -K $1 $2 $3 2>/dev/null" $OFFLOAD_BAK
	} || {
		echo "$ETHTOOL -K $1 $2 $3 2>/dev/null" > $OFFLOAD_BAK
	}
}

initConfigEng() {
	[ $usermode -eq 0 ] && {
		local tcp_wmem=$(set $shrinkOSWmem; echo $1)
		local wmem_max=$(set $shrinkOSWmem; echo $2)
		[ $acc -eq 1 ] && {
			[ -f $RUNCONFIG_BAK ] && /bin/bash $RUNCONFIG_BAK 2>/dev/null
			cat /dev/null > $RUNCONFIG_BAK
			[ "$tcp_wmem" = "1" ] && {
				tcp_wmem=$(cat /proc/sys/net/ipv4/tcp_wmem)
				[ -n "$tcp_wmem" ] && echo "echo '$tcp_wmem' >/proc/sys/net/ipv4/tcp_wmem" >> $RUNCONFIG_BAK
				echo "${shrinkOSWmemValue:-4096 16384 32768}" > /proc/sys/net/ipv4/tcp_wmem
			}
			[ "$wmem_max" = "1" ] && {
				wmem_max=$(cat /proc/sys/net/core/wmem_max)
				[ -n "$wmem_max" ] && echo "echo '$wmem_max' >/proc/sys/net/core/wmem_max" >> $RUNCONFIG_BAK
				echo "${shrinkOSWmemMax:-32768}" > /proc/sys/net/core/wmem_max
			}
		}
		
		
	}	
}

checkTso() {
	[ -n "$nic_offload" -a "$nic_offload" = "1" ] && return 0
	[ -z "$($ETHTOOL -k $1 2>/dev/null | grep -E 'tcp.segmentation.offload:')" ] && return 0
	[ -n "$($ETHTOOL -k $1 2>/dev/null | grep -E 'tcp.segmentation.offload: off')" ] && return 0
	$ETHTOOL -K $1 tso off 2>/dev/null
	local ok=1
	for i in 1 2 ; do
		[ -n "$($ETHTOOL -k $1 2>/dev/null | grep -E 'tcp.segmentation.offload: off')" ] && {
			ok=0
			bakOffload $1 tso on
			break
		}
		sleep 1
		$ETHTOOL -K $1 tso off 2>/dev/null
	done
	return $ok
}

checkGso() {
	[ -n "$nic_offload" -a "$nic_offload" = "1" ] && return 0
	[ -z "$($ETHTOOL -k $1 2>/dev/null | grep -E 'generic.segmentation.offload:')" ] && return 0
	[ -n "$($ETHTOOL -k $1 2>/dev/null | grep -E 'generic.segmentation.offload: off')" ] && return 0
	$ETHTOOL -K $1 gso off 2>/dev/null
	local ok=1
	for i in 1 2 ; do
		[ -n "$($ETHTOOL -k $1 2>/dev/null | grep -E 'generic.segmentation.offload: off')" ] && {
			ok=0
			bakOffload $1 gso on
			break
		}
		sleep 1
		$ETHTOOL -K $1 gso off 2>/dev/null
	done
	return $ok
}

checkGro() {
	[ -n "$nic_offload" -a "$nic_offload" = "1" ] && return 0
	[ -z "$($ETHTOOL -k $1 2>/dev/null | grep -E 'generic.receive.offload:')" ] && return 0
	[ -n "$($ETHTOOL -k $1 2>/dev/null | grep -E 'generic.receive.offload: off')" ] && return 0
	$ETHTOOL -K $1 gro off 2>/dev/null
	local ok=1
	for i in 1 2 ; do
		[ -n "$($ETHTOOL -k $1 2>/dev/null | grep -E 'generic.receive.offload: off')" ] && {
			ok=0
			bakOffload $1 gro on
			break
		}
		sleep 1
		$ETHTOOL -K $1 gro off 2>/dev/null
	done
	return $ok
}

checkLro() {
	[ -n "$nic_offload" -a "$nic_offload" = "1" ] && return 0
	[ -z "$($ETHTOOL -k $1 2>/dev/null | grep -E 'large.receive.offload:')" ] && return 0
	[ -n "$($ETHTOOL -k $1 2>/dev/null | grep -E 'large.receive.offload: off')" ] && return 0
	$ETHTOOL -K $1 lro off 2>/dev/null
	local ok=1
	for i in 1 2 ; do
		[ -n "$($ETHTOOL -k $1 2>/dev/null | grep -E 'large.receive.offload: off')" ] && {
			ok=0
			bakOffload $1 lro on
			break
		}
		sleep 1
		$ETHTOOL -K $1 lro off 2>/dev/null
	done
	return $ok
}

checkSg() {
	[ -n "$nic_offload" -a "$nic_offload" = "1" ] && return 0
	[ -z "$($ETHTOOL -k $1 2>/dev/null | grep -E 'scatter.gather:')" ] && return 0
	[ -n "$($ETHTOOL -k $1 2>/dev/null | grep -E 'scatter.gather: off')" ] && return 0
	$ETHTOOL -K $1 sg off 2>/dev/null
	for i in 1 2 ; do
		[ -n "$($ETHTOOL -k $1 2>/dev/null | grep -E 'scatter.gather: off')" ] && {
			bakOffload $1 sg on
			break
		}
		sleep 1
		$ETHTOOL -K $1 sg off 2>/dev/null
	done
}

checkChecksumming() {
	[ "x$txcsum" = "x1" ] && $ETHTOOL -K $1 tx on 2>/dev/null
	[ "x$txcsum" = "x2" ] && $ETHTOOL -K $1 tx off 2>/dev/null
	[ "x$rxcsum" = "x1" ] && $ETHTOOL -K $1 rx on 2>/dev/null
	[ "x$rxcsum" = "x2" ] && $ETHTOOL -K $1 rx off 2>/dev/null
}

checkInfOffload() {
	local x
	for x in $1; do
		local isBondingInf=0
		local isBridgedInf=0
		local isVlanInf=0
		local _tmpName=''
		#echo checking $x
		_tmpName=${x//\./dot}
		_tmpName=${_tmpName//-/dash}
		#check whether been checked
		eval offload_checked=\$offload_checked_$_tmpName
		[ -n "$offload_checked" ] && continue
		eval offload_checked_$_tmpName=1
		
		#check whether the interface is bridged
		if [ -z "$2" -a -d /sys/class/net/$x/brport ]; then
			isBridgedInf=1
			local siblings=$(ls /sys/class/net/$x/brport/bridge/brif)
			for be in $siblings; do
				checkInfOffload $be 1
				[ $? -gt 0 ] && return $?
			done
		fi
		
		#check whether the interface is a bonding interface
		if [ -f /proc/net/bonding/$x ] ; then
			isBondingInf=1
			local bondEth=$(cat /proc/net/bonding/$x | grep "Slave Interface" | awk '{print $3}')
			for be in $bondEth ; do
				checkInfOffload $be
				[ $? -gt 0 ] && return $?
			done
		fi

		#check whether the interface is a vlan interface
		local vlanIf=$x
		ip link show $vlanIf | grep $vlanIf@ >/dev/null && {
			vlanIf=$(ip link show $vlanIf | awk -F: '/@/ {print $2}')
			vlanIf=${vlanIf#*@}
			[ "$vlanIf" != "$x" -a -n "$vlanIf" -a -d /sys/class/net/$vlanIf ] && {
				isVlanInf=1
				checkInfOffload $vlanIf
				[ $? -gt 0 ] && return $?
			}
		}
		
		#[ $isBondingInf -eq 0 -a $isVlanInf -eq 0 ] && {
			checkSg $x
			checkTso $x
			#[ $? -gt 0 ] && return 1
			[ $? -gt 0 ] && echo "[warn] Failed to turn off tso"
			checkGso $x
			#[ $? -gt 0 ] && return 2
			[ $? -gt 0 ] && echo "[warn] Failed to turn off gso"
			checkGro $x
			#[ $? -gt 0 ] && return 3
			[ $? -gt 0 ] && echo "[warn] Failed to turn off gro"
			checkLro $x
			#[ $? -gt 0 ] && return 4
			[ $? -gt 0 ] && echo "[warn] Failed to turn off lro"
			checkChecksumming $x
		#}
	done
	
	return 0
}

checkIPv4() { 
    local _ip    
    local _ret    
  
    for _ip in $@    
    do  
        _ret=$(echo "$_ip" | awk -F '.' '{ if(NF!=4 || $1<0 || $2<0|| $3<0 ||$4<0|| $1>255 || $2>255 || $3>255 || $4>255) print 1; else print 0  }')
        return $_ret
    done
}

getIPv6Hex() {
    local _ipv6=$1
    local _v6
    local _suffix
    local _pre
    local _mid
    local _last
    local _oldLFS
    local _p1
    local _p2
    local _i
    local _k=0

    _v6=${_ipv6%/*}
    _suffix=${_ipv6#*/}

    # may be IPv4 mapped address
    [ "${_v6:0:7}" == "::ffff:" -o "${_v6:0:7}" == "::FFFF:" ] && {
        _p1=${_v6:7}

        checkIPv4 $_p1
        [ $? -eq 0 ] && {
            _p1=$(echo "$_p1" | awk -F'.' '{printf "%02X%02X%02X%02X", $1, $2, $3, $4}')
            echo "00000000000000000000FFFF$_p1/$_prefix"
            return
        }
    }


    if [[ $_v6 =~ "::" ]]; then
        _p1=${_v6%::*}
        _p2=${_v6#*::}

        _oldIFS=$IFS
        IFS=":" 

        for _p in $_p1; do
            _pre=$_pre$(printf "%04x" 0x$_p | tr [a-z] [A-Z])
            _k=$(expr $_k + 1)
        done

        for _p in $_p2; do
            _last=$_last$(printf "%04x" 0x$_p | tr [a-z] [A-Z])
            _k=$(expr $_k + 1)
        done
        IFS=$_oldIFS

        _k=$(expr 8 - $_k)
        for ((_i=0;_i<_k;_i++)); do
            _mid=${_mid}0000
        done

        echo $_pre$_mid$_last/$_suffix
    else
        _p1=${_v6%::*}

        _oldIFS=$IFS
        IFS=":" 
        for _p in $_p1; do
            _pre=$_pre$(printf "%04x" 0x$_p | tr [a-z] [A-Z])
        done
        IFS=$_oldIFS

        echo $_pre/$_suffix
    fi
}

formatIPv4() {
	local word
	local line=''
	local prefix
	local suffix
	[[ -n "$@" ]] || return
	for word in $@; do
		[[ "$word" = "1" || "$word" = "0" ]] && continue
		prefix=${word%/*}
		suffix=${word#*/}
		word=$(printf "%08X" 0x$prefix)
		line="$line $word/$suffix"
	done
	line=$(echo $line | xargs -n 1 | sort)
	echo $line
}

formatIPv6() {
	local word
	local line=''
	local prefix
	local suffix
	[[ -n "$@" ]] || return
	for word in $@; do
		[[ "$word" = "1" || "$word" = "0" ]] && continue
		logger $word
		[ "$word" != "${word//:}" ] && word=$(getIPv6Hex $word)
		logger $word
		line="$line $word"
	done
	line=$(echo $line | xargs -n 1 | sort)
	echo $line
}

setParam() {
	local e=$1
	local engine=$1
	local item=$2
	shift 2
	local value=$@
	local saved
	
	if [ $usermode -eq 0 ]; then
		[ $engine -eq 0 ] && engine=''

		for i in $(seq ${configTimeout:-15}); do
			[ -d $accpath$engine ] && break
			echo -n .
			sleep 1
		done
		[ ! -d $accpath$engine ] && {
			echo "Loading $PRODUCT_NAME failed: failed to load engine $e" >&2
			stop >/dev/null 2>&1
			exit 1
		}
	
		local path="$accpath$engine/$item"
		for i in $(seq ${configTimeout:-15}); do
			[ -f $path ] && break
			echo -n .
			sleep 1
		done
	
		[ ! -f $path ] && {
			echo "Loading $PRODUCT_NAME failed: failed to locate $path" >&2
			stop >/dev/null 2>&1
			exit 1
		}
	
		echo "$value" > $path 2>/dev/null
		if [ "${value:0:1}" = '+' -o "${value:0:1}" = '-' ]; then
			return 0
		else
			for ii in 1 2 3; do
				saved=$(cat $path 2>/dev/null)
				[ "$value" = "$saved" ] && return 0
				echo -n .
				sleep 1
			done
		fi
	
		echo "Failed to write configuration: $path" >&2
	else
		$apxexe /$engine/$item="$value"
		if [ "${value:0:1}" = '+' -o "${value:0:1}" = '-' ]; then
			return 0
		else
			saved=$($apxexe /$engine/$item 2>/dev/null)
			[ "$value" = "$saved" ] && return 0
		fi
	
		echo "Failed to write configuration: /$engine/$item" >&2
	fi
	
	stop >/dev/null 2>&1
	exit 1
}

setCmd() {
	local e=$1
	local engine=$1
	local item=$2
	shift 2
	local value=$@
	local saved
	
	if [ $usermode -eq 0 ]; then
		[ $engine -eq 0 ] && engine=''
		value=$(echo $value)
	
		for i in $(seq ${configTimeout:-15}); do
			[ -d $accpath$engine ] && break
			echo -n .
			sleep 1
		done
		[ ! -d $accpath$engine ] && {
			echo "Loading $PRODUCT_NAME failed: failed to load engine $e" >&2
			stop >/dev/null 2>&1
			exit 1
		}
	
		local path="$accpath$engine/cmd"
		for i in $(seq ${configTimeout:-15}); do
			[ -f $path ] && break
			echo -n .
			sleep 1
		done
	
		[ ! -f $path ] && {
			echo "Loading $PRODUCT_NAME failed: failed to locate $path" >&2
			stop >/dev/null 2>&1
			exit 1
		}

        ## 10/09/2016
        head -n 4096 $path | grep $item >/dev/null 2>&1 || return
	
		echo "$item: $value" > $path 2>/dev/null
		
		# if item is lanSegment, do not check
		[ "$item" == "lanSegment" -o "$item" == "lanSegmentV6" ] && return 0

		# if item is shortRttBypass, do not check
		[ "$item" == "shortRttBypass" ] && return 0
		
		for ii in 1 2 3; do
			saved=$(head -n 4096 $path | awk -F': ' "/$item:/ {print \$2}")
			[ "$value" = "$saved" ] && return 0
			saved=$(head -n 4096 $path | grep "$item:" | cut -d ' ' -f 2)
			[ "$value" = "$saved" ] && return 0
			echo -n .
			sleep 1
		done
	
		echo "Failed to write configuration: $path:$item" >&2
	else
		value=$(echo $value)
		$apxexe /$engine/cmd="$item $value"
	
		saved=$($apxexe /$engine/cmd | awk -F': ' "/$item:/ {print \$2}")
		[ "$value" = "$saved" ] && return 0
		saved=$($apxexe /$engine/cmd | grep "$item:" | cut -d ' ' -f 2)
		[ "$value" = "$saved" ] && return 0
	
		echo "Failed to write configuration: /$engine/cmd/$item" >&2
	fi
	
	
	stop >/dev/null 2>&1
	exit 1
}

setCmdBitwiseOr() {
	local e=$1
	local engine=$1
	local item=$2
	local value=$3
	local saved
	
	if [ $usermode -eq 0 ]; then
		[ $engine -eq 0 ] && engine=''
		value=$(echo $value)
	
		for i in $(seq ${configTimeout:-15}); do
			[ -d $accpath$engine ] && break
			echo -n .
			sleep 1
		done
		[ ! -d $accpath$engine ] && {
			echo "Loading $PRODUCT_NAME failed: failed to load engine $e" >&2
			stop >/dev/null 2>&1
			exit 1
		}
	
		local path="$accpath$engine/cmd"
		for i in $(seq ${configTimeout:-15}); do
			[ -f $path ] && break
			echo -n .
			sleep 1
		done
	
		[ ! -f $path ] && {
			echo "Loading $PRODUCT_NAME failed: failed to locate $path" >&2
			stop >/dev/null 2>&1
			exit 1
		}
	
		local originVal=$(head -n 4096 $path | awk -F': ' "/$item:/ {print \$2}")
		((originVal = $originVal | $value))
		echo "$item: $originVal" > $path 2>/dev/null
		for ii in 1 2 3; do
			saved=$(head -n 4096 $path | awk -F': ' "/$item:/ {print \$2}")
			((saved = saved & $value))
			[ $saved -gt 0 ] && return 0
			echo -n .
			sleep 1
		done
	
		echo "Failed to write configuration: $path:$item" >&2
	else
		value=$(echo $value)
	
		local originVal=$($apxexe /$engine/cmd | awk -F': ' "/$item:/ {print \$2}")
		((originVal = $originVal | $value))
		$apxexe /$engine/cmd="$item $originVal"
		
		saved=$($apxexe /$engine/cmd | awk -F': ' "/$item:/ {print \$2}")
		((saved = saved & $value))
		[ $saved -gt 0 ] && return 0
	
		echo "Failed to write configuration: /$engine/cmd/$item" >&2
	fi
	
		
	stop >/dev/null 2>&1
	exit 1
}

setCmdBitwiseXOr() {
	local e=$1
	local engine=$1
	local item=$2
	local value=$3
	local saved
	
	if [ $usermode -eq 0 ]; then
		[ $engine -eq 0 ] && engine=''
		value=$(echo $value)
	
		for i in $(seq ${configTimeout:-15}); do
			[ -d $accpath$engine ] && break
			echo -n .
			sleep 1
		done
		[ ! -d $accpath$engine ] && {
			echo "Loading $PRODUCT_NAME failed: failed to load engine $e" >&2
			stop >/dev/null 2>&1
			exit 1
		}
	
		local path="$accpath$engine/cmd"
		for i in $(seq ${configTimeout:-15}); do
			[ -f $path ] && break
			echo -n .
			sleep 1
		done
	
		[ ! -f $path ] && {
			echo "Loading $PRODUCT_NAME failed: failed to locate $path" >&2
			stop >/dev/null 2>&1
			exit 1
		}
	
		local originVal=$(head -n 4096 $path | awk -F': ' "/$item:/ {print \$2}")
		((bitwiseAndVal = $originVal & $value))
		[ $bitwiseAndVal -eq 0 ] && return 0
		((originVal = $originVal ^ $value))
		echo "$item: $originVal" > $path 2>/dev/null
		for ii in 1 2 3; do
			saved=$(head -n 4096 $path | awk -F': ' "/$item:/ {print \$2}")
			((saved = saved & $value))
			[ $saved -eq 0 ] && return 0
			echo -n .
			sleep 1
		done
		
	else
		value=$(echo $value)
	
		local originVal=$($apxexe /$engine/cmd | awk -F': ' "/$item:/ {print \$2}")
		((bitwiseAndVal = $originVal & $value))
		[ $bitwiseAndVal -eq 0 ] && return 0
		((originVal = $originVal ^ $value))
		$apxexe /$engine/cmd="$item $originVal"
		saved=$($apxexe /$engine/cmd | awk -F': ' "/$item:/ {print \$2}")
		((saved = saved & $value))
		[ $saved -eq 0 ] && return 0
		
	fi
	
		

	echo "Failed to write configuration: $path:$item" >&2
	stop >/dev/null 2>&1
	exit 1
}

getParam() {
	local engine=$1
	local item=$2
	local value
	
	if [ $usermode -eq 0 ]; then
		[ $engine -eq 0 ] && engine=''
		value=$(cat $accpath$engine/$item 2>/dev/null)
	else
		value=$($apxexe /$engine/$item)
	fi
	echo $value
}

getCmd() {
	local engine=$1
	local item=$2
	local value
	
	if [ $usermode -eq 0 ]; then
		[ $engine -eq 0 ] && engine=''
		value=$(head -n 4096 $accpath$engine/cmd | awk -F': ' "/$item:/ {print \$2}")
	else
		value=$($apxexe /$engine/cmd | awk -F': ' "/$item:/ {print \$2}")
	fi
	echo $value
}

configEng() {
	local e=$1
	local lanSegmentV4Fmt
	local lanSegmentV6Fmt

	#disable host fairness, voip, p2p
	setParam $e 'hostFairEnable' 0
	setParam $e 'voipAccEnable' 0

	#setCmd $e p2pPriorities 1

	#enable shaper and set bw to 1Gbps
	setParam $e 'shaperEnable' 1
	setParam $e 'wanKbps' $wankbps
	setParam $e 'wanInKbps' $waninkbps
	setParam $e 'conservMode' $csvmode

	#set acc
	setParam $e 'tcpAccEnable' $acc

	#set subnet acc
	setParam $e 'subnetAccEnable' $subnetAcc

	#set advance acc
	setParam $e 'trackRandomLoss' $advacc

	#set advinacc
	setParam $e 'advAccEnable' $advinacc

	#set shaper
	setParam $e 'shaperEnable' $shaperEnable

	#set max win to 0 for wan and 60 for lan
	setCmd $e maxAdvWinWan 0
	setCmd $e maxAdvWinLan 60

	#set maxTxEnable
	setParam $e 'maxTxEnable' $maxmode
	[ "x$maxmode" = "x1" ] && {
		setParam $e 'trackRandomLoss' 1
		setCmd $e maxTxEffectiveMS $maxTxEffectiveMS
	}

	[ -n "$maxTxMinSsThresh" ] && setCmd $e maxTxMinSsThresh $maxTxMinSsThresh
	[ -n "$maxAccFlowTxKbps" ] && setCmd $e maxAccFlowTxKbps $maxAccFlowTxKbps
	#set pcapEnable
	setParam $e 'pcapEnable' $pcapEnable

	#set bypassOverFlows
	setCmd $e bypassOverFlows $bypassOverFlows
	#set initialCwndWan
	setCmd $e initialCwndWan $initialCwndWan
	# 10/10/2017
	[ -n "$maxCwndWan" ] && setCmd $e maxCwndWan $maxCwndWan
	
	#queue size limit for lan to wan 
	[ -n "$l2wQLimit" ] && setCmd $e l2wQLimit $l2wQLimit
	#queue size limit for wan to lan 
	[ -n "$w2lQLimit" ] && setCmd $e w2lQLimit $w2lQLimit
	#set halfCwndMinSRtt
	[ -n "$halfCwndMinSRtt" ] && setCmd $e halfCwndMinSRtt $halfCwndMinSRtt
	#set halfCwndLossRateShift
	[ -n "$halfCwndLossRateShift" ] && setCmd $e halfCwndLossRateShift $halfCwndLossRateShift
	#set retranWaitListMS
	[ -n "$retranWaitListMS" ] && setCmd $e retranWaitListMS $retranWaitListMS
	#set tcpOnly
	[ -n "$tcpOnly" ] && setCmd $e tcpOnly $tcpOnly

	#set smBurstMS [suported from 3.9.10.43]
	[ $VER_STAGE -ge 6 ] && {
		[ -n "$smBurstMS" ] && setCmd $e smBurstMS $smBurstMS
		[ -n "$smBurstTolerance" ] && setCmd $e smBurstTolerance $smBurstTolerance
		[ -n "$smBurstMin" ] && setCmd $e smBurstMin $smBurstMin
	}

	if [ $usermode -eq 0 ]; then
		#set shrinkPacket
		[ -n "$shrinkPacket" ] && setCmd $e shrinkPacket $shrinkPacket
		
		setParam $e 'byteCacheEnable' $byteCacheEnable
		#setCmd $e engine $(getCmd $e engine | awk '{print $1,$2}') $(($byteCacheMemory/6))
		
		setParam $e 'dataCompEnable' $dataCompEnable
		
		if [[ "$byteCacheEnable" == "1" || "$dataCompEnable" == "1" ]]; then
			setParam $e 'httpCompEnable' $httpCompEnable
		else
			setParam $e 'httpCompEnable' 0
		fi
		
		#from 3.10.39.8
		[ $VER_STAGE -ge 9 ] && { 
			[ -n "$rsc" ] && setCmd $e rsc $rsc
			[ -n "$gso" ] && setCmd $e gso $gso
		
			#only set shortRttMS for the first engine
			[ $VER_STAGE -lt 19 -a -z "$e" -a -n "$shortRttMS" -a "$shortRttMS" != "0" ] && setCmd $e shortRttMS $shortRttMS
		}
		
		if [ -n "$lanSegment" ]; then
			setCmd $e lanSegment $lanSegment
			saved=$(getCmd $e lanSegment)
			saved=$(formatIPv4 $saved)
			lanSegmentV4Fmt=$(formatIPv4 $lanSegment)
			[[ "$saved" != "$lanSegmentV4Fmt" ]] && {
				echo "Failed to write configuration: lanSegment" >&2
				stop >/dev/null 2>&1
				exit 1
			}
		else
			setCmd $e lanSegment ""
		fi
		
		if [ $VER_STAGE -ge 33 ]; then
			# from 3.11.42.203  IPv6
			
			[ -n "$ipv4Only" ] && setCmd $e ipv4Only $ipv4Only
			[ -n "$ipv6Only" ] && setCmd $e ipv6Only $ipv6Only
	
			if [ -n "$lanSegmentV6" ]; then
				setCmd $e lanSegmentV6 $lanSegmentV6
				saved=$(getCmd $e lanSegmentV6)
				saved=$(formatIPv6 $saved)
				lanSegmentV6Fmt=$(formatIPv6 $lanSegmentV6)
				[[ "$saved" != "$lanSegmentV6Fmt" ]] && {
					echo "Failed to write configuration: lanSegmentV6" >&2
					stop >/dev/null 2>&1
					exit 1
				}
			else
				setCmd $e lanSegmentV6 ""
			fi

		fi
		
		#from 3.10.45.0
		[ $VER_STAGE -ge 10 ] && {
			[ -n "$txCongestObey" ] && setCmd $e txCongestObey $txCongestObey
			[[ -n "$highcsv" && $highcsv -gt 0 ]] && {
				setCmdBitwiseOr $e tcpFlags 0x4000
			} || {
				setCmdBitwiseXOr $e tcpFlags 0x4000
			}
		}
	fi

	#from 3.10.23.1
	[ $VER_STAGE -ge 7 -a -n "$ultraBoostWin" ] && setCmd $e ultraBoostWin $ultraBoostWin

	[ $VER_STAGE -ge 8 ] && {
		[ -n "$minSsThresh" ] && setCmd $e minSsThresh $minSsThresh
		[ -n "$dbcRttThreshMS" ] && setCmd $e dbcRttThreshMS $dbcRttThreshMS
		[ -n "$smMinKbps" ] && setCmd $e smMinKbps $smMinKbps
	}
	
	#from 3.10.54.2
	[ $VER_STAGE -ge 11 ] && {
		[ -n "$taskSchedDelay" ] && setCmd $e taskSchedDelay $taskSchedDelay
	}

	setCmd $e tcpFlags $tcpFlags

	#from 3.10.66.0
	[ $VER_STAGE -ge 14 ] && {
		[ -n "$udptun" ] && {
			setCmd $e udptun $udptun
		} || {
			setCmd $e udptun ''
		}
	}
	
	#from 3.10.66.18
	[ $VER_STAGE -ge 17 ] && {
		if [ -n "$shortRttBypass" ]; then
			setCmd $e shortRttBypass $shortRttBypass
			saved=$(getCmd $e shortRttBypass)
			[[ ${saved#$shortRttBypass} == $saved && ${shortRttBypass#$saved} == $shortRttBypass ]] && {
		        echo "Failed to write configuration: shortRttBypass" >&2
		        stop >/dev/null 2>&1
		        exit 1
			}
		else
			setCmd $e shortRttBypass ""
		fi
	}
	
	[ $usermode -eq 1 ] && setParam $e logDir $ROOT_PATH/log
	[ -n "$flowShortTimeout" ] && setCmd $e flowShortTimeout $flowShortTimeout
	[ $VER_STAGE -ge 19 ] && {
		setCmd $e shortRttMS $shortRttMS
		if [ -n "$shortRttMS" -a "$shortRttMS" != "0" ]; then
			setCmdBitwiseOr $e tcpFlags 0x800
		else
			setCmdBitwiseXOr $e tcpFlags 0x800
		fi
	}
	
	#from 3.11.10.0
	[ $VER_STAGE -ge 26 ] && {
		[ -n "$synRetranMS" ] && setCmd $e synRetranMS $synRetranMS
	}
	#from 3.11.19.11
	[ $VER_STAGE -ge 27 ] && {
		[ -n "$mpoolMaxCache" ] && setCmd $e mpoolMaxCache $mpoolMaxCache
	}

	local ee=$e
	[ $ee -eq 0 ] && ee=''
	[ -f /proc/net/appex${ee}/engSysEnable ] && setParam $e 'engSysEnable' 1
	
	#set acc interface
	if [ $VER_STAGE -lt 3 ]; then
		setParam $e 'wanIf' $accif
	else
		local tobeAdded tobeRemoved
		
		local curWanIf=$(getParam $e wanIf)
		for aif in $accif; do
			[ "${curWanIf/$aif}" = "$curWanIf" ] && tobeAdded="$tobeAdded $aif"
		done
		for aif in $curWanIf; do
			[ "${accif/$aif}" = "$accif" ] && tobeRemoved="$tobeRemoved $aif"
		done
		
		tobeAdded=$(echo $tobeAdded)
		tobeRemoved=$(echo $tobeRemoved)
		
		[ -n "$tobeAdded" ] && {
			for x in $tobeAdded; do
				setParam $e 'wanIf' "+$x"
			done
		}
		[ -n "$tobeRemoved" ] && {
			for x in $tobeRemoved; do
				setParam $e 'wanIf' "-$x"
			done
		}
		
		local savedWanIf=$(getParam $e wanIf)
		for aif in $accif; do
			[ "${savedWanIf/$aif}" = "$savedWanIf" ] && {
				echo "Failed to write configuration: wanIf($aif)" >&2
		   		stop >/dev/null 2>&1
				exit 1
			}
		done
	fi
	
	[ $VER_STAGE -eq 29 -o $VER_STAGE -ge 31 ] && {
		[ -n "$lanif" ] && {
			local curLanIf=$(getParam $e lanIf)
			local tobeAddedLans=($(comm -23 <(echo $lanif | xargs -n1 | sort) <(echo $curLanIf | xargs -n1 | sort)))
			local tobeRemovedLans=($(comm -13 <(echo $lanif | xargs -n1 | sort) <(echo $curLanIf | xargs -n1 | sort)))
		
			[ -n "$tobeAddedLans" ] && {
				for x in ${tobeAddedLans[@]}; do
					setParam $e 'lanIf' "+$x"
				done
			}
			[ -n "$tobeRemovedLans" ] && {
				for x in ${tobeRemovedLans[@]}; do
					setParam $e 'lanIf' "-$x"
				done
			}
			
			local savedlanIf=$(getParam $e lanIf)
			for aif in $lanif; do
				[ "${savedlanIf/$aif}" = "$savedlanIf" ] && {
					echo "Failed to write configuration: lanIf($aif)" >&2
			   		stop >/dev/null 2>&1
					exit 1
				}
			done
		}
	}
	
	#from 3.11.27.63  initialCwndLan
	[ $VER_STAGE -ge 30 ] && {
		[ -n "$initialCwndLan" ] && setCmd $e initialCwndLan $initialCwndLan
	}
	
	[ -n "$lttMaxDelayMS" ] && setCmd $e lttMaxDelayMS "$lttMaxDelayMS"
	
	# from 3.11.49.10
	[ $VER_STAGE -ge 35 ] && {
		[ -n "$halfCwndLowLimit" ] && setCmd $e halfCwndLowLimit $halfCwndLowLimit
	}
}

function freeIf() {
	[ $usermode -eq 1 ] && return
	local e=$1
	[ $e -eq 0 ] && e=''
	local epath="$accpath$e"
	[ -d $epath ] || return
	echo "" > $epath/wanIf 2>/dev/null
}

function disp_usage() {
	if [ $VER_STAGE -eq 1 ]; then
		echo "Usage: $0 {start | stop | reload | restart | status | uninstall}"
	else
		echo "Usage: $0 {start | stop | reload | restart | status | stats | uninstall}"
	fi
	echo
	echo -e "  start\t\t  start $PRODUCT_NAME"
	echo -e "  stop\t\t  stop $PRODUCT_NAME"
	echo -e "  reload\t  reload configuration"
	echo -e "  restart\t  restart $PRODUCT_NAME"
	echo -e "  status\t  show $PRODUCT_NAME running status"
	[ $VER_STAGE -gt 1 ] && echo -e "  stats\t\t  show realtime connection statistics"
	echo
	echo -e "  uninstall\t  uninstall $PRODUCT_NAME"
	exit 1
}

function init() {
	[ "$accppp" = "1" ] && {
		local updir=${pppup:- /etc/ppp/ip-up.d}
		local downdir=${pppdown:- /etc/ppp/ip-down.d}
		
		[ -d $updir ] && ln -sf $ROOT_PATH/bin/$SHELL_NAME $updir/pppup
		[ ! -f /etc/ppp/ip-up.local ] && ln -sf $ROOT_PATH/bin/$SHELL_NAME /etc/ppp/ip-up.local
		
		[ -d $downdir ] && ln -sf $ROOT_PATH/bin/$SHELL_NAME $downdir/pppdown
		[ ! -f /etc/ppp/ip-down.local ] && ln -sf $ROOT_PATH/bin/$SHELL_NAME /etc/ppp/ip-down.local
	}
}

function endLoad() {
	[ "$accppp" = "1" -a -f /proc/net/dev ] && {
		local updir=${pppup:- /etc/ppp/ip-up.d}
		[ -f $updir/pppup ] && {
			for i in $(cat /proc/net/dev | awk -F: '/ppp/ {print $1}'); do
				$updir/pppup $i
			done
		}
		[ -f /etc/ppp/ip-up.local ] && {
			for i in $(cat /proc/net/dev | awk -F: '/ppp/ {print $1}'); do
				/etc/ppp/ip-up.local $i
			done
		}
	}
}

function freeupLic() {
	local force=0
	[ "$1" = "-f" -o "$1" = "-force" ] && force=1
	echo 'connect to license server...'
	local url="http://$HOST/auth/free2.jsp?e=$email&s=$serial"
	wget --timeout=5 --tries=3 -O /dev/null $url >/dev/null 2>/dev/null
	[ $? -ne 0 -a $force -eq 0 ] && {
		echo 'failed to connect license server, please try again later.'
		echo -n "if you still want to uninstall $PRODUCT_NAME, please run "
		echo -en "$HL_START"
		echo -n "$0 uninstall -f"
		echo -e "$HL_END"
		exit 1
	}
}

function uninstall() {
	freeupLic $1
	[ -d "$accpath" ] && stop >/dev/null || {
		pkill -0 $KILLNAME 2>/dev/null
		[ $? -eq 0 ] && stop >/dev/null
	}
	sleep 2
	cd ~
	rm -rf $ROOT_PATH
	
	rm -f /etc/rc.d/init.d/$PRODUCT_ID 2>/dev/null
	rm -f /etc/rc.d/rc*.d/S20$PRODUCT_ID 2>/dev/null
	rm -f /etc/rc.d/$PRODUCT_ID 2>/dev/null
	rm -f /etc/rc.d/rc*.d/*$PRODUCT_ID 2>/dev/null
	rm -f /etc/init.d/$PRODUCT_ID 2>/dev/null
	rm -f /etc/rc*.d/S03$PRODUCT_ID 2>/dev/null
	
	rm -f /usr/lib/systemd/system/$PRODUCT_ID.service 2>/dev/null
	systemctl daemon-reload 2>/dev/null
		
	
	echo "Uninstallation done!"
	exit
}

function stop() {
	local rmRttMod=0
	[ "$1" = "all" -o "$1" = "ALL" ] && rmRttMod=1
	[ -d "$accpath" ] || {
		pkill -0 $KILLNAME 2>/dev/null
		[ $? -ne 0 ] && {
			[ $rmRttMod -eq 1 ] && rmmod ltt_if 2>/dev/null
			echo "$PRODUCT_NAME is not running!" >&2
			exit 1
		}
	}
	
	if [ $usermode -eq 0 ]; then
		getCpuNum
		for enum in $(seq $CPUNUM); do
			freeIf $((enum - 1))
		done
		
		pkill $KILLNAME
		for i in $(seq 30); do
			pkill -0 $KILLNAME
			[ $? -gt 0 ] && break
			sleep 1
			[ $i -eq 6 ] && echo 'It takes a long time than usual, please wait for a moment...'
			[ $i -eq 30 ] && pkill -9 $KILLNAME
		done
		
		local enum=0
		for enum in $(seq $CPUNUM); do
			unloadModule $((enum - 1))
		done
		[ -f $OFFLOAD_BAK ] && /bin/bash $OFFLOAD_BAK 2>/dev/null
		[ -f $RUNCONFIG_BAK ] && {
			/bin/bash $RUNCONFIG_BAK 2>/dev/null
			rm -f RUNCONFIG_BAK 2>/dev/null
		}
		[ $rmRttMod -eq 1 ] && rmmod ltt_if 2>/dev/null
	else
		$apxexe quit
	fi
		
	echo "$PRODUCT_NAME is stopped!"
}

function start() {
	[ -d "$accpath" ] && {
		echo "$PRODUCT_NAME is running!" >&2
		exit 1
	}
	pkill -0 $KILLNAME 2>/dev/null
	[ $? -eq 0 ] && {
		echo "$PRODUCT_NAME is running!"
		exit 1
	}
	
	if [ $usermode -eq 0 ]; then
		#disable tso&gso&sg
		cat /dev/null > $OFFLOAD_BAK
		checkInfOffload "$accif"
		case $? in
			1)
				echo "Can not disable tso(tcp segmentation offload) of $x, exit!"
				exit 1
				;;
			2)
				echo "Can not disable gso(generic segmentation offload) of $x, exit!"
				exit 1
				;;
			3)
				echo "Can not disable gro(generic receive offload) of $x, exit!"
				exit 1
				;;
			4)
				echo "Can not disable lro(large receive offload) of $x, exit!"
				exit 1
				;;
		esac
	fi
	
	init
	getCpuNum 1
	local engineNumOption="-n $CPUNUM"
	local shortRttOption=''
	local pmtuOption=''
	local kernelOption=''
	local keyOption=''
	local bcOption=''
	local dropCacheOption=''
	
	[ -n "$pmtu" ] && pmtuOption="-t $pmtu"
	[ "$byteCacheEnable" == "1" ] && {
		[ $byteCacheMemory -ge 0 ] && bcOption="-m $(($byteCacheMemory/2))"
		[ -n "$diskDev" -a $byteCacheDisk -ge 0 ] && bcOption=" $bcOption -d $(($byteCacheDisk/2)) -c $diskDev"
		bcOption=$(echo $bcOption)
		[ -n "$bcOption" ] && bcOption="-b $bcOption"
	}
	
	[ $VER_STAGE -ge 4 -a -n "$cpuID" ] && engineNumOption="-c $cpuID"
	[ $VER_STAGE -ge 9 -a -n "$shortRttMS" -a "$shortRttMS" != "0" ] && shortRttOption="-w $shortRttMS"
	[ $VER_STAGE -ge 19 ] && shortRttOption=''
	# 3.11.9.1
	[ $VER_STAGE -ge 24 -a -n "$ipHooks" ] && kernelOption="$kernelOption ipHooks=$ipHooks"
	[ $VER_STAGE -ge 15 ] && {
		[ -n "$ipRxHookPri" ] && kernelOption="$kernelOption ipRxHookPri=$ipRxHookPri"
		[ -n "$ipTxHookPri" ] && kernelOption="$kernelOption ipTxHookPri=$ipTxHookPri"
		
		if [ $VER_STAGE -ge 33 ]; then
			[ -n "$ipv6Hooks" ] && kernelOption="$kernelOption ipv6Hooks=$ipv6Hooks"
			[ -n "$ipv6RxHookPri" ] && kernelOption="$kernelOption ipv6RxHookPri=$ipv6RxHookPri"
			[ -n "$ipv6TxHookPri" ] && kernelOption="$kernelOption ipv6TxHookPri=$ipv6TxHookPri"
		fi
		[ -n "$kernelOption" ] && kernelOption=$(echo $kernelOption)
	}
	[ $VER_STAGE -ge 16 ] && keyOption="-K $licenseGen"
	[ $licenseGen -eq 5 -a $VER_STAGE -lt 22 ] && {
		echo 'please update acce vertion greater than 3.11.5.1'
		exit 1
	}
	[ $VER_STAGE -ge 20 -a -n "$dropCache" -a "$dropCache" != "0" ] && dropCacheOption="-r $dropCache"
	
	if [ $usermode -eq 0 ]; then
		[ -f "$rttko" ] && {
			# default port 49152
			lsmod | grep ltt_if >/dev/null 2>&1 || /sbin/insmod $rttko ${rttListenPort:+ltt_udp_port=$rttListenPort}
		}
		$apxexe $keyOption $engineNumOption -s $apxlic -m -p $packetWrapper $pmtuOption $shortRttOption $dropCacheOption ${kernelOption:+-k "$kernelOption"} $bcOption
	else
		$apxexe -e -i $keyOption -s $apxlic -p $packetWrapper $pmtuOption $shortRttOption
	fi 
	result=$?
	[ $result -ne 0 ] && {
		echo "Load $PRODUCT_NAME failed!"
		exit $result
	}
	#sleep 1
	initConfigEng
	local enum=0
	while [ $enum -lt $CPUNUM ]; do
		configEng $enum
		enum=$(($enum + 1))
	done
	#[ -f $ROOT_PATH/bin/apxClsfCfg  -a -f $ROOT_PATH/etc/clsf ] && $ROOT_PATH/bin/apxClsfCfg 2>/dev/null
	endLoad
	[ $VER_STAGE -ge 9 -a -n "$shortRttMS" -a "$shortRttMS" != "0" ] && echo "Short-RTT bypass has been enabled"
}

function restart() {
	[ -d "$accpath" ] && stop $1 >/dev/null || {
		pkill -0 $KILLNAME 2>/dev/null
		[ $? -eq 0 ] && stop $1 >/dev/null
	}
	sleep 2
	start
}

function showStatus() {
	echo -en "$HL_START"
	echo -n "[Running Status]"
	echo -e "$HL_END"
	pkill -0 $KILLNAME 2>/dev/null
	if [ $? -eq 0 ];then
		running=1
		echo "$PRODUCT_NAME is running!"
	else
		running=0
		echo "$PRODUCT_NAME is NOT running!"
	fi
	
	if [ $running -eq 1 -a $usermode -eq 1 ]; then
		printf "%-20s %s\n" version $(getParam 0 version)
	else
		verName=$(echo $apxexe | awk -F- '{print $2}')
		printf "%-20s %s\n" version $verName
	fi
	echo
	
	echo -en "$HL_START"
	echo -n "[License Information]"
	echo -e "$HL_END"
	if [ $VER_STAGE -ge 5 ]; then
		keyOption=''
		[ $VER_STAGE -ge 16 ] && keyOption="-K $licenseGen"
		if [ $usermode -eq 0 -a "$byteCacheEnable" == "1" ]; then
   			$apxexe $keyOption -s $apxlic -d | while read _line; do
				echo $_line | awk -F': ' '/^[^\(]/{if($1 != "MaxCompSession"){printf "%-20s %s\n", $1, ($2 == "0" ? "unlimited" : $2)}}'
			done 2>/dev/null
		else
			$apxexe $keyOption -s $apxlic -d | while read _line; do
				echo $_line | awk -F': ' '/^[^\(]/{if($1 != "MaxCompSession" && $1 != "MaxByteCacheSession"){printf "%-20s %s\n", $1, ($2 == "0" ? "unlimited" : $2)}}'
			done 2>/dev/null
		fi
	else
		printf "%-20s %s\n" $(echo $apxlic | awk -F- '{printf "expiration %0d", $2}' )
	fi
	
	[ "$rtt" = "1" ] && {
		echo
   		echo -en "$HL_START"
   		echo -n "[RTT Information]"
   		echo -e "$HL_END"
   		printf "%-20s %s %s\n" module $(lsmod | grep ltt_if >/dev/null 2>&1 && echo 'loaded' || echo 'not load')
	}
	
	if [ $running -eq 1 ];then
		echo
		echo -en "$HL_START"
   		echo -n "[Connection Information]"
   		echo -e "$HL_END"
   		if [ $usermode -eq 0 ]; then
   			cat /proc/net/appex*/stats 2>/dev/null | awk -F= '/NumOf.*Flows/ {gsub(/[ \t]*/,"",$1);gsub(/[ \t]*/,"",$2);a[$1]+=$2;} END {\
   				printf "%-20s %s\n", "TotalFlow",a["NumOfFlows"];\
   				printf "%-20s %s\n", "NumOfTcpFlows",a["NumOfTcpFlows"];\
   				printf "%-20s %s\n", "TotalAccTcpFlow",a["NumOfAccFlows"];\
   				printf "%-20s %s\n", "TotalActiveTcpFlow",a["NumOfActFlows"];\
   				
   				if(a["V4NumOfFlows"] != "") {
	   				printf "%-20s %s\n", "V4TotalFlow",a["V4NumOfFlows"];\
	   				printf "%-20s %s\n", "V4NumOfTcpFlows",a["V4NumOfTcpFlows"];\
	   				printf "%-20s %s\n", "V4TotalAccTcpFlow",a["V4NumOfAccFlows"];\
	   				printf "%-20s %s\n", "V4TotalActiveTcpFlow",a["V4NumOfActFlows"];\
	   				printf "%-20s %s\n", "V6TotalFlow",a["V6NumOfFlows"];\
	   				printf "%-20s %s\n", "V6NumOfTcpFlows",a["V6NumOfTcpFlows"];\
	   				printf "%-20s %s\n", "V6TotalAccTcpFlow",a["V6NumOfAccFlows"];\
	   				printf "%-20s %s\n", "V6TotalActiveTcpFlow",a["V6NumOfActFlows"];\
   				}
   			}'
   		else
   			$apxexe /0/stats | awk -F= '/NumOf.*Flows/ {gsub(/[ \t]*/,"",$1);gsub(/[ \t]*/,"",$2);a[$1]+=$2;} END {\
   				printf "%-20s %s\n", "TotalFlow",a["NumOfFlows"];\
   				printf "%-20s %s\n", "NumOfTcpFlows",a["NumOfTcpFlows"];\
   				printf "%-20s %s\n", "TotalAccTcpFlow",a["NumOfAccFlows"];\
   				printf "%-20s %s\n", "TotalActiveTcpFlow",a["NumOfActFlows"];\
   			}'
   		fi
   		
   		
   		echo
   		echo -en "$HL_START"
   		echo -n "[Running Configuration]"
   		echo -e "$HL_END"
		printf "%-20s %s %s %s %s %s %s %s %s\n" accif $(getParam 0 wanIf)
		printf "%-20s %s %s %s %s %s %s %s %s\n" lanif $(getParam 0 lanIf)
		printf "%-20s %s\n" acc $(getParam 0 tcpAccEnable)

		printf "%-20s %s\n" advacc $(getParam 0 trackRandomLoss)
		printf "%-20s %s\n" advinacc $(getParam 0 advAccEnable)
		printf "%-20s %s\n" wankbps $(getParam 0 wanKbps)
		printf "%-20s %s\n" waninkbps $(getParam 0 wanInKbps)
		printf "%-20s %s\n" csvmode $(getParam 0 conservMode)
		printf "%-20s %s\n" subnetAcc $(getParam 0 subnetAccEnable)
		printf "%-20s %s\n" maxmode $(getParam 0 maxTxEnable)
		printf "%-20s %s\n" pcapEnable $(getParam 0 pcapEnable)
		
		[ $usermode -eq 0 ] && {
			[ $VER_STAGE -ge 9 -a -n "$shortRttMS" -a "$shortRttMS" != "0" ] && printf "%-20s %s\n" shortRttMS $(getCmd 0 shortRttMS | awk '{print $1}')
			[ "$byteCacheEnable" == "1" ] && printf "%-20s %s\n" byteCacheEnable $(getParam 0 byteCacheEnable)
		}
	fi
}

function pppUp() {
	getCpuNum
	local eNum=0
	local e
	if [ $usermode -eq 0 ]; then
		while [ $eNum -lt $CPUNUM ]; do
			e=$eNum
			[ $e -eq 0 ] && e=''
			[ -d /proc/net/appex$e ] && {
				echo "+$1" > /proc/net/appex$e/wanIf
			}
			((eNum = $eNum + 1))
		done
	else
		pkill -0 $KILLNAME 2>/dev/null
		[ $? -eq 0 ] || exit 0
		while [ $eNum -lt $CPUNUM ]; do
			$apxexe /$eNum/wanIf=+$1
			((eNum = $eNum + 1))
		done
	fi
	exit 0	
}

function pppDown() {
	getCpuNum
	local eNum=0
	local e
	if [ $usermode -eq 0 ]; then
		while [ $eNum -lt $CPUNUM ]; do
			e=$eNum
			[ $e -eq 0 ] && e=''
			[ -d /proc/net/appex$e ] && {
				curWanIf=$(getParam $eNum wanIf)
				setParam $eNum wanIf ''
				for cIf in $curWanIf; do
					[ $cIf != "$1" ] && setParam $eNum wanIf "+$cIf"
				done
			}
			((eNum = $eNum + 1))
		done
	else
		pkill -0 $KILLNAME 2>/dev/null
		[ $? -eq 0 ] || exit 0
		while [ $eNum -lt $CPUNUM ]; do
			$apxexe /$eNum/wanIf=-$1
			((eNum = $eNum + 1))
		done
	fi
	exit 0	
}

function getRttVerState() {
	local verName=$(cat /sys/kernel/ltt/cmd | grep 'version:')
	local intVerName=$(ip2long ${verName/version: /})
	local boundary=0
	
	boundary=$(ip2long '0.7.20')
	[ $intVerName -ge $boundary ] && {
		# add tos
		RTT_VER_STAGE=10
		return
	}
}

function parseRttConf()	{
	local conf=$1
	local idx=$2

	eval $(cat $1.conf | awk -F\= -v idx=$idx '/^[^#].*/ {gsub(/"/,"",$2);gsub(/[ \t]+$/, "", $1);gsub(/^[ \t]+/, "", $1);gsub(/^[ \t]+/, "", $2);gsub(/[ \t]+$/, "", $2); print $1"["idx"]""="$2}')

	for((j=0;j<$idx;j++)); do
		if [ "${ifname[$idx]}"0 = "${ifname[j]}"0 ]; then
			echo "Duplicate RTT interface ${ifname[$idx]} in $conf.conf"
			exit
		fi
	done

	### default value
	dstport[$idx]=${dstport[$idx]:-49152}
}

function parseAllRttConf()	{
	local i=0

	confname=''
	srcip=''
	dstip=''	
	ifname=''
	localip=''
	remoteip=''
	dstport=''
	tcptun=''
	udptun=''
	passive=''
	vni=''
	ipop=''
	keepalive=''
	txkbps=''
	tos=''
	ipsec=''
	inspi=''
	outspi=''
	md5val=''
	des3val=''
	aesval=''
	reqid=''
	encmethod=''	
	
	cd $rttWork
	for	c in `/bin/ls *.conf 2>/dev/null`; do
		bn=${c%%.conf}
		[ -n "$1" -a "${1%%.conf}" != "$bn"	] && continue
		bn=${bn//-/_}
		[ "$bn"	= "default"	] && continue
		
		[ -f "$bn.sh" ]	&& . $bn.sh
		confname[$i]=$bn
		parseRttConf $bn $i
		i=`expr $i + 1`
	done
}

### Should call parseAllRttConf() first.
function findConfnameByIfname() {
	local arr_length=${#ifname[*]}
	for ((idx = 0; idx < $arr_length; idx++)); do
  	 	[ -n "$1" -a "$1"0 == "${ifname[$idx]}"0 ] && break		
	done
	echo ${confname[$idx]}
}

function startRtt() {
	local bn
	local cmdline
	
	[ -d /sys/kernel/ltt ] || {
		echo 'Please start LotServer first'
		return	
	}
	getRttVerState
	### Read All RTT Config
	parseAllRttConf

	### set RTT tunnel into /sys/kernel/ltt/tunnels
	local arr_length=${#ifname[*]}
	for((i=0;i<$arr_length;i++)); do
	 	[ -n "$1" -a "$1"0 != "${confname[$i]}"0 ] && continue
		cmdline="+ dstip=${dstip[$i]}${srcip[$i]:+ srcip=${srcip[$i]}} ifname=${ifname[$i]} tcptun=${tcptun[$i]} udptun=${udptun[$i]} passive=${passive[$i]:-0} vni=${vni[$i]:-0}${ipop[$i]:+ ipop=${ipop[$i]}}${dstport[$i]:+ dstport=${dstport[$i]}}${ipsec[$i]:+ ipsec=${ipsec[$i]}}${keepalive[$i]:+ keepalive=${keepalive[$i]}}${txkbps[$i]:+ txkbps=${txkbps[$i]}}${ipsec[$i]:+ aeskey=${aesval[$i]}}"
		
		[ $RTT_VER_STAGE -ge 10 ] && {
        	# add tos
        	[ -n "${tos[$i]}" ] && cmdline="$cmdline ${tos[$i]:+ tos=${tos[$i]}}"
        }
		echo $cmdline  > /sys/kernel/ltt/tunnels
	done

	### check RTT tunnel in /sys/kernel/ltt/tunnels  ??is useful?
	for((i=0;i<$arr_length;i++)); do
	 	[ -n "$1" -a "$1"0 != "${confname[$i]}"0 ] && continue

		success=0

		sip="[[:digit:]]+\\.[[:digit:]]+\\.[[:digit:]]+\\.[[:digit:]]+"
		dip=${dstip[$i]//./\\.}
		for j in 1 2 3 4 5; do
			cat	/sys/kernel/ltt/tunnels	| grep -E "${ifname[$i]}${sip:+[[:space:]]+$sip}[[:space:]]+${dip}[[:space:]]+${dstport[$i]}[[:space:]]+${vni[$i]:-0}[[:space:]]+" >/dev/null 2>&1
			[ $? = 0 ] && {
				success=1
				break
			}
			sleep 1
		done
		
		if [ $success -eq 1 ]; then
			#ifconfig $ifname $localip pointopoint $remoteip
			echo -n	"start ${confname[$i]}"
			success; echo
		else
			echo -n	"start ${confname[$i]}"
			failure; echo
			continue
		fi

        ### ifconfig $ifname $localip pointopoint $remoteip
		for	k in 1 2 3;	do
			ifconfig ${ifname[$i]} >/dev/null 2>&1 && break
			sleep 1
		done

		ifconfig ${ifname[$i]} ${localip[$i]} pointopoint ${remoteip[$i]}
	done

	unset confname dstport dstip ip ifname tcptun udptun	passive	vni	ipop keepalive txkbps ipsec inspi outspi md5val des3val aesval reqid encmethod
}

function stopRtt() {
	local bn
	
	cd $rttWork

	[ -d /sys/kernel/ltt ] || {
		echo 'Please start LotServer first'
		return
	}

    rowNum=$(cat /sys/kernel/ltt/tunnels | wc -l)
    eval $(cat /sys/kernel/ltt/tunnels | awk 'NR == 1, gsub(/\([^\)]*\)/, "", $0) {print "titles=("$0")"}')
    eval $(cat /sys/kernel/ltt/tunnels | awk '{if(NR == 1) { gsub(/\([^\)]*\)/, "", $0); for(i = 1; i <= NF; i++) { title[i] = $i; } } else for(i = 1; i <= NF; i++) { print title[i]"_"NR"="$i } }')

    [ $rowNum -le 1 ] && return;

	### Read All RTT Config
	parseAllRttConf

	local arr_length=${#ifname[*]}

    for ((row = 2; row <= $rowNum; row++)); do
        eval ifname_t=\$ifname_$row		
		eval confname_t=`findConfnameByIfname $ifname_t`
	
		[ -n "$1" -a "$confname_t"0 != "$1"0 ] && continue
	  	for ((idx = 0; idx < $arr_length; idx++)); do
	  	 	[ "$confname_t"0 == "${confname[$idx]}"0 ] && break		
		done
		
		cmd=''

        for title in ${titles[@]}; do
            [ "$title" = "state" -o "$title" = "ipop" -o "$title" = "aeskey" ] && continue
            eval val=\$${title}_$row
            cmd="$cmd $title=$val"
        done

        echo "-$cmd" > /sys/kernel/ltt/tunnels

        success=0
        for i in 1 2 3 4 5; do
		    cat /sys/kernel/ltt/tunnels	| grep - "${ifname_t}[[:space:]]+" >/dev/null 2>&1
            [ $? -ne 0 ] && {
                success=1
                break
            }
            sleep 1
        done
       	

		if [ $success -eq 1 ]; then
            echo -n	"stop ${confname_t:---}"
			success; echo
		else
			echo -n	"stop ${confname_t:---}"
			failure; echo
		fi
    done
	unset confname dstport dstip ip ifname tcptun udptun	passive	vni	ipop keepalive txkbps ipsec inspi outspi md5val des3val aesval reqid encmethod
}

function restartRtt() {
	stopRtt $1
	sleep 5
	startRtt $1
}

function reloadRtt() {
	startRtt $1
}

showRttStatus() {
	cd $rttWork

	[ -d /sys/kernel/ltt ] || {
		echo 'Please start LotServer first'
		return 1
	}

    rowNum=$(cat /sys/kernel/ltt/tunnels | wc -l)
    eval $(cat /sys/kernel/ltt/tunnels | awk 'NR == 1, gsub(/\([^\)]*\)/, "", $0) {print "titles=("$0")"}')
    eval $(cat /sys/kernel/ltt/tunnels | awk '{if(NR == 1) { gsub(/\([^\)]*\)/, "", $0); for(i = 1; i <= NF; i++) { title[i] = $i; } } else for(i = 1; i <= NF; i++) { print title[i]"_"NR"="$i } }')
    
    [ $rowNum -le 1 ] && {
        echo 'no running RTT tunnels'
        return;
    }
    
	### Read All RTT Config
	parseAllRttConf

	local arr_length=${#ifname[*]}
  
    lines="config ${titles[@]%%state} localip remoteip state"
    for ((row = 2; row <= $rowNum; row++)); do
        eval ifname_t=\$ifname_$row 		
		eval confname_t=`findConfnameByIfname $ifname_t`

		[ -n "$1" -a "$confname_t"0 != "$1"0 ] && continue
	  	for ((idx = 0; idx < $arr_length; idx++)); do
	  	 	[ "$confname_t"0 == "${confname[$idx]}"0 ] && break		
		done
		
        eval addr=$(ip addr	show ${ifname[$idx]} 2>/dev/null | awk '/inet/ {print "("$2,$4")"}')
		laddr=${addr[0]:--}
		raddr=${addr[1]%%/32}
		raddr=${raddr:--}

        line=$confname_t
        for title in ${titles[@]%%state} localip remoteip state; do
            eval val=\$${title}_$row
            if [ "$title" = "localip" ]; then
                val=$laddr
            elif [ "$title" = "remoteip" ]; then
                val=$raddr
            elif [ "$title" = "state" ]; then
                if [ "$val" = "UP" ];	then
                    val="\\033[1;32mUP\\033[0;39m"
                elif [ "$val" = "DOWN" ];	then
                    val="\\033[1;33mDOWN\\033[0;39m"
                else
                    val="\\033[1;31mSTOP\\033[0;39m"
                fi
            fi
            line="$line $val"
        done
        #echo "-$cmd"
        lines="$lines\n$line"

    done
    echo -e	"$lines" | column	-t
    unset lines line
   	unset confname dstport dstip ip ifname tcptun udptun	passive	vni	ipop keepalive txkbps ipsec inspi outspi md5val des3val aesval reqid encmethod
}

initConf
[ $? -eq 2 ] && {
	activate
	exit
}

getVerStage
if [ "$bn" = "pppup" -o "$bn" = "ip-up.local" ]; then
	[ "$accppp" != "1" ] && exit 0
	pppUp $1
	exit 0
elif [ "$bn" = "pppdown" -o "$bn" = "ip-down.local" ]; then
	[ "$accppp" != "1" ] && exit 0
	pppDown $1
	exit 0
fi

[ -z $1 ] && disp_usage
[ -d /var/run ] || mkdir -p /var/run
[ -d /etc/rtt ] || mkdir /etc/rtt
[ -f /var/run/$PRODUCT_ID.pid ] && {
	pid=$(cat /var/run/$PRODUCT_ID.pid)
	kill -0 $pid 2>/dev/null
	[ $? -eq 0 ] && {
		echo "$SHELL_NAME is still running, please try again later"
		exit 2
	}
}
case "$1" in
	stop)
		if [ "$bn" = "rtt" ]; then
			# stop rtt services
			stopRtt $2
		else
			#stop LotServer
			echo $$ > /var/run/$PRODUCT_ID.pid
			stop $2
			[ -f /var/run/$PRODUCT_ID.pid ] && rm -f /var/run/$PRODUCT_ID.pid
		fi
		;;
	start)
		if [ "$bn" = "rtt" ]; then
			# start rtt services
			startRtt $2
		else
			# start LotServer
			echo $$ > /var/run/$PRODUCT_ID.pid
			start
			[ -f $ROOT_PATH/bin/.debug.sh ] && $ROOT_PATH/bin/.debug.sh >/dev/null 2>&1 &
			[ -f $afterLoad ] && chmod +x $afterLoad && $afterLoad >/dev/null 2>&1 &
			sleep 1
			echo
			[ -f /var/run/$PRODUCT_ID.pid ] && rm -f /var/run/$PRODUCT_ID.pid
		fi
		;;
	reload)
		if [ "$bn" = "rtt" ]; then
			# reload rtt services
			reloadRtt $2
		else
			# reload LotServer
			echo $$ > /var/run/$PRODUCT_ID.pid
			pkill -0 $KILLNAME 2>/dev/null || {
				start
				[ -f /var/run/$PRODUCT_ID.pid ] && rm -f /var/run/$PRODUCT_ID.pid
				exit 0
			}
			#check whether accif is changed
			accIfChanged=0
			curWanIf=$(getParam 0 wanIf)
			[ ${#accif} -ne ${#curWanIf} ] && accIfChanged=1
			[ $accIfChanged -eq 0 ] && {
				for aif in $accif; do
					[ "${curWanIf/$aif}" = "$curWanIf" ] && {
						accIfChanged=1
						break
					}
				done
			}
			[ $accIfChanged -eq 1 -a $usermode -eq 0 ] && {
				[ -f $OFFLOAD_BAK ] && /bin/bash $OFFLOAD_BAK 2>/dev/null
				[ "$detectInterrupt" = "1" ] && {
					[ -f /var/run/$PRODUCT_ID.pid ] && rm -f /var/run/$PRODUCT_ID.pid
					$0 restart
					exit
				}
				
				#disable tso&gso&sg
				cat /dev/null > $OFFLOAD_BAK
				checkInfOffload "$accif"
				case $? in
					1)
						echo "Can not disable tso(tcp segmentation offload) of $x, exit!" >&2
						exit 1
						;;
					2)
						echo "Can not disable gso(generic segmentation offload) of $x, exit!" >&2
						exit 1
						;;
					3)
						echo "Can not disable gro(generic receive offload) of $x, exit!" >&2
						exit 1
						;;
					4)
						echo "Can not disable lro(large receive offload) of $x, exit!" >&2
						exit 1
						;;
				esac
			}
			initConfigEng
			getCpuNum 1
			enum=0
			while [ $enum -lt $CPUNUM ]; do
				configEng $enum
				enum=`expr $enum + 1`
			done
			#[ -f $ROOT_PATH/bin/apxClsfCfg  -a -f $ROOT_PATH/etc/clsf ] && $ROOT_PATH/bin/apxClsfCfg 2>/dev/null
			[ -f /var/run/$PRODUCT_ID.pid ] && rm -f /var/run/$PRODUCT_ID.pid
		fi
		;;
	restart)
		if [ "$bn" = "rtt" ]; then
			# restart rtt services
			restartRtt $2
		else
			echo $$ > /var/run/$PRODUCT_ID.pid
			restart $2
			[ -f /var/run/$PRODUCT_ID.pid ] && rm -f /var/run/$PRODUCT_ID.pid
		fi
		;;
   	status|st)
   		if [ "$bn" = "rtt" ]; then
			# restart rtt services
			showRttStatus $2
		else
	   		showStatus $2
	   	fi
   		;;
   	stats)
   		[ $VER_STAGE -eq 1 ] && {
   			echo 'Not available for this version!'
   			exit 1
   		}
   		[ -f $ROOT_PATH/bin/utils.sh ] || {
   			echo "Missing $ROOT_PATH/bin/utils.sh"
   			exit 1
   		}
   		trap - 1 2 3 6 9 15
   		$ROOT_PATH/bin/utils.sh $2
   		;;
   	uninstall|uninst)
   		shift
   		echo $$ > /var/run/$PRODUCT_ID.pid
   		uninstall $1
   		[ -f /var/run/$PRODUCT_ID.pid ] && rm -f /var/run/$PRODUCT_ID.pid
   		;;
	*)
	 	disp_usage
		;;
esac
