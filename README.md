# retracker.local
Provider-side torrent traffic optimizer - retracker.local in one lightweight PHP script.
Only web-server with PHP and MySQL needed.


## Installation
Create new database from dump `announce/mysql.sql` and mysql user with select / insert / delete permissions to created DB.
Place web-scripts and mainly `announce` directory to root directory of your `retracker.local` virtual host.
Edit `config.php` anf setup correctr DB-user and DB-password data.

## Manage
Watch table `tracker` for new peers and hashes.
Table with peers placed in memory - this nice for performance and privacy.
In high-load environment watch for memory usage by mysqld and allocate enought volume of memory to retracker.local host.

In difficult cases enable debug log in config

## Configs and command example.

### Nginx

```
server {
        listen 80;
        listen [::]:80;

        server_name retracker.local;
        root /var/www/html_retracker;

        access_log /dev/null;
        error_log  /tmp/retracker-error.log;
        index index.html index.htm index.php;

        location = / {
                try_files $uri $uri/ =404;
        }

        location ~ \.php$ {
                include snippets/fastcgi-php.conf;
                fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        }

        location = /announce/ann-list.php {
                include snippets/fastcgi-php.conf;
                fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
                allow 127.0.0.1/32;
                deny all;
        }

        location = /ann {
           rewrite ^/ http://retracker.local/announce/ permanent;
        }

}
```

### MySQL
```
CREATE DATABASE retracker;
CREATE USER 'retracker'@'localhost' IDENTIFIED BY 'my-database-password';
GRANT SELECT,INSERT,UPDATE,DELETE ON retracker.* TO 'retracker'@'localhost';

# mysql -uroot -p -D retracker < ./announce/mysql.sql
```
