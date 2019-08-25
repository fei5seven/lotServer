#!/bin/bash
# Copyright (C) 2015 AppexNetworks
# Author:	Len
# Date:		Aug, 2015

ROOT_PATH=/appex
PRODUCT_NAME=LotServer

[ -f $ROOT_PATH/etc/config ] || { echo "Missing file: $ROOT_PATH/etc/config"; exit 1; }
. $ROOT_PATH/etc/config 2>/dev/null
#KILLNAME=$(echo $(basename $apxexe) | sed "s/-\[.*\]//")
#[ -z "$KILLNAME" ] && KILLNAME="acce-";
KILLNAME=acce-[0-9.-]+\[.*\]
pkill -0 $KILLNAME 2>/dev/null
[ $? -eq 0 ] || {
    echo "$PRODUCT_NAME is NOT running!"
    exit 1
}

help() {
	echo "Usage: $0 <config> <value1> [value2 ... [valueN]]"
	echo ""
	echo "e.g. $0 wanIf eth0"
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

item=$1
shift
value=$@

[[ -z "$item" || -z "$value" || "$item" = "-help" || "$item" = "--help" ]] && {
	help
	exit 1
}
if [ $usermode -eq 0 ]; then
	[ -f /proc/net/appex/$item ] || grep "$item:" /proc/net/appex/cmd >/dev/null || [ $item = "pcapFilterSplit" ] || {
		echo "Invalid config! "
		exit 1
	}
	
	for engine in $(ls -d /proc/net/appex*); do
		if [ -f $engine/$item ]; then
			echo "$value" > $engine/$item 2>/dev/null
			if [ $item = 'wanIf' ]; then
				saved=$(cat $engine/$item 2>/dev/null)
				saved=$(echo $saved)
		    	for if in $value; do
		    		[ "${saved/$if}" == "$saved" ] && {
		    			echo "Failed to write configuration!"
				    	exit 1
		    		}
		    	done
			else
				saved=$(cat $engine/$item 2>/dev/null)
				saved=$(echo $saved)
				[ "$value" != "$saved" ] && {
					echo "Failed to write configuration!"
					exit 1
				}
			fi
		else
			if [ "$item" = 'lanSegment' ]; then
				PATTERN='^[0-9A-Fa-f]{7,8}/[0-9]{1,2}(\s{1,}[0-9A-Fa-f]{7,8}/[0-9]{1,2}){0,}(\s{1,}[0-1]){0,1}$'
				[[ "$value" =~ $PATTERN ]] || {
					echo "Failed to write configuration: lanSegment" >&2
					exit 1
				}
				echo "$item: $value" > $engine/cmd 2>/dev/null
				saved=$(awk -F': ' "/$item(\(.*\))?:/ {print \$2}" $engine/cmd 2>/dev/null)
				saved=$(formatIPv4 $saved)
				lanSegmentV4Fmt=$(formatIPv4 $value)
				[[ "$saved" != "$lanSegmentV4Fmt" ]] && {
					echo "Failed to write configuration: lanSegment" >&2
					stop >/dev/null 2>&1
					exit 1
				}
			elif [ "$item" = 'lanSegmentV6' ]; then
				nf=`echo "$value" | awk '{print NF}'`
				for _tmp in $value; do
					((nf--))
					ipcalc -cs6 "$_tmp"
					if [[ $? -ne 0 ]]; then
						if [[ $_tmp = "0" || $_tmp = "1" ]]; then
							if [[ $nf -ne 0 ]]; then
								echo "Failed to write configuration: lanSegmentV6" >&2
								exit 1
							fi
						else
							echo "Failed to write configuration: lanSegmentV6" >&2
							exit 1
						fi
					fi
				done
				echo "$item: $value" > $engine/cmd 2>/dev/null
				saved=$(awk -F': ' "/$item(\(.*\))?:/ {print \$2}" $engine/cmd 2>/dev/null)
				saved=$(formatIPv6 $saved)
				lanSegmentV6Fmt=$(formatIPv6 $value)
				[[ "$saved" != "$lanSegmentV6Fmt" ]] && {
					echo "Failed to write configuration: lanSegmentV6" >&2
					stop >/dev/null 2>&1
					exit 1
				}
			else
				echo "$item: $value" > $engine/cmd 2>/dev/null
				saved=$(awk -F': ' "/$item(\(.*\))?:/ {print \$2}" $engine/cmd 2>/dev/null)
				[ "$value" != "$saved" ] && {
					echo "Failed to write configuration!"
					exit 1
				}
				# add mutual exclusion for ipv4Only & ipv6Only here
				if [ "$item" = "ipv4Only" -a "$value" = "1" ]; then
					echo "ipv6Only: 0" > $engine/cmd 2>/dev/null
				elif [ "$item" = "ipv6Only" -a "$value" = "1" ]; then
					echo "ipv4Only: 0" > $engine/cmd 2>/dev/null
				fi
			fi
		fi
	done
else
	for i in $($apxexe | sed 's/\[.*\]//g'); do
		[[ "$i" != "$item" ]] && continue
		$apxexe /0/$item="$value"
		saved=$($apxexe /0/$item)
		saved=$(echo $saved)
		if [ $item = 'wanIf' ]; then
	    	for if in $value; do
	    		[ "${saved/$if}" == "$saved" ] && {
	    			echo "Failed to write configuration!"
			    	exit 1
	    		}
	    	done
		else
			[ "$value" != "$saved" ] && {
				echo "Failed to write configuration!"
				exit 1
			}
		fi
		exit 0
	done
	
	for i in $($apxexe /0/cmd | awk -F: '{print $1}') pcapFilterSplit; do
		[[ "$i" != "$item" ]] && continue
		$apxexe /0/cmd="$item $value"
		
		[ $item = 'lanSegmentV6' ] && continue
		
		saved=$($apxexe /0/cmd | awk -F': ' "/$item(\(.*\))?:/ {print \$2}")
		if [ $item = 'lanSegment' ]; then
			[[ ${saved#$value} == $saved && ${value#$saved} == $value ]] && {
				echo "Failed to write configuration: lansegment"
				exit 1
			}
		else
			[ "$value" != "$saved" ] && {
				echo "Failed to write configuration!"
				exit 1
			}
		fi
		exit 0
	done
	echo "Invalid config! "
	exit 1
	
fi
