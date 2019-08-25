#!/bin/bash
# Copyright (C) 2017 AppexNetworks
# Author:	Len
# Date:		May, 2017
#

ROOT_PATH=/appex
PRODUCT_NAME=LotServer

[ -f $ROOT_PATH/etc/config ] || { echo "Missing file: $ROOT_PATH/etc/config"; exit 1; }
. $ROOT_PATH/etc/config 2>/dev/null

# Locate bc
BC=`which bc`
[ -z "$BC" ] && {
    echo "bc not found, please install \"bc\" using \"yum install bc\" or \"apt-get install bc\" according to your linux distribution"
    exit 1
}

KILLNAME=$(echo $(basename $apxexe) | sed "s/-\[.*\]//")
[ -z "$KILLNAME" ] && KILLNAME="acce-";
KILLNAME=acce-[0-9.-]+\[.*\]
pkill -0 $KILLNAME 2>/dev/null
[ $? -eq 0 ] || {
    echo "$PRODUCT_NAME is NOT running!"
    exit 1
}

CPUNUM=0
VER_STAGE=1
TOTAL_TIME=65535
CALC_ITV=5 #seconds
HL_START="\033[37;40;1m"
HL_END="\033[0m" 
[ -z "$usermode" ] && usermode=0

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
	
	boundary=$(ip2long '3.11.42.203')
	[ $intVerName -ge $boundary ] && {
		#IPv6, and related config
		VER_STAGE=33
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

getCpuNum() {
	[ $usermode -eq 1 ] && {
		CPUNUM=1
		return
	}
	[ $VER_STAGE -eq 1 ] && {
		CPUNUM=1
		return
	}
	if [ $VER_STAGE -ge 4 -a -n "$cpuID" ]; then
		CPUNUM=$(echo $cpuID | awk -F, '{print NF}')
		#num=`cat /proc/stat | grep cpu | wc -l`
		#num=`expr $num - 1`
		#[ $CPUNUM -gt $num ] && echo
	else
		num=`cat /proc/stat | grep cpu | wc -l`
		num=`expr $num - 1`
		CPUNUM=$num
		[ -n "$engineNum" ] && {
			[ $engineNum -gt 0 -a $engineNum -lt $num ] && CPUNUM=$engineNum
		}
		X86_64=$(uname -a | grep -i x86_64)
		[ -z "$X86_64" -a $CPUNUM -gt 4 ] && CPUNUM=4
	fi
	[ -n "$1" -a -n "$X86_64" -a $CPUNUM -gt 4 ] && {
		memTotal=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
		used=$(($CPUNUM * 800000)) #800M
		left=$(($memTotal - $used))
		[ $left -lt 2000000 ] && {
			HL_START="\033[37;40;1m"
			HL_END="\033[0m"
			echo -en "$HL_START"
			echo "$PRODUCT_NAME Warning: $CPUNUM engines will be launched according to the config file. Your system's total RAM is $memTotal(KB), which might be insufficient to run all the engines without performance penalty under extreme network conditions. "
			echo -en "$HL_END"
		}    
	}
}

initCmd() {
    eNum=0
    while [ $eNum -lt $CPUNUM ]; do
        if [ $usermode -eq 0 ]; then
        	e=$eNum
        	[ $e -eq 0 ] && e=''
	        [ -d /proc/net/appex$e ] && {
	            echo "displayLevel: 5" > /proc/net/appex$e/cmd
	        }
        else
        	$apxexe /$eNum/cmd="displayLevel 5"
        fi
        ((eNum = $eNum + 1))
    done
}

dump_flow()
{

	cmd="$cmd /usr/bin/printf \"total sessions: $HL_START%d$HL_END, \" $NumOfFlows;"
	cmd="$cmd /usr/bin/printf \"tcp sessions: $HL_START%d$HL_END, \" $NumOfTcpFlows;"
	cmd="$cmd /usr/bin/printf \"accelerated tcp sessions: $HL_START%d$HL_END, \" $NumOfAccFlows;"
	cmd="$cmd /usr/bin/printf \"active tcp sessions: $HL_START%d$HL_END, \" $NumOfActFlows;"
	#echo
	cmd="$cmd /usr/bin/printf \"\${showLan:+wan }in: $HL_START%.2F$HL_END kbit/s\t\${showLan:+wan }out: $HL_START%.2F$HL_END kbit/s \" $wanInRate $wanOutRate;"
	[ -n "$showLan" ] && {
		cmd="$cmd /usr/bin/printf \"lan out: $HL_START%.2F$HL_END kbit/s\tlan in:  $HL_START%.2F$HL_END kbit/s \" $lanOutRate $lanInRate;"
		cmd="$cmd /usr/bin/printf \"retransmission ratio: $HL_START%.1F %%$HL_END\" $outRatio;"
	}
	cmd="$cmd /usr/bin/printf \"\n\";"
}

dump_ipv4_flow()
{
	cmd="$cmd /usr/bin/printf \"ipv4 sessions: $HL_START%d$HL_END, \" $V4NumOfFlows;"
	cmd="$cmd /usr/bin/printf \"tcp sessions: $HL_START%d$HL_END, \" $V4NumOfTcpFlows;"
	cmd="$cmd /usr/bin/printf \"accelerated tcp sessions: $HL_START%d$HL_END, \" $V4NumOfAccFlows;"
	cmd="$cmd /usr/bin/printf \"active tcp sessions: $HL_START%d$HL_END, \" $V4NumOfActFlows;"
	[ $NfBypass -gt 0 ] && cmd="$cmd /usr/bin/printf \"Short-RTT bypassed packets: $HL_START%d$HL_END\n\" $NfBypass;"
	#echo
	cmd="$cmd /usr/bin/printf \"\${showLan:+wan }in: $HL_START%.2F$HL_END kbit/s\t\${showLan:+wan }out: $HL_START%.2F$HL_END kbit/s \" $v4wanInRate $v4wanOutRate;"
	[ -n "$showLan" ] && {
		cmd="$cmd /usr/bin/printf \"lan out: $HL_START%.2F$HL_END kbit/s\tlan in:  $HL_START%.2F$HL_END kbit/s \" $v4lanOutRate $v4lanInRate;"
		cmd="$cmd /usr/bin/printf \"retransmission ratio: $HL_START%.1F %%$HL_END\" $v4outRatio;"
	}
	cmd="$cmd /usr/bin/printf \"\n\";"
}

dump_ipv6_flow()
{
	cmd="$cmd /usr/bin/printf \"ipv6 sessions: $HL_START%d$HL_END, \" $V6NumOfFlows;"
	cmd="$cmd /usr/bin/printf \"tcp sessions: $HL_START%d$HL_END, \" $V6NumOfTcpFlows;"
	cmd="$cmd /usr/bin/printf \"accelerated tcp sessions: $HL_START%d$HL_END, \" $V6NumOfAccFlows;"
	cmd="$cmd /usr/bin/printf \"active tcp sessions: $HL_START%d$HL_END, \" $V6NumOfActFlows;"
	#echo
	cmd="$cmd /usr/bin/printf \"\${showLan:+wan }in: $HL_START%.2F$HL_END kbit/s\t\${showLan:+wan }out: $HL_START%.2F$HL_END kbit/s \" $v6wanInRate $v6wanOutRate;"
	[ -n "$showLan" ] && {
		cmd="$cmd /usr/bin/printf \"lan out: $HL_START%.2F$HL_END kbit/s\tlan in:  $HL_START%.2F$HL_END kbit/s \" $v6lanOutRate $v6lanInRate;"
		cmd="$cmd /usr/bin/printf \"retransmission ratio: $HL_START%.1F %%$HL_END\" $v6outRatio;"
	}
	cmd="$cmd /usr/bin/printf \"\n\";"
}

dump_total_flow()
{

	cmd="$cmd /usr/bin/printf \"total sessions: $HL_START%d$HL_END, \" $NumOfFlowsTotal;"
	cmd="$cmd /usr/bin/printf \"tcp sessions: $HL_START%d$HL_END, \" $NumOfTcpFlowsTotal;"
	cmd="$cmd /usr/bin/printf \"accelerated tcp sessions: $HL_START%d$HL_END, \" $NumOfAccFlowsTotal;"
	cmd="$cmd /usr/bin/printf \"active tcp sessions: $HL_START%d$HL_END, \" $NumOfActFlowsTotal;"
	#echo
	cmd="$cmd /usr/bin/printf \"\${showLan:+wan }in :  $HL_START%.2F$HL_END kbit/s\t\${showLan:+wan }out: $HL_START%.2F$HL_END kbit/s\" $wanInRateTotal $wanOutRateTotal;"
	[ -n "$showLan" ] && {
		cmd="$cmd /usr/bin/printf \" lan out: $HL_START%.2F$HL_END kbit/s\tlan in :  $HL_START%.2F$HL_END kbit/s\" $lanOutRateTotal $lanInRateTotal;"
            	
		if [ $wanOutValTotal -gt 0 ]; then
			outRatio=$(echo "($wanOutValTotal - $lanInValTotal) * 100 / $wanOutValTotal" | bc -l)
		else
			outRatio=0
		fi
		cmd="$cmd /usr/bin/printf \" retransmission ratio: $HL_START%.1F %%$HL_END \" $outRatio;"
	}
	cmd="$cmd /usr/bin/printf \"\n\";"
}

dump_total_ipv4_flow()
{
	cmd="$cmd /usr/bin/printf \"ipv4 sessions: $HL_START%d$HL_END, \" $V4NumOfFlowsTotal;"
	cmd="$cmd /usr/bin/printf \"tcp sessions: $HL_START%d$HL_END, \" $V4NumOfTcpFlowsTotal;"
	cmd="$cmd /usr/bin/printf \"accelerated tcp sessions: $HL_START%d$HL_END, \" $V4NumOfAccFlowsTotal;"
	cmd="$cmd /usr/bin/printf \"active tcp sessions: $HL_START%d$HL_END, \" $V4NumOfActFlowsTotal;"
	cmd="$cmd /usr/bin/printf \"Short-RTT bypassed packets: $HL_START%d$HL_END\n\" $NfBypassTotal;"
	#echo
	cmd="$cmd /usr/bin/printf \"\${showLan:+wan }in :  $HL_START%.2F$HL_END kbit/s\t\${showLan:+wan }out: $HL_START%.2F$HL_END kbit/s\" $v4wanInRateTotal $v4wanOutRateTotal;"
	[ -n "$showLan" ] && {
		cmd="$cmd /usr/bin/printf \" lan out: $HL_START%.2F$HL_END kbit/s\tlan in :  $HL_START%.2F$HL_END kbit/s\" $v4lanOutRateTotal $v4lanInRateTotal;"
            	
		if [ $v4wanOutValTotal -gt 0 ]; then
			v4outRatio=$(echo "($v4wanOutValTotal - $v4lanInValTotal) * 100 / $v4wanOutValTotal" | bc -l)
		else
			v4outRatio=0
		fi
		cmd="$cmd /usr/bin/printf \" retransmission ratio: $HL_START%.1F %%$HL_END \" $v4outRatio;"
	}
	cmd="$cmd /usr/bin/printf \"\n\";"
}

dump_total_ipv6_flow()
{
	cmd="$cmd /usr/bin/printf \"ipv6 sessions: $HL_START%d$HL_END, \" $V6NumOfFlowsTotal;"
	cmd="$cmd /usr/bin/printf \"tcp sessions: $HL_START%d$HL_END, \" $V6NumOfTcpFlowsTotal;"
	cmd="$cmd /usr/bin/printf \"accelerated tcp sessions: $HL_START%d$HL_END, \" $V6NumOfAccFlowsTotal;"
	cmd="$cmd /usr/bin/printf \"active tcp sessions: $HL_START%d$HL_END, \" $V6NumOfActFlowsTotal;"
#	cmd="$cmd /usr/bin/printf \"Short-RTT bypassed packets: $HL_START%d$HL_END\n\" $NfBypassTotal;"
	#echo
	cmd="$cmd /usr/bin/printf \"\${showLan:+wan }in :  $HL_START%.2F$HL_END kbit/s\t\${showLan:+wan }out: $HL_START%.2F$HL_END kbit/s\" $v6wanInRateTotal $v6wanOutRateTotal;"
	[ -n "$showLan" ] && {
		cmd="$cmd /usr/bin/printf \" lan out: $HL_START%.2F$HL_END kbit/s\tlan in :  $HL_START%.2F$HL_END kbit/s\" $v6lanOutRateTotal $v6lanInRateTotal;"
            	
		if [ $v6wanOutValTotal -gt 0 ]; then
			v6outRatio=$(echo "($v6wanOutValTotal - $v6lanInValTotal) * 100 / $v6wanOutValTotal" | bc -l)
		else
			v6outRatio=0
		fi
		cmd="$cmd /usr/bin/printf \" retransmission ratio: $HL_START%.1F %%$HL_END \" $v6outRatio;"
	}
	cmd="$cmd /usr/bin/printf \"\n\";"
}


showStats() {
    initCmd
    count=0
    lstTime=$(date +%s)
    cmd=''
    showLan=''
    [ "$1" = "all" ] && showLan=1
    while [ $count -lt $TOTAL_TIME ]; do
        eNum=0
        cmd=''
        wanInRateTotal=0
        lanInRateTotal=0
        wanOutRateTotal=0
        lanOutRateTotal=0
        v4wanInRateTotal=0
        v4lanInRateTotal=0
        v4wanOutRateTotal=0
        v4lanOutRateTotal=0
        v6wanInRateTotal=0
        v6lanInRateTotal=0
        v6wanOutRateTotal=0
        v6lanOutRateTotal=0
        NumOfFlowsTotal=0
        NumOfTcpFlowsTotal=0
        NumOfAccFlowsTotal=0
        NumOfActFlowsTotal=0
        V4NumOfFlowsTotal=0
        V4NumOfTcpFlowsTotal=0
        V4NumOfAccFlowsTotal=0
        V4NumOfActFlowsTotal=0
        V6NumOfFlowsTotal=0
        V6NumOfTcpFlowsTotal=0
        V6NumOfAccFlowsTotal=0
        V6NumOfActFlowsTotal=0
        NfBypassTotal=0
        lanInValTotal=0
        wanOutValTotal=0
        v4lanInValTotal=0
        v4wanOutValTotal=0
        v6lanInValTotal=0
        v6wanOutValTotal=0
        while [ $eNum -lt $CPUNUM ]; do
        	if [ $usermode -eq 0 ]; then
        		e=$eNum
	            [ $e -eq 0 ] && e=''
	            [ -d /proc/net/appex$e ] || {
	                ((eNum = $eNum + 1))
	                continue
	            }
	            eval $(cat /proc/net/appex$e/stats | egrep '(NumOf.*Flows)|(Bytes)|(NfBypass)' | sed 's/\s*//g')
        	else
        		eval $($apxexe /$eNum/stats | egrep '(NumOf.*Flows)|(Bytes)|(NfBypass)' | sed 's/\s*//g')
        	fi
	            
            [ -z "$NumOfFlows" ] && NumOfFlows=0
            [ -z "$NumOfTcpFlows" ] && NumOfTcpFlows=0
            [ -z "$NumOfAccFlows" ] && NumOfAccFlows=0
            [ -z "$NumOfActFlows" ] && NumOfActFlows=0
            [ -z "$V4NumOfFlows" ] && V4NumOfFlows=0
            [ -z "$V4NumOfTcpFlows" ] && V4NumOfTcpFlows=0
            [ -z "$V4NumOfAccFlows" ] && V4NumOfAccFlows=0
            [ -z "$V4NumOfActFlows" ] && V4NumOfActFlows=0
            [ -z "$V6NumOfFlows" ] && V6NumOfFlows=0
            [ -z "$V6NumOfTcpFlows" ] && V6NumOfTcpFlows=0
            [ -z "$V6NumOfAccFlows" ] && V6NumOfAccFlows=0
            [ -z "$V6NumOfActFlows" ] && V6NumOfActFlows=0
            [ -z "$WanInBytes" ] && WanInBytes=0
            [ -z "$LanInBytes" ] && LanInBytes=0
            [ -z "$WanOutBytes" ] && WanOutBytes=0
            [ -z "$LanOutBytes" ] && LanOutBytes=0
            [ -z "$V4WanInBytes" ] && V4WanInBytes=0
            [ -z "$V4LanInBytes" ] && V4LanInBytes=0
            [ -z "$V4WanOutBytes" ] && V4WanOutBytes=0
            [ -z "$V4LanOutBytes" ] && V4LanOutBytes=0
            [ -z "$V6WanInBytes" ] && V6WanInBytes=0
            [ -z "$V6LanInBytes" ] && V6LanInBytes=0
            [ -z "$V6WanOutBytes" ] && V6WanOutBytes=0
            [ -z "$V6LanOutBytes" ] && V6LanOutBytes=0
            [ -z "$NfBypass" ] && NfBypass=0
            
            eval wanInPre=\$wan_in_pre_$e
            eval lanInPre=\$lan_in_pre_$e
            eval wanOutPre=\$wan_out_pre_$e
            eval lanOutPre=\$lan_out_pre_$e
            eval v4wanInPre=\$v4wan_in_pre_$e
            eval v4lanInPre=\$v4lan_in_pre_$e
            eval v4wanOutPre=\$v4wan_out_pre_$e
            eval v4lanOutPre=\$v4lan_out_pre_$e
            eval v6wanInPre=\$v6wan_in_pre_$e
            eval v6lanInPre=\$v6lan_in_pre_$e
            eval v6wanOutPre=\$v6wan_out_pre_$e
            eval v6lanOutPre=\$v6lan_out_pre_$e
            
            wanIn=$WanInBytes
            lanIn=$LanInBytes
            wanOut=$WanOutBytes
            lanOut=$LanOutBytes
            v4wanIn=$V4WanInBytes
            v4lanIn=$V4LanInBytes
            v4wanOut=$V4WanOutBytes
            v4lanOut=$V4LanOutBytes
            v6wanIn=$V6WanInBytes
            v6lanIn=$V6LanInBytes
            v6wanOut=$V6WanOutBytes
            v6lanOut=$V6LanOutBytes
            
            [ -z "$wanInPre" ] && {
                wanInPre=$wanIn
                lanInPre=$lanIn
                wanOutPre=$wanOut
                lanOutPre=$lanOut
            }
            [ -z "$v4wanInPre" ] && {
                v4wanInPre=$v4wanIn
                v4lanInPre=$v4lanIn
                v4wanOutPre=$v4wanOut
                v4lanOutPre=$v4lanOut
            }
            [ -z "$v6wanInPre" ] && {
                v6wanInPre=$v6wanIn
                v6lanInPre=$v6lanIn
                v6wanOutPre=$v6wanOut
                v6lanOutPre=$v6lanOut
            }
            
            eval wan_in_pre_$e=$wanIn
            eval lan_in_pre_$e=$lanIn
            eval wan_out_pre_$e=$wanOut
            eval lan_out_pre_$e=$lanOut
            eval v4wan_in_pre_$e=$v4wanIn
            eval v4lan_in_pre_$e=$v4lanIn
            eval v4wan_out_pre_$e=$v4wanOut
            eval v4lan_out_pre_$e=$v4lanOut
            eval v6wan_in_pre_$e=$v6wanIn
            eval v6lan_in_pre_$e=$v6lanIn
            eval v6wan_out_pre_$e=$v6wanOut
            eval v6lan_out_pre_$e=$v6lanOut

            wanInVal=$(echo "$wanIn - $wanInPre" | bc -l)
            lanInVal=$(echo "$lanIn - $lanInPre" | bc -l)
            wanOutVal=$(echo "$wanOut - $wanOutPre" | bc -l)
            lanOutVal=$(echo "$lanOut - $lanOutPre" | bc -l)
            v4wanInVal=$(echo "$v4wanIn - $v4wanInPre" | bc -l)
            v4lanInVal=$(echo "$v4lanIn - $v4lanInPre" | bc -l)
            v4wanOutVal=$(echo "$v4wanOut - $v4wanOutPre" | bc -l)
            v4lanOutVal=$(echo "$v4lanOut - $v4lanOutPre" | bc -l)
            v6wanInVal=$(echo "$v6wanIn - $v6wanInPre" | bc -l)
            v6lanInVal=$(echo "$v6lanIn - $v6lanInPre" | bc -l)
            v6wanOutVal=$(echo "$v6wanOut - $v6wanOutPre" | bc -l)
            v6lanOutVal=$(echo "$v6lanOut - $v6lanOutPre" | bc -l)
                                    
            #calc ratio
            wanInRate=$(echo "$wanInVal / (128 * $CALC_ITV)" | bc -l)
            lanInRate=$(echo "$lanInVal / (128 * $CALC_ITV)" | bc -l)
            wanOutRate=$(echo "$wanOutVal / (128 * $CALC_ITV)" | bc -l)
            lanOutRate=$(echo "$lanOutVal / (128 * $CALC_ITV)" | bc -l)
            v4wanInRate=$(echo "$v4wanInVal / (128 * $CALC_ITV)" | bc -l)
            v4lanInRate=$(echo "$v4lanInVal / (128 * $CALC_ITV)" | bc -l)
            v4wanOutRate=$(echo "$v4wanOutVal / (128 * $CALC_ITV)" | bc -l)
            v4lanOutRate=$(echo "$v4lanOutVal / (128 * $CALC_ITV)" | bc -l)
            v6wanInRate=$(echo "$v6wanInVal / (128 * $CALC_ITV)" | bc -l)
            v6lanInRate=$(echo "$v6lanInVal / (128 * $CALC_ITV)" | bc -l)
            v6wanOutRate=$(echo "$v6wanOutVal / (128 * $CALC_ITV)" | bc -l)
            v6lanOutRate=$(echo "$v6lanOutVal / (128 * $CALC_ITV)" | bc -l)
            
            # ratio of lanin wanout #(wanout - lanin) / wanout
			if [ $wanOutVal -gt 0 ]; then
				outRatio=$(echo "($wanOutVal - $lanInVal) * 100 / $wanOutVal" | bc -l)
			else
				outRatio=0
			fi
			if [ $v4wanOutVal -gt 0 ]; then
				v4outRatio=$(echo "($v4wanOutVal - $v4lanInVal) * 100 / $v4wanOutVal" | bc -l)
			else
				v4outRatio=0
			fi
			if [ $v6wanOutVal -gt 0 ]; then
				v6outRatio=$(echo "($v6wanOutVal - $v6lanInVal) * 100 / $v6wanOutVal" | bc -l)
			else
				v6outRatio=0
			fi
            
            if [ $CPUNUM -gt 1 ]; then
                ((NumOfFlowsTotal = $NumOfFlowsTotal + $NumOfFlows))
                ((NumOfTcpFlowsTotal = $NumOfTcpFlowsTotal + $NumOfTcpFlows))
                ((NumOfAccFlowsTotal = $NumOfAccFlowsTotal + $NumOfAccFlows))
                ((NumOfActFlowsTotal = $NumOfActFlowsTotal + $NumOfActFlows))
                ((V4NumOfFlowsTotal = $V4NumOfFlowsTotal + $V4NumOfFlows))
                ((V4NumOfTcpFlowsTotal = $V4NumOfTcpFlowsTotal + $V4NumOfTcpFlows))
                ((V4NumOfAccFlowsTotal = $V4NumOfAccFlowsTotal + $V4NumOfAccFlows))
                ((V4NumOfActFlowsTotal = $V4NumOfActFlowsTotal + $V4NumOfActFlows))
                ((V6NumOfFlowsTotal = $V6NumOfFlowsTotal + $V6NumOfFlows))
                ((V6NumOfTcpFlowsTotal = $V6NumOfTcpFlowsTotal + $V6NumOfTcpFlows))
                ((V6NumOfAccFlowsTotal = $V6NumOfAccFlowsTotal + $V6NumOfAccFlows))
                ((V6NumOfActFlowsTotal = $V6NumOfActFlowsTotal + $V6NumOfActFlows))
                wanInRateTotal=$(echo "$wanInRateTotal + $wanInRate" | bc -l)
                lanInRateTotal=$(echo "$lanInRateTotal + $lanInRate" | bc -l)
                wanOutRateTotal=$(echo "$wanOutRateTotal + $wanOutRate" | bc -l)
                lanOutRateTotal=$(echo "$lanOutRateTotal + $lanOutRate" | bc -l)
                v4wanInRateTotal=$(echo "$v4wanInRateTotal + $v4wanInRate" | bc -l)
                v4lanInRateTotal=$(echo "$v4lanInRateTotal + $v4lanInRate" | bc -l)
                v4wanOutRateTotal=$(echo "$v4wanOutRateTotal + $v4wanOutRate" | bc -l)
                v4lanOutRateTotal=$(echo "$v4lanOutRateTotal + $v4lanOutRate" | bc -l)
                v6wanInRateTotal=$(echo "$v6wanInRateTotal + $v6wanInRate" | bc -l)
                v6lanInRateTotal=$(echo "$v6lanInRateTotal + $v6lanInRate" | bc -l)
                v6wanOutRateTotal=$(echo "$v6wanOutRateTotal + $v6wanOutRate" | bc -l)
                v6lanOutRateTotal=$(echo "$v6lanOutRateTotal + $v6lanOutRate" | bc -l)
                ((NfBypassTotal = $NfBypassTotal + $NfBypass))
                ((wanOutValTotal = $wanOutValTotal + $wanOutVal))
                ((lanInValTotal = $lanInValTotal + $lanInVal))
                ((v4wanOutValTotal = $v4wanOutValTotal + $v4wanOutVal))
                ((v4lanInValTotal = $v4lanInValTotal + $v4lanInVal))
                ((v6wanOutValTotal = $v6wanOutValTotal + $v6wanOutVal))
                ((v6lanInValTotal = $v6lanInValTotal + $v6lanInVal))
            fi
            
			cmd="$cmd echo \"engine#$eNum:\";"
			dump_flow
			[ $VER_STAGE -ge 33 ] && {
				dump_ipv4_flow
	    		dump_ipv6_flow
	    	}
            cmd="$cmd /usr/bin/printf \"\n\";"
            ((eNum = $eNum + 1))
            ((NfBypass = 0))
        done
        if [ $CPUNUM -gt 1 ]; then
            cmd="$cmd echo \"Total:\";"
			dump_total_flow
			[ $VER_STAGE -ge 33 ] && {
				dump_total_ipv4_flow
				dump_total_ipv6_flow
			}
            cmd="$cmd /usr/bin/printf \"\n\";"
            echo
        fi
        clear
        eval $cmd
        sleep $CALC_ITV
        ((count = $count + $CALC_ITV))
    done
}

getVerStage
[ $VER_STAGE -eq 1 ] && {
	echo 'Not available for this version!'
	exit 1
}
getCpuNum
showStats $1
