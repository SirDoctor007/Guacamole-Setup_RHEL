#!/bin/env bash

###################################################
################## Set Variables ##################
###################################################
MAJOR_VER=`cat /etc/redhat-release | grep -oP "[0-9]+" | sed -n 1p`
GUAC_VER="1.4.0"
GUAC_URL="https://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/"

# Ports
GUAC_PORT="4822"
MYSQL_PORT="3306"

# Key Sizes
# JKSTORE_KEY_SIZE_DEF="4096" # Default Java Keystore key-size
# LE_KEY_SIZE_DEF="4096" # Default Let's Encrypt key-size
SSL_KEY_SIZE="4096" # Default Self-signed SSL key-size

# Default Credentials
MYSQL_PASSWD="guacamole" # Default MySQL/MariaDB root password
DB_NAME="guac_db" # Defualt database name
DB_USER="guac_adm" # Defualt database user name
DB_PASSWD="guacamole" # Defualt database password
JKS_GUAC_PASSWD="guacamole" # Default Java Keystore password
JKS_CACERT_PASSWD="guacamole" # Default CACert Java Keystore password, used with LDAPS

# Misc
GUACD_USER="guacd"
DOMAIN_NAME="dkolabs.com"
GUAC_URIPATH="/"
GUAC_LAN_IP="192.168.50.30"

# Dirs and File Names
INSTALL_DIR="/usr/local/src/guacamole/${GUAC_VER}/"
LIB_DIR="/etc/guacamole/"
GUAC_CONF="guacamole.properties"
GUAC_SERVER="guacamole-server-${GUAC_VER}"
GUAC_CLIENT="guacamole-${GUAC_VER}"
GUAC_JDBC="guacamole-auth-jdbc-${GUAC_VER}"
###################################################

# Disable localhost ipv6
sed -i 's/::1/# ::1/' /etc/hosts


# Check Repos
if rpm -q "epel-release"; then
	echo "epel-release is installed"
else
	echo "epel-release is missing. Installing"
	rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-${MAJOR_VER}.noarch.rpm
fi

if rpm -q "rpmfusion-free-release"; then
	echo "rpmfusion-free-release is installed"
else
	echo "rpmfusion-free-release is missing. Installing"
	rpm -Uvh https://download1.rpmfusion.org/free/el/rpmfusion-free-release-${MAJOR_VER}.noarch.rpm
fi

subscription-manager repos --enable=codeready-builder-for-rhel-8-x86_64-rpms
dnf module enable virt-devel -y

# Install Dependencies
dnf install -y wget cairo-devel libjpeg-turbo-devel libpng-devel libtool libuuid-devel ffmpeg-devel freerdp-devel pango-devel libssh2-devel libtelnet-devel libvncserver-devel libwebsockets-devel openssl-devel libvorbis-devel libwebp-devel java-11-openjdk-devel libgcrypt-devel pulseaudio-libs-devel policycoreutils-python-utils mariadb mariadb-server nginx


###################################################
################### Tomcat Setup ##################
###################################################
cd /usr/local
wget https://dlcdn.apache.org/tomcat/tomcat-9/v9.0.64/bin/apache-tomcat-9.0.64.tar.gz
tar -xvf apache-tomcat-9.0.64.tar.gz
mv apache-tomcat-9.0.64 tomcat9
rm -f apache-tomcat-9.0.64.tar.gz
useradd -r tomcat
chown -R tomcat:tomcat /usr/local/tomcat9/
 
# Create service file for auto start
cat << EOF > /etc/systemd/system/tomcat.service
[Unit]
Description=Apache Tomcat Server
After=syslog.target network.target
 
[Service]
Type=forking
User=tomcat
Group=tomcat
 
Environment=CATALINA_PID=/usr/local/tomcat9/temp/tomcat.pid
Environment=CATALINA_HOME=/usr/local/tomcat9
Environment=CATALINA_BASE=/usr/local/tomcat9
 
ExecStart=/usr/local/tomcat9/bin/catalina.sh start
ExecStop=/usr/local/tomcat9/bin/catalina.sh stop
 
RestartSec=10
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# Save and Reload the Systemd Configuration
systemctl daemon-reload
 
# Start, Enable and Verify Service
systemctl start tomcat.service
systemctl enable tomcat.service
# systemctl status tomcat.service


###################################################
################### Nginx Setup ###################
###################################################
mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.ori.bkp

cat << EOF > /etc/nginx/conf.d/guacamole.conf
server {
	listen 80;
	listen [::]:80;
	server_name ${DOMAIN_NAME};
	return 301 https://\$host\$request_uri;
	location ${GUAC_URIPATH} {
	proxy_pass http://${GUAC_LAN_IP}:8080/guacamole/;
	proxy_buffering off;
	proxy_http_version 1.1;
	proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
	proxy_set_header Upgrade \$http_upgrade;
	proxy_set_header Connection \$http_connection;
	proxy_cookie_path /guacamole/ ${GUAC_URIPATH};
	access_log off;
	}
}
EOF

#Nginx Hardening
find /etc/nginx -type d | xargs chmod 750
find /etc/nginx -type f | xargs chmod 640
sed -i '/keepalive_timeout/c\keepalive_timeout 10\;' /etc/nginx/nginx.conf

