#!/bin/bash

##!/usr/bin/env bash

# OS: Ubuntu 18.04 & 20.04
# Example of call: ./wordpress-setup.sh setup   example.com.config.sh
# Example of call: ./wordpress-setup.sh restore example.com.config.sh /root/wpbackup/example.com-20210417211417/ example.com.restore.config.sh

set -e

### Determine script root:
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"


### Read common procedure file:
source $SCRIPT_DIR/common.sh


### Check command:
command=$1
check_defined command && exit 1

if ! [[ "$command" =~ ^(restore|setup)$ ]]; then
  echo "Error: Invalid command: $command."
  echo "Allowed values for command: setup, restore"
  exit 1
fi


### Read main config file:
config_file=$2
check_defined config_file && exit 1
source $config_file 
success "Read config file $config_file"


### Buffer variables:
sitename_orig=$sitename;


### Read restore info (if needed):
if [ $command == 'restore' ] ; then

  backup_files_dir=$3
  restoredir=$backup_files_dir # Backward compatibility
  
  check_defined backup_files_dir && exit 1
  
  if [ ! -d $backup_files_dir ]; then
    failure "Directory with backup files not found"
    exit 1
  fi

  restore_file=$4
  check_defined restore_file && exit 1
  source $restore_file 
  success "Read config file $restore_file"

  sitename=$restore_name;

fi


### Basic checks:
check_defined sitename && exit 1
check_defined var_www && exit 1
check_defined includewwwprefix && exit 1
check_defined createuser && exit 1
check_defined username && exit 1
check_defined userpass && exit 1
check_defined userpubkey && exit 1
check_defined creategroup && exit 1
check_defined groupname && exit 1
check_defined sethostname && exit 1
check_defined osupgrade && exit 1
check_defined osversion && exit 1
check_defined restoredir && exit 1
check_defined sitename_orig && exit 1
check_defined db_name && exit 1
check_defined db_user && exit 1
check_defined db_pass && exit 1
check_defined httpauthuser && exit 1
check_defined httpauthpass && exit 1

check_defined htpasswd_file && export htpasswd_file="/etc/.htpasswd-$sitename"



### Determine site directory root:
sitedir=$var_www/$sitename
check_defined sitedir && exit 1


### Check if www prefix is needed:
if [ $includewwwprefix == 'yes' ] ; then
  servername_directive="server_name ${sitename} www.${sitename}"
else
  servername_directive="server_name ${sitename}"
fi


### Check if user needs to be created:
if [ $createuser == 'yes' ] ; then
  useradd -m -s /bin/bash ${username}
  success "Created Linux user $username"
  echo -e "$userpass\n$userpass" | passwd $username
  success "Password set for $username"

  ### Put user's public key:
  check_defined userpubkey && exit 1
  mkdir -p /home/${username}/.ssh
  echo $userpubkey >> /home/${username}/.ssh/authorized_keys
  chmod 700 /home/${username}/.ssh/
  chmod 600 /home/${username}/.ssh/authorized_keys
  chmod 700 /home/${username}/.ssh/
  chown -R ${username}:${username} /home/${username}/.ssh
  success "Public key set for $username"
fi

if [ $creategroup == 'yes' ] ; then
  groupadd ${groupname}
  success "Created Linux group $groupname"
  usermod -a -G ${groupname} ${username}
  success "Added user $username to group $groupname"
fi


if [ $sethostname == 'yes' ] ; then
  hostnamectl set-hostname ${hostname}
fi

if [ $osupgrade == 'yes' ] ; then
  apt-get update && apt-get upgrade -y
fi

if [ $osversion == '20.04' ] ; then
  phpversion='7.4'
else
  # 18.04 as default:
  phpversion='7.2'
fi

apt-get install -y php
sudo apt-get -y remove apache2
#apt-get install -y mysql-server mysql-client nginx php php-mysql php-fpm php${phpversion}-gd php${phpversion}-xml php${phpversion}-curl apache2-utils dos2unix
apt-get install -y mariadb-server mariadb-client nginx php php-mysql php-fpm php${phpversion}-gd php${phpversion}-xml php${phpversion}-curl apache2-utils dos2unix prometheus-node-exporter


### Copy wordpress files:
if [ $command == 'restore' ] ; then
  tar xf $restoredir/wordpress.tgz -C $var_www
  mv $var_www/$sitename_orig $sitedir
else
  mkdir -p ~/Downloads
  cd ~/Downloads
  rm -f latest.tar.gz
  wget https://wordpress.org/latest.tar.gz
  tar xfz latest.tar.gz
  
  mv wordpress ${sitedir}
  
  cd ${sitedir}
  chown -R ${username}:www-data ${sitedir}
  cd wp-content

  chmod -R 775 * .
  chmod -R g+s * .
fi


success "Wordpress files moved to the site directory: $sitedir"


### Database settings:
echo "create database $db_name" | mysql
echo "CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}'" | mysql
echo "GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost'" | mysql
echo "flush privileges" | mysql

