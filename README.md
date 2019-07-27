# lotServer
### 支持系统看log文件



## Debian/Unbuntu 自动自动内核 (必须，运行后需重启)
```
bash <(wget --no-check-certificate -qO- https://github.com/fei5seven/lotServer/raw/master/Debian_Kernel.sh)
```



## 用户安装
### 常规自动安装（推荐，自动检测内核）
```
bash <(wget --no-check-certificate -qO- https://github.com/fei5seven/lotServer/raw/master/Install.sh) install
```

### 指定内核安装
```
bash <(wget --no-check-certificate -qO- https://github.com/fei5seven/lotServer/raw/master/Install.sh) install <Kernel Version>
```

## 完全卸载
```
bash <(wget --no-check-certificate -qO- https://github.com/fei5seven/lotServer/raw/master/Install.sh) uninstall
```



## CentOS用户如遇内核不能匹配, 请参照以下示例:
### 使用锐速安装脚本,得知不能匹配到内核.
### 通过 uname -r 查看到的版本号为 2.6.32-642.el6.x86_64 ,
### 去查看锐速版本库发现有个内核版本很接近 2.6.32-573.1.1.el6.x86_64 .
### 执行安装命令:
```
wget --no-check-certificate -O appex.sh https://raw.githubusercontent.com/0oVicero0/serverSpeeder_Install/master/appex.sh && chmod +x appex.sh && bash appex.sh install '2.6.32-573.1.1.el6.x86_64'
```
### 锐速安装脚本就会强制安装内核版本为 2.6.32-573.1.1.el6.x86_64 的锐速.
### 安装命令中的 2.6.32-573.1.1.el6.x86_64 可自行更改.
### 启动锐速
### 如果启动成功，恭喜你!
### 如果启动失败，请重复 2-5 步骤!
### 不要害怕失败,安装失败并不会影响系统运行.




## 使用方法:
### 启动命令 /appex/bin/lotServer.sh start
### 停止加速 /appex/bin/lotServer.sh stop
### 状态查询 /appex/bin/lotServer.sh status
### 重新启动 /appex/bin/lotServer.sh restart



## 小内存机器（小于1G）建议设置(free memory低于120M时自动清理内存，比较安全）
```
echo 120000 > /proc/sys/vm/min_free_kbytes
```
或者
```
sysctl -w vm.min_free_kbytes=120000
sysctl -p
```



## 许可证生成 -->[萌咖 API接口](https://moeclub.org/api)  
### 如果无法生成许可证,可能API正在被无聊的人攻击.

## [常见问答](https://github.com/MoeClub/lotServer/wiki)     

## [更新历史](http://download.appexnetworks.com.cn/releaseNotes/)     

  