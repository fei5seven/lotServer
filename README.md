# frok自萌咖（moeclub）大佬的lotServer
#### 目前一直在调整参数，希望找到常规linux死机的原因。（aws gcp aliyun都不会死机，但linode digitalvm kagoya等常规vps都会概率死机）
### 支持系统看log文件

  * [更换内核相关](#更换内核相关)
  * [用户安装](#用户安装)
  * [使用方法](#使用方法)
  * [优化相关](#优化相关)
   * [linode白嫖20刀方法](#linode白嫖20刀方法)
  * [萌咖大佬相关](#萌咖大佬相关)


## 更换内核相关
### Debian/Unbuntu 自动更换内核 (必须，运行后需重启)
```
bash <(wget --no-check-certificate -qO- wget https://git.io/Kernel.sh)
```



### CentOS用户如遇内核不能匹配, 请参照以下示例
- 使用锐速安装脚本,得知不能匹配到内核.
- 通过 uname -r 查看到的版本号为 2.6.32-642.el6.x86_64 ,
- 去查看锐速版本库发现有个内核版本很接近 2.6.32-573.1.1.el6.x86_64 .
- 执行安装命令:
```
bash <(wget --no-check-certificate -qO-  https://git.io/lotServerInstall.sh) install 2.6.32-573.1.1.el6.x86_64
```
- 锐速安装脚本就会强制安装内核版本为 2.6.32-573.1.1.el6.x86_64 的锐速.
- 安装命令中的 2.6.32-573.1.1.el6.x86_64 可自行更改.
- 启动锐速
- 如果启动成功，恭喜你!
- 如果启动失败，请重复 2-5 步骤!
- 不要害怕失败,安装失败并不会影响系统运行.



## 用户安装
- 常规自动安装（推荐，自动检测内核）
```
bash <(wget --no-check-certificate -qO-  https://git.io/lotServerInstall.sh) install
```

- 指定内核安装
```
bash <(wget --no-check-certificate -qO-  https://git.io/lotServerInstall.sh) install <Kernel Version>
```

- 完全卸载
```
bash <(wget --no-check-certificate -qO-  https://git.io/lotServerInstall.sh) uninstall
```




## 使用方法
- 启动命令 /appex/bin/lotServer.sh start
- 停止加速 /appex/bin/lotServer.sh stop
- 状态查询 /appex/bin/lotServer.sh status
- 重新启动 /appex/bin/lotServer.sh restart


## 优化相关
#### 小内存机器建议设置选项
(示例：free memory低于缺省值时自动清理内存，相对dorp cache比较安全不容易死机且稳定）
- (在exit 0前添加 推荐，永久生效)

```
vim /etc/rc.local
````
在exit 0前添加
````
sysctl -w vm.min_free_kbytes=67584
sysctl -p
reboot
````
或者
````
echo 67584 > /proc/sys/vm/min_free_kbytes
sysctl -p
reboot
````

#### 检测并修改为hybla加速模块
- 编辑 limits.conf
````
vi /etc/security/limits.conf
````
- 增加以下两行
````
* soft nofile 51200
* hard nofile 51200
````
- 开启服务之前，先设置一下 ulimit
````
ulimit -n 51200
````
##### 启用hybla算法（可选）
Linux 内核中提供了若干套 TCP 拥塞控制算法，这些算法各自适用于不同的环境。
1 ） reno 是最基本的拥塞控制算法，也是 TCP 协议的实验原型。
2 ） bic 适用于 rtt 较高但丢包极为罕见的情况，比如北美和欧洲之间的线路，这是 2.6.8 到 2.6.18 之间的 Linux 内核的默认算法。
3 ） cubic 是修改版的 bic ，适用环境比 bic 广泛一点，它是 2.6.19 之后的 linux 内核的默认算法。
4 ） hybla 适用于高延时、高丢包率的网络，比如卫星链路——同样适用于中美之间的链路。

我们需要做的工作就是将 TCP 拥塞控制算法改为 hybla 算法，并且优化 TCP 参数。

1 、查看可用的算法。
主要看内核是否支持 hybla ，如果没有，只能用 cubic 了。（一般都支持）
````
sysctl net.ipv4.tcp_available_congestion_control
````
2 、如果没有该算法，则加载 hybla 算法（不支持 OpenVZ ）
````
/sbin/modprobe tcp_hybla
````
3 、首先做好备份工作，把 sysctl.conf 备份到 root 目录
````
cp /etc/sysctl.conf /root/
````
4 、修改 sysctl.conf 配置文件，优化 TCP 参数
````
vi /etc/sysctl.conf
````
添加以下代码
````
fs.file-max = 51200
#提高整个系统的文件限制
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 3240000
 
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
#如果linux内核没到3.10，这个fastopen请注释掉
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = hybla
````
5 、保存生效
````
sysctl -p
````
6 、添加开机加载（在exit 0前添加）
````
vim /etc/rc.local
/sbin/modprobe tcp_hybla
````
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

  
