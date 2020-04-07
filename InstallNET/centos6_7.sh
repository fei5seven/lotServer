#!/bin/bash
echo '
[upg]
name=CentOS-$releasever - Upgrade Tool
baseurl=http://dev.centos.org/centos/6/upg/x86_64/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6
' >>/etc/yum.repos.d/upgradetool.repo
echo '
#!/bin/bash
ln -s /usr/lib64/libsasl2.so.3.0.0 /usr/lib64/libsasl2.so.2
ln -s /usr/lib64/libpcre.so.1.2.0 /usr/lib64/libpcre.so.0
service sshd restart
' > start.sh
chmod +x start.sh
chmod +x /etc/rc.d/rc.local
echo 'bash /root/start.sh' >>/etc/rc.d/rc.local
yum install redhat-upgrade-tool preupgrade-assistant-contents -y
yum erase openscap -y
yum install http://dev.centos.org/centos/6/upg/x86_64/Packages/openscap-1.0.8-1.0.1.el6.centos.x86_64.rpm -y
yum install redhat-upgrade-tool preupgrade-assistant-contents -y
preupg -s CentOS6_7 <<EOF
y
EOF
rpm --import http://mirror.centos.org/centos/RPM-GPG-KEY-CentOS-7
centos-upgrade-tool-cli --network 7 --instrepo=http://vault.centos.org/centos/7.2.1511/os/x86_64/ <<EOF
y
EOF
reboot