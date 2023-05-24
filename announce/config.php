<?php

error_reporting(E_ALL);                            // Set php error reporting mode
# set_magic_quotes_runtime(0);                       // Disable magic_quotes_runtime

// Tracker config
$tr_cfg = array();

// Garbage collector (run this script in cron each 5 minutes with '?run_gc=1' e.g. http://yoursite.com/announce.php?run_gc=1)
$tr_cfg['run_gc_key'] = 'run_gc';

$tr_cfg['announce_interval']  = 1800;              // sec, min = 60
$tr_cfg['peer_expire_factor'] = 25;               // min = 2; Consider a peer dead if it has not announced in a number of seconds equal to this many times the calculated announce interval at the time of its last announcement
$tr_cfg['numwant']            = 50;                // number of peers being sent to client
$tr_cfg['ignore_reported_ip'] = false;              // Ignore IP reported by client
$tr_cfg['verify_reported_ip'] = false;             // Verify IP reported by client against $_SERVER['HTTP_X_FORWARDED_FOR']
$tr_cfg['allow_internal_ip']  = true;              // Allow internal IP (10.xx.. etc.)

$tr_cfg['debug']  = 0;                                 // 0 - OFF, 1 - only exceptions, 2 - more and more
$tr_cfg['debug_file']  = '/tmp/retracker_debug.txt';   // Debug log file


// DB - MySQL
$tr_cfg['tr_db']['mysql'] = array(
	'dbhost'   => '127.0.0.1',
	'dbuser'   => 'retracker',
	'dbpasswd' => 'my-database-password',
	'dbname'   => 'retracker',
	'pconnect' => false,
	'log_name' => 'MySQL',
);

define('PEERS_LIST_PREFIX', '');
define('PEERS_LIST_EXPIRE', round(0.7 * $tr_cfg['announce_interval']));  // sec

?>
