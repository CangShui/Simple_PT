#!/bin/sh

echo "设置登陆账号"
read -p "请输入:" username

while [ "$username" = "admin" ] || [[ "$username" =~ ^[0-9]+$ ]]; do
    if [ "$username" = "admin" ]; then
        echo "用户名不允许是 [admin]，请重新输入:"
    else
        echo "用户名不允许是 [纯数字]，请重新输入:"
    fi
    read -p "请输入:" username
done

echo "设置登陆密码"
read -p "请输入:" password

# 用户已存在时只更新密码
pass=$(perl -e 'print crypt($ARGV[0], "password")' $password)

if id -u "$username" >/dev/null 2>&1; then
    echo "用户 [$username] 已存在，跳过创建，更新密码..."
    usermod -p "$pass" "$username"
else
    useradd -m -p "$pass" "$username"
fi

cat <<EOF > /etc/apt/sources.list
deb https://mirrors.xtom.com/debian/ bullseye main non-free contrib
deb https://mirrors.xtom.com/debian-security bullseye/updates main
deb https://mirrors.xtom.com/debian/ bullseye-updates main non-free contrib
deb https://mirrors.xtom.com/debian/ bullseye-backports main non-free contrib

deb-src https://mirrors.xtom.com/debian-security bullseye/updates main
deb-src https://mirrors.xtom.com/debian/ bullseye main non-free contrib
deb-src https://mirrors.xtom.com/debian/ bullseye-updates main non-free contrib
deb-src https://mirrors.xtom.com/debian/ bullseye-backports main non-free contrib
EOF

apt-get update
apt-get install -y psmisc

for i in {1..4}
do
  killall qbittorrent-nox
  killall filebrowser
  sleep 1s
done

# ==============================
# 安装 qBittorrent
# ==============================
wget --no-check-certificate --no-cache -O "$HOME/qbittorrent-nox" https://github.com/CangShui/Simple_PT/releases/download/V4.3.8/qbittorrent-nox && chmod +x $HOME/qbittorrent-nox
pgrep -i -f qbittorrent && pkill -s $(pgrep -i -f qbittorrent)
test -e /usr/bin/qbittorrent-nox && rm /usr/bin/qbittorrent-nox
mv $HOME/qbittorrent-nox /usr/bin/qbittorrent-nox

test -e /etc/systemd/system/qbittorrent-nox@.service && rm /etc/systemd/system/qbittorrent-nox@.service
touch /etc/systemd/system/qbittorrent-nox@.service
cat << EOF >/etc/systemd/system/qbittorrent-nox@.service
[Unit]
Description=qBittorrent
After=network.target

[Service]
Type=forking
User=$username
LimitNOFILE=infinity
ExecStart=/usr/bin/qbittorrent-nox -d
ExecStop=/usr/bin/killall -w -s 9 /usr/bin/qbittorrent-nox
Restart=on-failure
TimeoutStopSec=20
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /home/$username/qbittorrent/Downloads && chown $username /home/$username/qbittorrent/Downloads
mkdir -p /home/$username/.config/qBittorrent && chown $username /home/$username/.config/qBittorrent

systemctl enable qbittorrent-nox@$username

systemctl start qbittorrent-nox@$username
sleep 3s
systemctl stop qbittorrent-nox@$username
sleep 2s

wget --no-check-certificate --no-cache -O "$HOME/qb_password_gen" https://github.com/CangShui/Simple_PT/releases/download/V4.3.8/qb_password_gen && chmod +x $HOME/qb_password_gen
PBKDF2password=$($HOME/qb_password_gen $password)

# 写配置
rm -rf /home/$username/.config/qBittorrent/qBittorrent.conf
cat << EOF >/home/$username/.config/qBittorrent/qBittorrent.conf
[LegalNotice]
Accepted=true

[BitTorrent]
Session\BTProtocol=Both

[Network]
Cookies=@Invalid()

[Preferences]
General\Locale=zh
Connection\PortRangeMin=45000
WebUI\ClickjackingProtection=false
WebUI\HostHeaderValidation=false
Downloads\DiskWriteCacheSize=512
Downloads\SavePath=/home/$username/qbittorrent/Downloads/
Queueing\QueueingEnabled=false
WebUI\CSRFProtection=false
WebUI\Password_PBKDF2="@ByteArray($PBKDF2password)"
WebUI\Port=8080
WebUI\Username=$username
EOF

# 设置文件归属
chown $username /home/$username/.config/qBittorrent/qBittorrent.conf

rm -f $HOME/qb_password_gen
systemctl start qbittorrent-nox@$username


# ==============================
# 安装 filebrowser
# ==============================
wget --no-check-certificate --no-cache -O "$HOME/filebrowser" https://github.com/CangShui/Simple_PT/releases/download/v2.21.1/filebrowser
mv -f $HOME/filebrowser /usr/bin/filebrowser
chmod +x /usr/bin/filebrowser

cat >/lib/systemd/system/filebrowser.service <<-EOF
[Unit]
Description=Filebrowser Service
After=network.target
Wants=network.target

[Service]
Type=simple
PIDFile=/var/run/filebrowser.pid
ExecStart=/usr/bin/filebrowser -c /etc/filebrowser/filebrowser.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /etc/filebrowser
cat >/etc/filebrowser/filebrowser.json <<-EOF
{
  "port": 8888,
  "baseURL": "",
  "address": "",
  "log": "stdout",
  "database": "/etc/filebrowser/database.db",
  "root": "/etc/filebrowser/"
}
EOF

systemctl enable filebrowser

# 避免重置数据库
systemctl start filebrowser
sleep 3s
systemctl stop filebrowser
sleep 1s

# 仅在数据库不存在时才初始化（重复执行时跳过，保留原有用户数据）
if [ ! -f /etc/filebrowser/database.db ]; then
    filebrowser config init
fi

# 随机密码
psd=$(echo $RANDOM | md5sum | cut -c 1-32)
filebrowser -d /etc/filebrowser/database.db users update admin --password "$psd"
filebrowser -d /etc/filebrowser/database.db config set --locale zh-cn

#filebrowser 用户已存在时只更新密码，不重复添加
if filebrowser -d /etc/filebrowser/database.db users ls 2>/dev/null | grep -q "$username"; then
    echo "filebrowser 用户 [$username] 已存在，更新密码..."
    filebrowser -d /etc/filebrowser/database.db users update "$username" --password "$password"
else
    filebrowser -d /etc/filebrowser/database.db users add "$username" "$password" --perm.admin
    filebrowser -d /etc/filebrowser/database.db users update "$username" --scope "/"
fi

systemctl start filebrowser


# ==============================
# 输出安装结果
# ==============================
ip=$(curl -s -g http://1.0.0.10/cdn-cgi/trace | sed -n '3p') || exit 1
ip=${ip##*=}

clear
echo -e "
安装完成啦！
安装的软件信息：

qBittorrent V4.3.8
网页地址：http://$ip:8080
登陆账号：$username
登陆密码：$password

filebrowser V2.21.1
网页地址：http://$ip:8888
登陆账号：$username
登陆密码：$password

项目地址：https://github.com/CangShui/Simple_PT
"
