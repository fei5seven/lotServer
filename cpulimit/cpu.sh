#!/bin/sh
{
sleep 15
sysctl -w vm.min_free_kbytes=50000
sysctl -w vm.panic_on_oom=1
sysctl -p
nohup cpulimit -e acce-3.11.36.2-[Ubuntu_16.04_4.8.0-36-generic] -l 30 &
nohup cpulimit -e v2ray  -l 30 &
nohup cpulimit -e caddy  -l 30 &
nohup cpulimit -e java  -l 30 &
}
