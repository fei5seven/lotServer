# frok自萌咖（moeclub）大佬的lotServer
#### 目前一直在调整参数，希望找到常规linux死机的原因。~~（aws gcp aliyun都不会死机，但linode digitalvm kagoya等常规vps都会概率死机） ~~
#### 基本找到死机原因了，是ss或者v2进程与内存自动清理程序ksoftirqd/0 互殴导致CPU占满被母鸡关机了，解决方法看优化内存相关）
#### 内存低于512M不建议使用，一定会死机
### 支持系统看log文件
***
***
  * [更换内核相关](#更换内核相关)
  * [用户安装](#用户安装)
  * [使用方法](#使用方法)
  * [优化内存相关](#优化内存相关)
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
***
***
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
***
***
## 使用方法
- 启动命令 /appex/bin/lotServer.sh start
- 停止加速 /appex/bin/lotServer.sh stop
- 状态查询 /appex/bin/lotServer.sh status
- 重新启动 /appex/bin/lotServer.sh restart
***
***
## 优化相关
#### 机器内存控制建议设置选项
(示例：free memory低于60M自动清理内存，保证锐速加速所需内存还不至于进程互相打架）
```
vim /etc/rc.local
````
- 在exit 0前添加
````
sysctl -w vm.min_free_kbytes=30000
sysctl -p
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
- 如果无法生成许可证,可能API正在被无聊的人攻击.~~（脚本内置的接口为我自己的接口，自己选择使用吧）~~

## [常见问答](https://github.com/MoeClub/lotServer/wiki)     

## [更新历史](http://download.appexnetworks.com.cn/releaseNotes/)     

  
