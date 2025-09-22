#!/usr/bin/env bash

set -e

mkdir app
mkdir build
mkdir service

echo "--> Creating directory local bin"
mkdir -p ~/.local/bin

echo "--> Creating directory systemd user level"
mkdir -p ~/.config/systemd/user

echo "--> Configuring .bashrc"
tee -a ~/.bashrc > /dev/null <<EOF

alias ".."="cd .."
alias "c"="clear"
alias "q"="exit"
alias "v"="vi"
alias "la"="ls -alh"
alias "ll"="ls -lh"
alias "home"="cd /home/$USER"
alias "ports"="sudo ss -tulwn"
alias "ports-ls"="sudo ss -tulwn | grep LISTEN"

export NODE_ENV=production
EOF
sleep 1

echo "--> Adding sshinstance group"
sudo groupadd sshinstance
sudo usermod -aG sshinstance "$USER"

echo "--> Adding sudoinstance group"
sudo groupadd sudoinstance
sudo usermod -aG sudoinstance "$USER"
sudo cp --archive /etc/sudoers /etc/sudoers.bak
echo "%sudoinstance ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers > /dev/null

echo "--> Adding suinstance group"
sudo groupadd suinstance
sudo usermod -aG suinstance "$USER"
sudo chgrp suinstance /bin/su
sudo chmod 4750 /bin/su
echo "auth required pam_wheel.so use_uid group=suinstance" | sudo tee -a /etc/pam.d/su > /dev/null

echo "--> Configuring curl options"
tee ~/.curlrc > /dev/null <<EOF
-L
-A "Mozilla/5.0 (X11; Linux x86_64; rv:141.0) Gecko/20100101 Firefox/141.0"
-H "Cache-Control: no-cache, no-store, must-revalidate"
--retry 5
--retry-delay 5
--connect-timeout 30
EOF
sudo cp ~/.curlrc /root/.curlrc

echo "--> Configuring vi"
tee ~/.vimrc > /dev/null <<EOF
set nowrap
set number
set expandtab
set tabstop=4
set shiftwidth=4
set softtabstop=4
set autoindent
set smartindent
set nobackup
set noswapfile
set nocompatible
set backspace=indent,eol,start
map q lh
map Q lh
EOF
sudo cp ~/.vimrc /root/.vimrc

echo "--> Configuring sshd"
sudo cp --archive /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sudo tee /etc/ssh/sshd_config > /dev/null <<'EOF'
AddressFamily any

HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key

KexAlgorithms curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com

LogLevel VERBOSE

MaxAuthTries 3
MaxSessions 3

AllowGroups sshinstance

AuthenticationMethods publickey
AuthorizedKeysFile .ssh/authorized_keys

PasswordAuthentication no
PermitUserEnvironment no

Subsystem sftp internal-sftp -f AUTHPRIV -l INFO

Protocol 2
UsePAM yes
X11Forwarding no
AllowTcpForwarding no
AllowStreamLocalForwarding no
GatewayPorts no
PermitTunnel no
PermitEmptyPasswords no
IgnoreRhosts yes
UseDNS yes
Compression no
TCPKeepAlive no
AllowAgentForwarding no
PermitRootLogin no
HostbasedAuthentication no
EOF

echo "--> Checking sshd"
sudo sshd -t

echo "--> Remove short Diffie-Hellman keys"
sudo cp --archive /etc/ssh/moduli /etc/ssh/moduli.bak
sudo awk '$5 >= 3071' /etc/ssh/moduli | sudo tee /etc/ssh/moduli.tmp > /dev/null
sudo mv /etc/ssh/moduli.tmp /etc/ssh/moduli

echo "--> Updating packages, please wait"
echo "fastestmirror=True" | sudo tee -a /etc/dnf/dnf.conf > /dev/null
sudo dnf clean all
### Check
### sudo cat /etc/yum.repos.d/epel-cisco-openh264.repo
sudo dnf update -y
sudo dnf install -y dnf-utils epel-release
sudo /usr/bin/crb enable
sudo dnf install -y btop curl chrony fastfetch firewalld gzip rsync policycoreutils-python-utils tar
sudo systemctl enable --now chronyd || echo

echo "--> Configuring firewalld"
sudo systemctl enable --now firewalld
sudo firewall-cmd --permanent --remove-service=ssh
if [ "$HTTP_HTTPS" = "Y" ]; then
	sudo firewall-cmd --permanent --zone="$FIREWALL_ZONE" --add-port=80/tcp
	sudo firewall-cmd --permanent --zone="$FIREWALL_ZONE" --add-port=443/tcp
