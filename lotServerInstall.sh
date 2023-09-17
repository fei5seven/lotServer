#!/bin/bash

function Welcome()
{
clear
echo -n "                      Local Time :   " && date "+%F [%T]       ";
echo "            ======================================================";
echo "            |                      lotServer                     |";
echo "            |                                     for Linux      |";
echo "            |----------------------------------------------------|";
echo "            |                                   --By fei5seven   |";
echo "            ======================================================";
echo "";
root_check;
mkdir -p /tmp
cd /tmp
}

function root_check()
{
if [[ $EUID -ne 0 ]]; then
  echo "Error:This script must be run as root!" 1>&2
  exit 1
fi
}

function pause()
{
read -n 1 -p "Press Enter to Continue..." INP
if [ "$INP" != '' ] ; then
  echo -ne '\b \n'
  echo "";
fi
}

function dep_check()
{
  apt-get >/dev/null 2>&1
  [ $? -le '1' ] && apt-get -y -qq install sed grep gawk ethtool >/dev/null 2>&1
  yum >/dev/null 2>&1
  [ $? -le '1' ] && yum -y -q install sed grep gawk ethtool >/dev/null 2>&1
}

function acce_check()
{
  local IFS='.'
  read ver01 ver02 ver03 ver04 <<<"$1"
  sum01=$[$ver01*2**32]
  sum02=$[$ver02*2**16]
  sum03=$[$ver03*2**8]
  sum04=$[$ver04*2**0]
  sum=$[$sum01+$sum02+$sum03+$sum04]
  [ "$sum" -gt '12885627914' ] && echo "1" || echo "0"
}