! read -r -d '' BLANK_HTML <<"EOF"
<!DOCTYPE html>
<html>
<head>
</head>
<body>
</body>
</html>
EOF

echo "${BLANK_HTML}" > /usr/share/nginx/html/index.html
echo "${BLANK_HTML}" > /usr/share/nginx/html/50x.html

sed -i "s/daily/weekly/" /etc/logrotate.d/nginx
sed -i "s/rotate 52/rotate 13/" /etc/logrotate.d/nginx

systemctl enable nginx
systemctl restart nginx
###################################################


# Create Dirs
mkdir -vp ${LIB_DIR}{extensions,lib}
mkdir -vp ${INSTALL_DIR}{client,selinux}
# mkdir -vp /usr/share/tomcat/.guacamole/


# Guacamole Server Install
#Guacamole Download
cd ${INSTALL_DIR}
wget "${GUAC_URL}source/${GUAC_SERVER}.tar.gz" -O ${GUAC_SERVER}.tar.gz
tar xzvf guacamole-server-1.4.0.tar.gz
rm -f guacamole-server-1.4.0.tar.gz
mv -v ${GUAC_SERVER} server

# JDBC Download
wget "${GUAC_URL}binary/${GUAC_JDBC}.tar.gz" -O ${GUAC_JDBC}.tar.gz
tar xzvf ${GUAC_JDBC}.tar.gz
rm -f ${GUAC_JDBC}.tar.gz
mv -v ${GUAC_JDBC}/mysql/guacamole-auth-jdbc-mysql-1.4.0.jar ${LIB_DIR}extensions/

# MySQL Connector Download
wget "https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-8.0.29-1.el8.noarch.rpm"
rpm2cpio mysql-connector-java-8.0.29-1.el8.noarch.rpm | cpio -idmv
mv usr/share/java/mysql-connector-java.jar ${LIB_DIR}lib/
rm -f mysql-connector-java-8.0.29-1.el8.noarch.rpm
rm -fr usr/

# Install
cd server
./configure --with-systemd-dir=/etc/systemd/system
make
make install
ldconfig
systemctl enable guacd
systemctl start guacd


# Guacamole Client Install
wget "${GUAC_URL}binary/${GUAC_CLIENT}.war" -O ${INSTALL_DIR}client/guacamole.war


# Guacamole Configuration File
cat << EOF > /etc/guacamole/${GUAC_CONF}
guacd-hostname: localhost
guacd-port: ${GUAC_PORT}
# MySQL properties
mysql-hostname: localhost
mysql-port: ${MYSQL_PORT}
mysql-database: ${DB_NAME}
mysql-username: ${DB_USER}
mysql-password: ${DB_PASSWD}
mysql-default-max-connections-per-user: 0
mysql-default-max-group-connections-per-user: 0
EOF


# Create Sym links
ln -vfs ${INSTALL_DIR}client/guacamole.war /usr/local/tomcat9/webapps/
# ln -vfs /etc/guacamole/${GUAC_CONF} /usr/share/tomcat/.guacamole/
# ln -vfs ${LIB_DIR}lib/ /usr/share/tomcat/.guacamole/
# ln -vfs ${LIB_DIR}extensions/ /usr/share/tomcat/.guacamole/
# ln -vfs /usr/local/lib/freerdp/guac* /usr/lib64/freerdp


# Setup guacd user, group and permissions
groupadd ${GUACD_USER}
useradd -r ${GUACD_USER} -m -s "/bin/nologin" -g ${GUACD_USER} -c ${GUACD_USER}
sed -i "s/User=daemon/User=${GUACD_USER}/g" /etc/systemd/system/guacd.service


# DB Setup
systemctl enable mariadb.service
systemctl restart mariadb.service
mysqladmin -u root password ${MYSQL_PASSWD}
mysql_secure_installation <<EOF
${MYSQL_PASSWD}
n
y
y
y
y
EOF
mysql -u root -p${MYSQL_PASSWD} -e "CREATE DATABASE ${DB_NAME};"
mysql -u root -p${MYSQL_PASSWD} -e "GRANT SELECT,INSERT,UPDATE,DELETE ON ${DB_NAME}.* TO '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWD}';"
mysql -u root -p${MYSQL_PASSWD} -e "FLUSH PRIVILEGES;"
cat ${INSTALL_DIR}/${GUAC_JDBC}/mysql/schema/*.sql | mysql -u root -p${MYSQL_PASSWD} -D ${DB_NAME}


# Firewall Setup
cp /etc/firewalld/zones/public.xml ~/fwbackup
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --permanent --zone=public --add-service=https
firewall-cmd --permanent --zone=public --add-port=8080/tcp
# firewall-cmd --permanent --zone=public --add-port=8443/tcp
firewall-cmd --reload


#SELinux Settings
# Set Booleans
# setsebool -P httpd_can_network_connect 1
# setsebool -P httpd_can_network_relay 1
#  -P tomcat_can_network_connect_db 1

# Guacamole Client Context
# semanage fcontext -a -t tomcat_exec_t "${LIB_DIR}guacamole.war"
# restorecon -v "${LIB_DIR}guacamole.war"