fi
sudo firewall-cmd --permanent --zone="$FIREWALL_ZONE" --add-rich-rule="rule port port=22 protocol=tcp limit value='3/m' accept"

echo "--> Restarting sshd"
sudo systemctl restart sshd
sudo firewall-cmd --reload

if [ "$FAIL2BAN" = "Y" ]; then
	echo "--> Installing fail2ban"
	sudo dnf install -y fail2ban
	sudo tee /etc/fail2ban/jail.local > /dev/null <<EOF
[DEFAULT]
banaction           = firewallcmd-rich-rules
banaction_allports  = firewallcmd-rich-rules

[sshd]
enabled  = true
port     = 22
filter   = sshd
maxretry = 3
findtime = 3h
bantime  = 1d
bantime.maxtime   = 1w
bantime.increment = true
bantime.formula   = ban.Time * ban.Count
EOF
	sudo tee /etc/fail2ban/action.d/firewallcmd-rich-rules.local > /dev/null <<'EOF'
[INCLUDES]
before = firewallcmd-common.conf

[Definition]
actionstart =
actionstop  =
actioncheck =

fwcmd_rich_rule = rule family='<family>' source address='<ip>' %(rich-suffix)s
actionban       = firewall-cmd --add-rich-rule="%(fwcmd_rich_rule)s"
actionunban     = firewall-cmd --remove-rich-rule="%(fwcmd_rich_rule)s"
rich-suffix     = <rich-blocktype>
EOF
	sudo systemctl enable --now fail2ban || echo "--> ERROR: Could not find server"
fi

if [ "$HTTP_HTTPS" = "Y" ]; then
	echo "--> Adding exception filter service"
	tee ~/.config/systemd/user/exception-filter.service > /dev/null <<EOF
[Unit]
Description=Exception Filter
After=nginx.service
Wants=nginx.service

[Service]
ExecStart=%h/service/exception-filter --port 31000
WorkingDirectory=%h/service
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=default.target
EOF
	sudo loginctl enable-linger "$USER"
	systemctl --user daemon-reload
	echo "--> Downloading exception filter"
	curl -o ~/service/exception-filter https://github.com/ryhkml/go-exception-filter/releases/download/v0.0.1/exception-filter-linux-amd64
	chmod +x ~/service/exception-filter
fi

echo "--> Updating unused boolean SELinux"
sudo setsebool -P openfortivpn_can_network_connect 0
sudo setsebool -P openvpn_can_network_connect 0
sudo setsebool -P openvpn_enable_homedirs 0
sudo setsebool -P httpd_builtin_scripting 0
sudo setsebool -P httpd_enable_cgi 0
sudo setsebool -P guest_exec_content 0

if [ "$BANDWHICH" = "Y" ]; then
	echo "--> Installing bandwhich"
	mkdir ~/build/bandwhich
	cd ~/build/bandwhich
	curl -O https://github.com/imsnif/bandwhich/releases/download/v0.23.1/bandwhich-v0.23.1-x86_64-unknown-linux-gnu.tar.gz
	tar -xvf bandwhich-v0.23.1-x86_64-unknown-linux-gnu.tar.gz
	sudo ln -sf "$(pwd)/bandwhich" /usr/bin/bandwhich
	cd "$HOME"
fi

if [ "$ZELLIJ" = "Y" ]; then
	echo "--> Installing zellij"
	mkdir ~/build/zellij
	cd ~/build/zellij
	curl -O https://github.com/zellij-org/zellij/releases/download/v0.43.1/zellij-no-web-x86_64-unknown-linux-musl.tar.gz
	tar -xvf zellij-no-web-x86_64-unknown-linux-musl.tar.gz
	ln -sf "$(pwd)/zellij" ~/.local/bin/zellij
	cd "$HOME"
fi

echo "--> Configuring the bootloader"
### Source https://cloud.google.com/compute/docs/import/import-existing-image#configure_bootloader
sudo sed -i '/^GRUB_CMDLINE_LINUX=/ s/\"$/ console=ttyS0,38400n8d\"/' /etc/default/grub
sudo grub2-mkconfig -o /boot/grub2/grub.cfg

echo "--> Removing swap"
sudo swapoff -a
sudo sed -i "/swap/ s/^/#/" /etc/fstab
sudo systemctl daemon-reload

echo "SELinux: $(getenforce)"

cd "$HOME"
history -cw
echo "DONE"