function Install()
{
  Welcome;
  echo 'Preparatory work...'
  Uninstall;
  dep_check;
  [ -f /etc/redhat-release ] && KNA=$(awk '{print $1}' /etc/redhat-release)
  [ -f /etc/os-release ] && KNA=$(awk -F'[= "]' '/PRETTY_NAME/{print $3}' /etc/os-release)
  [ -f /etc/lsb-release ] && KNA=$(awk -F'[="]+' '/DISTRIB_ID/{print $2}' /etc/lsb-release)
  KNB=$(getconf LONG_BIT)
  [ ! -f /proc/net/dev ] && echo -ne "I can not find network device! \n\n" && exit 1;
  Eth_List=`cat /proc/net/dev |awk -F: 'function trim(str){sub(/^[ \t]*/,"",str); sub(/[ \t]*$/,"",str); return str } NR>2 {print trim($1)}'  |grep -Ev '^lo|^sit|^stf|^gif|^dummy|^vmnet|^vir|^gre|^ipip|^ppp|^bond|^tun|^tap|^ip6gre|^ip6tnl|^teql|^venet' |awk 'NR==1 {print $0}'`
  [ -z "$Eth_List" ] && echo "I can not find the server pubilc Ethernet! " && exit 1
  Eth=$(echo "$Eth_List" |head -n1)
  [ -z "$Eth" ] && Uninstall "Error! Not found a valid ether. "
  Mac=$(cat /sys/class/net/${Eth}/address)
  [ -z "$Mac" ] && Uninstall "Error! Not found mac code. "
  URLKernel='https://github.com/fei5seven/lotServer/raw/master/lotServer.log'
  AcceData=$(wget --no-check-certificate -qO- "$URLKernel")
  AcceVer=$(echo "$AcceData" |grep "$KNA/" |grep "/x$KNB/" |grep "/$KNK/" |awk -F'/' '{print $NF}' |sort -nk 2 -t '_' |tail -n1)
  MyKernel=$(echo "$AcceData" |grep "$KNA/" |grep "/x$KNB/" |grep "/$KNK/" |grep "$AcceVer" |tail -n1)
  [ -z "$MyKernel" ] && echo -ne "Kernel not be matched! \nYou should change kernel manually, and try again! \n\nView the link to get details: \n"$URLKernel" \n\n\n" && exit 1
  pause;
  KNN=$(echo "$MyKernel" |awk -F '/' '{ print $2 }') && [ -z "$KNN" ] && Uninstall "Error! Not Matched. "
  KNV=$(echo "$MyKernel" |awk -F '/' '{ print $5 }') && [ -z "$KNV" ] && Uninstall "Error! Not Matched. "
  AcceRoot="/tmp/lotServer"
  AcceTmp="${AcceRoot}/apxfiles"
  AcceBin="acce-"$KNV"-["$KNA"_"$KNN"_"$KNK"]"
  mkdir -p "${AcceTmp}/bin/"
  mkdir -p "${AcceTmp}/etc/"
  wget --no-check-certificate -qO "${AcceTmp}/bin/${AcceBin}" "https://github.com/fei5seven/lotServer/raw/master/${MyKernel}"
  [ ! -f "${AcceTmp}/bin/${AcceBin}" ] && Uninstall "Download Error! Not Found ${AcceBin}. "
  Welcome;
  wget --no-check-certificate -qO "/tmp/lotServer.tar" "https://github.com/fei5seven/lotServer/raw/master/lotServer.tar"
  tar -xvf "/tmp/lotServer.tar" -C /tmp
  acce_ver=$(acce_check ${KNV})
  # 如果有自己搭建的或者api失效，这里修改成你自己的api即可
  wget --no-check-certificate -qO "${AcceTmp}/etc/apx.lic" "https://speed.irsb.xyz/keygen.php?ver=${acce_ver}&mac=${Mac}"
  [ "$(du -b ${AcceTmp}/etc/apx.lic |cut -f1)" -lt '152' ] && Uninstall "Error! I can not generate the Lic for you, Please try again later. "
  echo "Lic generate success! "
  sed -i "s/^accif\=.*/accif\=\"$Eth\"/" "${AcceTmp}/etc/config"
  sed -i "s/^apxexe\=.*/apxexe\=\"\/appex\/bin\/$AcceBin\"/" "${AcceTmp}/etc/config"
  bash "${AcceRoot}/install.sh" -in 1000000 -out 1000000 -t 0 -r -b -i ${Eth}
  rm -rf /tmp/*lotServer* >/dev/null 2>&1
  Welcome;
  if [ -f /appex/bin/serverSpeeder.sh ]; then
    bash /appex/bin/serverSpeeder.sh status
  elif [ -f /appex/bin/lotServer.sh ]; then
    bash /appex/bin/lotServer.sh status
  fi
  exit 0
}

function Uninstall()
{
  AppexName="lotServer"
  [ -e /appex ] && chattr -R -i /appex >/dev/null 2>&1
  if [ -d /etc/rc.d ]; then
    rm -rf /etc/rc.d/init.d/serverSpeeder >/dev/null 2>&1
    rm -rf /etc/rc.d/rc*.d/*serverSpeeder >/dev/null 2>&1
    rm -rf /etc/rc.d/init.d/lotServer >/dev/null 2>&1
    rm -rf /etc/rc.d/rc*.d/*lotServer >/dev/null 2>&1
  fi
  if [ -d /etc/init.d ]; then
    rm -rf /etc/init.d/*serverSpeeder* >/dev/null 2>&1
    rm -rf /etc/rc*.d/*serverSpeeder* >/dev/null 2>&1
    rm -rf /etc/init.d/*lotServer* >/dev/null 2>&1
    rm -rf /etc/rc*.d/*lotServer* >/dev/null 2>&1
  fi
  rm -rf /etc/lotServer.conf >/dev/null 2>&1
  rm -rf /etc/serverSpeeder.conf >/dev/null 2>&1
  [ -f /appex/bin/lotServer.sh ] && AppexName="lotServer" && bash /appex/bin/lotServer.sh uninstall -f >/dev/null 2>&1
  [ -f /appex/bin/serverSpeeder.sh ] && AppexName="serverSpeeder" && bash /appex/bin/serverSpeeder.sh uninstall -f >/dev/null 2>&1
  rm -rf /appex >/dev/null 2>&1
  rm -rf /tmp/*${AppexName}* >/dev/null 2>&1
  [ -n "$1" ] && echo -ne "$AppexName has been removed! \n" && echo "$1" && echo -ne "\n\n\n" && exit 0
}

if [ $# == '1' ]; then
  [ "$1" == 'install' ] && KNK="$(uname -r)" && Install;
  [ "$1" == 'uninstall' ] && Welcome && pause && Uninstall "Done.";
elif [ $# == '2' ]; then
  [ "$1" == 'install' ] && KNK="$2" && Install;
else
  echo -ne "Usage:\n     bash $0 [install |uninstall |install '{Kernel Version}']\n"
fi


