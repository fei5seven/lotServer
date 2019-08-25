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

HL_START="\033[37;40;1m"
HL_END="\033[0m" 

[ -z "$1" ] && {
	echo "Usage: $0 {config | all | help}"
	echo ""
	echo -e "$0 help\t\tshow available config items"
	echo -e "$0 all\t\tshow all"
	echo "e.g. $0 wanIf"
	exit 1
}

case "$1" in
	help)
		printf "${HL_START}Available config items:${HL_END}\n"
		items=$(ls /proc/net/appex/ 2>/dev/null || $apxexe | sed 's/\[.*\]//g')
		for i in $items; do
			[[ "$i" = "." || "$i" = ".." || "$i" = "cmd" || "$i" = "version" || "$i" = "ioctl" || "$i" = "stats" \
				|| "$i" = "byteCacheIoFails" || "$i" = "logLevel" || "$i" = "engine" || "$i" = "hz" ]] && {
				continue
			}
			echo -en "$i\n"
		done
		items=$(cat /proc/net/appex/cmd 2>/dev/null | awk -F: '{print $1}')
		[ -z "$items" ] && items=$($apxexe /0/cmd | awk -F: '{print $1}')
		for i in $items; do
			[ "$i" = "wanState" ] && continue
			echo -en "${i/(1~16)/}\n"
		done
	;;
    all)
    	if [ $usermode -eq 0 ]; then
	    	for engine in $(ls -d /proc/net/appex*); do
	    		printf "${HL_START}%s:${HL_END}\n" $(basename $engine)
	    		for i in $(ls $engine/); do
					[[ "$i" = "." || "$i" = ".." || "$i" = "cmd" || "$i" = "version" || "$i" = "ioctl" || "$i" = "stats" \
						|| "$i" = "byteCacheIoFails" || "$i" = "logLevel" || "$i" = "engine" || "$i" = "hz" ]] && {
						continue
					}
					value=$(cat $engine/$i)
					value=$(echo $value)
					echo -en "$i: $value\n"
				done
				cat $engine/cmd | grep -v wanState
				echo
	    	done
    	else
    		items=$($apxexe | sed 's/\[.*\]//g')
			for i in $items; do
				[[ "$i" = "." || "$i" = ".." || "$i" = "cmd" || "$i" = "version" || "$i" = "ioctl" || "$i" = "stats" \
					|| "$i" = "byteCacheIoFails" || "$i" = "logLevel" || "$i" = "engine" || "$i" = "hz" || "$i" = "guistats" ]] && {
					continue
				}
				echo -en "$i: $($apxexe /0/$i)\n"
			done
			$apxexe /0/cmd | grep -v wanState
    	fi
    ;;
    *)
    	if [ $usermode -eq 0 ]; then
	    	[ -f /proc/net/appex/$1 ] || grep "$1:" /proc/net/appex/cmd >/dev/null || [ $1 = "pcapFilterSplit" ] || {
	    		echo "Invalid config! "
	    		exit 1
	    	}
	    	for engine in $(ls -d /proc/net/appex*); do
	    		printf "${HL_START}%s:${HL_END}\n" $(basename $engine)
	    		if [ -f $engine/$1 ]; then
					value=$(cat $engine/$1)
					value=$(echo $value)
					echo -en "$1: $value\n"
				else
					cat $engine/cmd | grep $1
				fi
				echo
	    	done
	    else
	    	items=$($apxexe | sed 's/\[.*\]//g')
			for i in $items; do
				[[ "$i" != "$1" ]] && {
					continue
				}
				echo -en "$i: $($apxexe /0/$i)\n"
				exit 0
			done
			items=$($apxexe /0/cmd | awk -F: '{print $1}')
			for i in $items; do
				[[ "$i" != "$1" ]] && {
					continue
				}
				$apxexe /0/cmd | grep $1
				exit 0
			done
			[ "$1" = "pcapFilterSplit" ] && {
				$apxexe /0/cmd | grep pcapFilterSplit
				exit 0
			}
			[ "$i" != "$1" ] && echo "Invalid config! "
	    fi
    ;;
  esac