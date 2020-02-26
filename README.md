# frok自萌咖（moeclub）大佬的lotServer
~~目前一直在调整参数，希望找到常规linux死机的原因。（aws gcp aliyun都不会死机，但linode digitalvm kagoya等常规vps都会概率死机）  
基本找到死机原因了，是ss或者v2进程与内存自动清理程序ksoftirqd/0 互殴导致CPU占满被母鸡关机了，解决方法看优化内存相关）~~  
 - 新增一个控制CPU防止ubuntu死机的方法，实际效果不佳，推荐使用centos安装3.11.36.2版本（gtmd ubuntu)  
 - 内存低于512M不建议使用，一定会死机  
***
***
  * [更换内核相关](#更换内核相关)
  * [用户安装](#用户安装)
  * [使用方法](#使用方法)
  * [优化内存相关](#优化内存相关)
  * [控制锐速CPU峰值防止死机](#控制锐速CPU峰值防止死机)
  * [重装系统相关](#重装系统相关)
  * [linode白嫖20刀方法](#linode白嫖20刀方法)
  * [萌咖大佬相关](#萌咖大佬相关)
***
***
## 更换内核相关
### Debian/Unbuntu 自动更换内核 (必须，运行后需重启)
```
bash <(wget --no-check-certificate -qO- wget https://git.io/Kernel.sh)
```
### CentOS用户如遇内核不能匹配, 请参照以下示例
 > 使用锐速安装脚本,得知不能匹配到内核.  
 通过 uname -r 查看到的版本号为 2.6.32-642.el6.x86_64 ,  
 去查看锐速版本库发现有个内核版本很接近 2.6.32-573.1.1.el6.x86_64 .  
 执行安装命令:  
```
bash <(wget --no-check-certificate -qO-  https://git.io/lotServerInstall.sh) install 2.6.32-573.1.1.el6.x86_64
```
 > 锐速安装脚本就会强制安装内核版本为 2.6.32-573.1.1.el6.x86_64 的锐速.  
 安装命令中的 2.6.32-573.1.1.el6.x86_64 可自行更改.  
 启动锐速  
 如果启动成功，恭喜你!  
 如果启动失败，请重复 2-5 步骤!  
 不要害怕失败,安装失败并不会影响系统运行.
***
***
## 用户安装  
 ~~（脚本内置许可证的接口为我自己的接口了，有效期9999年那种 笑）~~
 > 常规自动安装（推荐，自动检测内核）
```
bash <(wget --no-check-certificate -qO-  https://git.io/lotServerInstall.sh) install
```

 > 指定内核安装
```
bash <(wget --no-check-certificate -qO-  https://git.io/lotServerInstall.sh) install <Kernel Version>
```

 > 完全卸载
```
bash <(wget --no-check-certificate -qO-  https://git.io/lotServerInstall.sh) uninstall
```
***
***
## 使用方法
- 启动命令 /appex/bin/lotServer.sh start
- 停止加速 /appex/bin/lotServer.sh stop
- 状态查询 /appex/bin/lotServer.sh status
- 重新启动 /appex/bin/lotServer.sh restart
***
***
## 优化内存相关
#### 机器内存控制建议设置选项
设置内存低于阈值清理内存，数值不建议过高，并关闭oom自动杀进程功能方式锐速多次启动导致宕机。
(示例：free memory低于60M自动清理内存，保证锐速加速所需内存还不至于进程互相打架）
```
vim /etc/rc.local
````
- 在exit 0前添加（这里的oom不确定有没有用，建议用下面的）
````
sysctl -w vm.min_free_kbytes=30000
sysctl -w vm.panic_on_oom=1
sysctl -p
````
关闭oom(1为开启）
````
# echo "0" > /proc/sys/vm/oom-kill
````
#### 增加swap分区空间
(针对特殊实例如kagoya等没有设置swap分区的IDC,示例为增加1G空间，实际需求与内存对等即可)
设置swap分区为1G
````
dd if=/dev/zero of=/home/swap bs=1024 count=1024000
````
更改swap分区
````
/sbin/mkswap /home/swap
````
激活swap分区
````
/sbin/swapon /home/swap
````
以上修改重启就会丢失，修改swap分区永久有效方法
````
vim /etc/fstab
````
增加如下一行
````
/home/swap swap swap defaults 0 0
````
***
***
## 控制锐速CPU峰值防止死机
安装必须软件
```
apt-get install cpulimit
```
~~配置锐速限制示例(这里Ubuntu_18.04_4.15.0-30-generic自行替换对应版本） 懒得写脚本，每次开机必须重新配置~~  
临时性的写了一个脚本(cpulimit文件夹里）应对我搜集的可能解决死机的方案，可行性很差，还是抑制不了死机，继续自己测试。脚本自己设置开机启动吧.

***
***
## 重装系统相关
 > 默认密码root密码为fei5seven(安装后只有系统和基本软件，其他软件都没有）
Debian/Ubuntu:
````
apt-get update
````
RedHat/CentOS:
````
yum update
````
确保安装了所需软件:
Debian/Ubuntu:
````
apt-get install -y xz-utils openssl gawk file
````
RedHat/CentOS:
````
yum install -y xz openssl gawk file
````
安装centos6.10 (-firmware 额外驱动支持)
````
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/fei5seven/lotServer/master/InstallNET/InstallNET.sh') -c 6.10 -v 64 -a -firmware
````
安装debian9 (-firmware 额外驱动支持)
````
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/fei5seven/lotServer/master/InstallNET/InstallNET.sh') -d 9 -v 64 -a -firmware
````
安装ubuntu16.04 (-firmware 额外驱动支持)
````
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/fei5seven/lotServer/master/InstallNET/InstallNET.sh') -u 16.04 -v 64 -a -firmware
````
安装ubuntu18.04 (-firmware 额外驱动支持)
````
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/fei5seven/lotServer/master/InstallNET/InstallNET.sh') -u 18.04 -v 64 -a -firmware
````
说明：
bash InstallNET.sh      -d/--debian [dist-name]
                                -u/--ubuntu [dist-name]
                                -c/--centos [dist-version]
                                -v/--ver [32/i386|64/amd64]
                                --ip-addr/--ip-gate/--ip-mask
                                -apt/-yum/--mirror
                                -dd/--image
                                -a/-m

- dist-name: 发行版本代号
- dist-version: 发行版本号
- -apt/-yum/--mirror : 使用定义镜像
- -a/-m : 询问是否能进入VNC自行操作. -a 为不提示(一般用于全自动安装), -m 为提示.  

- centos6.10升级centos7  
安装依赖列表
yum源文件/etc/yum.repos.d/upgrade.repo，内容为
```
[upgrade]
name=upgrade
baseurl=http://dev.centos.org/centos/6/upg/x86_64/
enabled=1
gpgcheck=0
```
- 安装依赖包
```
yum install preupgrade-assistant-contents redhat-upgrade-tool preupgrade-assistant
```
- 校验升级  
执行刚刚安装的命令
preupg

- 导入yum的GPG密钥
```
rpm --import http://mirror.centos.org/centos/RPM-GPG-KEY-CentOS-7
```
- 开始升级  
执行升级命令
```
/usr/bin/redhat-upgrade-tool-cli --force --network 7 --instrepo=http://mirror.centos.org/centos/7/os/x86_64
```

可以换成阿里云的镜像，速度会快一些
```
/usr/bin/redhat-upgrade-tool-cli --force --network 7 --instrepo=http://mirrors.aliyun.com/centos/7/os/x86_64/
```
如果遇到报错
Error: database disk image is malformed
清除缓存，再次重试
```
yum clean dbcache
```
重启
```
reboot
```
### 安装中文语言包
- 安装中文语言包
````
sudo apt-get install  language-pack-zh-han*
````
- 安装gnome包
````
sudo apt-get install   language-pack-gnome-zh-han*
````
- 安装kde包
````
sudo apt-get install   language-pack-kde-zh-han*
````
- 到这里就能够查看目录下面的中文字符了。
- 最后运行语言支持检查
````
sudo apt install $(check-language-support)
````
### ssh登陆显示详细信息
````
sudo apt-get install landscape-common
sudo apt-get install update-notifier-common
````
***
***
## linode白嫖20刀方法
- [注册我的refer链接,每人获得20刀，感谢点击](https://www.linode.com/?r=88190ba8ace938de1db8a94410586dfbe1a53e85)
- 注册时促销代码填写podcastinit2019 完成后可以立即获得20刀，免费用4个月。
- 之后还想白嫖可以重装下系统换个IP清除浏览器cookie后再次使用。
- 感谢您使用我的refer链接，谢谢谢谢！

## 萌咖大佬相关

## 许可证生成 -->[萌咖 API接口](https://moeclub.org/api)  
- 如果无法生成许可证,可能API正在被无聊的人攻击.

## [常见问答](https://github.com/MoeClub/lotServer/wiki)     

## [更新历史](http://download.appexnetworks.com.cn/releaseNotes/)     

  
