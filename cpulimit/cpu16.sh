#!/bin/sh
{
sysctl -w vm.panic_on_oom=1
sysctl -p
nohup cpulimit -e /appex/bin/acce-3.11.36.2-[Ubuntu_16.04_4.8.0-36-generic] -l 70 m>> /dev/null 2>&1 &
}