if [ $command == 'restore' ] ; then
  echo "Search and Replace check:"
  set +e
  zgrep -v "https://${sitename_orig}" $restoredir/${db_name}.export.sql.gz |grep "${sitename_orig}" |grep -v var
  set -e

  echo "WP CLI install:"
  curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  chmod +x wp-cli.phar
  mv wp-cli.phar /usr/local/bin/wp

  echo "MySql import:"
  zcat $restoredir/${db_name}.export.sql.gz | mysql

  echo "WP search-replace:"
  echo "debug: sitename_orig: ${sitename_orig}"
  echo "debug: restore_name: ${restore_name}"
  #wp search-replace --allow-root --path=${sitedir} "//${sitename_orig}" "//${restore_name}"
  wp search-replace --allow-root --path=${sitedir} "${sitename_orig}" "${restore_name}"

fi
success "Database $db_name set up"


### Basic authentication:
if [ ! -f "$htpasswd_file" ]; then
  touch ${htpasswd_file}
  htpasswd -b -c ${htpasswd_file} $httpauthuser $httpauthpass
  success "Added first htpasswd user: $httpauthuser"
else
  linenums=`cat ${htpasswd_file} | wc -l`
  if [ "$linenums" != "0" ]; then
    linenums2=`grep $httpauthuser ${htpasswd_file} | wc -l`
    if [ "$linenums2" == "0" ]; then
      htpasswd -b ${htpasswd_file} $httpauthuser $httpauthpass
      success "Added htpasswd user: $httpauthuser"
    fi
  else
    htpasswd -b -c ${htpasswd_file} $httpauthuser $httpauthpass
    success "Added first htpasswd user: $httpauthuser"
  fi
fi


### Set up nginx:
cat > /etc/nginx/sites-enabled/${sitename} <<- EOM
server {
    listen 80;
    listen [::]:80;

    ${servername_directive};

    root /var/www/${sitename};
    index index.php;
    auth_basic           "Restricted";
    auth_basic_user_file ${htpasswd_file};

    location / {
        #try_files \$uri \$uri/ =404;

        # Permalinks workaround (https://www.digitalocean.com/community/questions/404-when-using-pretty-permalinks-on-new-wordpress-site-on-lemp-nginx):
        if (!-e \$request_filename) {
            rewrite ^.*$ /index.php last;
        }        
        try_files \$uri \$uri/ index.php\$is_args\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${phpversion}-fpm.sock;
    }

    access_log /var/log/nginx/${sitename}-access.log;
    error_log /var/log/nginx/${sitename}-error.log;

    client_max_body_size 15M;
    
    ### Security section:
    
    # server_tokens off; # Optional but recommended. Can be in http section
    
    # Block xmlrpc use (optional):
    #location ~ xmlrpc.php {
    #    deny all;
    #}

	location ~ /\. {
		return 404;
	}    
    
}
EOM

rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx
success "Nginx configuration set up"

apt install -y snapd
snap install core
snap refresh core
snap install --classic certbot
rm -f /usr/bin/certbot
ln -s /snap/bin/certbot /usr/bin/certbot


### LE CertBot:
if [ "$includewwwprefix" = "yes" ] ; then
  certbot --nginx --non-interactive --agree-tos --redirect -m ${certbot_email} -d ${sitename} -d www.${sitename}
else
  certbot --nginx --non-interactive --agree-tos --redirect -m ${certbot_email} -d ${sitename}
fi
success "Certbot set up"


### Configure Wordpress:
if [ $command == 'restore' ] ; then
  echo "No configuretion needed at restore action"
else
  cd ${sitedir}
  cp wp-config-sample.php wp-config.php
  sed -i "s/database_name_here/${db_name}/" wp-config.php
  sed -i "s/username_here/${db_user}/" wp-config.php
  sed -i "s/password_here/${db_pass}/" wp-config.php
  echo "define( 'FS_METHOD', 'direct' );" >> wp-config.php
  dos2unix wp-config.php
fi

chmod 640 wp-config.php
chown ${username}:www-data wp-config.php
#chmod 775 wp-admin/includes/update-core.php

cd wp-content
mkdir -p upgrade && chown ${username}:www-data upgrade && chmod 775 upgrade
mkdir -p uploads && chown ${username}:www-data uploads && chmod 775 uploads

chmod -R 775 * .
chmod -R g+s * .

echo "; AA Overrides:"              >> /etc/php/${phpversion}/fpm/php.ini
echo "upload_max_filesize = 20M" >> /etc/php/${phpversion}/fpm/php.ini
echo "post_max_size = 20M"       >> /etc/php/${phpversion}/fpm/php.ini
systemctl restart php${phpversion}-fpm.service



success "All done!"
exit 0


###; AA: Posible needed overrides:
###upload_max_filesize = 64M
###post_max_size = 64M
###memory_limit = 100M
###file_uploads = On
###max_execution_time = 300


