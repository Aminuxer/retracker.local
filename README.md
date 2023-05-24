# retracker.local
Provider-side torrent traffic optimizer - retracker.local in one lightweight PHP script.
Only web-server with PHP and MySQL needed.


## Installation
Create new database from dump `mysql.sql` and mysql user with select / insert / delete permissions to created DB.
Place web-scripts and mainly `announce` directory to root directory of your `retracker.local` virtual host.
Edit `config.php` anf setup correctr DB-user and DB-password data.

## Manage
Watch table `tracker` for new peers and hashes.
Table with peers placed in memory - this nice for performance and privacy.
In high-load environment watch for memory usage by mysqld and allocate enought volume of memory to retracker.local host.

In difficult cases enable debug log in config

