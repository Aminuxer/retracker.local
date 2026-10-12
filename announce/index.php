<?php

require('./config.php');

if ( $tr_cfg['debug'] > 0 ) { $fh = fopen($tr_cfg['debug_file'], "a"); };

// ----------------------------------------------------------------------------
// Initialization


// DB
$db = mysqli_connect($tr_cfg['tr_db']['mysql']['dbhost'], $tr_cfg['tr_db']['mysql']['dbuser'], $tr_cfg['tr_db']['mysql']['dbpasswd'], $tr_cfg['tr_db']['mysql']['dbname'])
or print mysqli_error();

function fetch_rowset ($query)
{
        global $db;
	$rowset = array();
	$result = mysqli_query($db, $query) or print mysqli_error($db);
	if (is_resource($result)) {
	   while ($row = mysqli_fetch_array($result, MYSQL_ASSOC)) { $rowset[] = $row; };
	}
	return $rowset;
}


// Garbage collector
if (!empty($_GET[$tr_cfg['run_gc_key']]))
{
        # print 'clear garbage data...';
	$announce_interval = max(intval($tr_cfg['announce_interval']), 60);
	$expire_factor     = max(floatval($tr_cfg['peer_expire_factor']), 2);
	$peer_expire_time  = time() - floor($announce_interval * $expire_factor);

	mysqli_query($db, "DELETE FROM tracker WHERE update_time < $peer_expire_time") or print mysqli_error($db);
	die();
}

// Recover info_hash
if (isset($_GET['?info_hash']) && !isset($_GET['info_hash']))
{
	$_GET['info_hash'] = $_GET['?info_hash'];
}

// Input var names
// String
$input_vars_str = array(
	'info_hash',
	'event',
);
// Numeric
$input_vars_num = array(
	'port',
);

// Init received data
// String
foreach ($input_vars_str as $var_name)
{
	$$var_name = isset($_GET[$var_name]) ? (string) $_GET[$var_name] : null;
}
// Numeric
foreach ($input_vars_num as $var_name)
{
	$$var_name = isset($_GET[$var_name]) ? (float) $_GET[$var_name] : null;
}

// Verify required request params (info_hash, port)
if (!isset($info_hash) || strlen($info_hash) != 20)
{
        if ( $tr_cfg['debug'] > 0 ) {  fwrite($fh, "BAD-INFO-HASH from $ip : IHASH->".bin2hex($info_hash)."</-IHASH. LEN: ".strlen($info_hash)."\n"); }
	msg_die('Invalid info_hash');
}
if (!isset($port) || $port < 0 || $port > 0xFFFF)
{
	msg_die('Invalid port');
}

// IP
$ip = $_SERVER['REMOTE_ADDR'];

if (!$tr_cfg['ignore_reported_ip'] && isset($_GET['ip']) && $ip !== $_GET['ip'])
{
	if (!$tr_cfg['verify_reported_ip'])
	{
		$ip = $_GET['ip'];
	}
	else if (
               isset($_SERVER['HTTP_X_FORWARDED_FOR']) &&
               preg_match_all('#\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}#', $_SERVER['HTTP_X_FORWARDED_FOR'], $matches)
        )
	{
		foreach ($matches[0] as $x_ip)
		{
			if ($x_ip === $_GET['ip'])
			{
				if (!$tr_cfg['allow_internal_ip'] && preg_match("#^(10|172\.16|192\.168)\.#", $x_ip))
				{
					break;
				}
				$ip = $x_ip;
				break;
			}
		}
	}
}
// Check+filter IP format is valid - IPv4 + IPv6
$ip_sql = filter_var($ip, FILTER_VALIDATE_IP) or msg_die("Invalid IP: $ip");


// ----------------------------------------------------------------------------
// Start announcer
//
// $info_hash_sql = rtrim(mysqli_escape_string($db, $info_hash), ' ');
$info_hash_sql = bin2hex($info_hash);
if ( $tr_cfg['debug'] > 2 ) {  fwrite($fh, "DEBUG $ip : IHSQL->$info_hash_sql</-IHSQL   LEN-IHASH-BINARY: ".strlen($info_hash)." LEN-IHSQL-BINARY: ".strlen(hex2bin($info_hash_sql))."\n"); }

// Stopped event
if ($event === 'stopped')
{
        // print 'delete data...';
	mysqli_query($db, "DELETE FROM `tracker` WHERE `info_hash` = UNHEX('$info_hash_sql') AND `ip` = '$ip_sql' AND `port` = '$port'")
        or print mysqli_error($db);
	die();
}

// Update peer info
# print 'update data...';
$sql = "REPLACE INTO tracker (info_hash, ip, port, update_time) VALUES (UNHEX('$info_hash_sql'), '$ip_sql', '$port', UNIX_TIMESTAMP())";

try {
   mysqli_query($db, $sql) or print mysqli_error($db);
} catch (Exception $e) {
              if ( $tr_cfg['debug'] > 2 ) { fwrite($fh, "IP-REPLACE-EXCEPTION: $ip\n   SQL: $sql\n   e-MSG: ".$e->getMessage()."\n"); }
}

if ( $tr_cfg['debug'] > 1 ) { fwrite($fh, "IP: $ip   REPLACE-SQL: $sql\n"); };

// Get cached output
	// Retrieve peers
	$peers  =  $peers6     = '';
	$ann_interval = $tr_cfg['announce_interval'] + mt_rand(0, 600);

        $sql = "SELECT ip, port FROM `tracker` WHERE `info_hash` = UNHEX('$info_hash_sql') AND `ip` != '$ip_sql' ORDER BY RAND() LIMIT ". (int) $tr_cfg['numwant'];
	$result = mysqli_query($db, $sql) or print mysqli_error($db);

        if ( $tr_cfg['debug'] > 2 ) { fwrite($fh, "IP: $ip  IP-SQL: $ip_sql    SQL: $sql\n"); };

        while ($peer = mysqli_fetch_array($result, MYSQLI_ASSOC))
	{
        try {
                $ip = $peer['ip'];
                if ( filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) ) { 
                     $ip4 = ip2long($ip);
                     $peers .= pack('Nn', $ip4, $peer['port']);
                }
                elseif ( filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6) ) {
                         $ip6 = ipv6_to_long($ip);
                         $peers6 .= $ip6.pack('n', $peer['port']);
                };

         } catch (Exception $e) {
              if ( $tr_cfg['debug'] > 0 ) { fwrite($fh, "IP-LOONG: $ip   IP2: $ip2  IP3: $ip3  e-MSG: ".$e->getMessage()."\n"); };
         }
                if ( $tr_cfg['debug'] > 1 ) { fwrite($fh, "IP-LOONG: $ip   IP2: $ip2  IP3: $ip3   PACK: ".bin2hex($peers)."\n"); };
	}


	$output = array(
		'interval'     => (int) $ann_interval,
		'min interval' => (int) $ann_interval,
		'peers'        => $peers,
	);

if ($peers6 !== '') {
    $output['peers6'] = $peers6;
}

// Return data to client
echo bencode($output);

exit;

// ----------------------------------------------------------------------------
// Functions
//
function msg_die ($msg)
{
	$output = bencode(array(
		'min interval'   => (int)    1800,
		'failure reason' => (string) $msg,
	));
	die($output);
}

function ipv6_to_long($ip6_string)
{
    $ip6_string = trim((string)$ip6_string);
    $bin = @inet_pton($ip6_string);
    if ($bin === false || strlen($bin) !== 16) {
        return false;
    }
    return $bin;
}

// bencode: based on OpenTracker [http://whitsoftdev.com/opentracker]
function bencode ($var)
{
	if (is_string($var))
	{
		return strlen($var) .':'. $var;
	}
	else if (is_int($var))
	{
		return 'i'. $var .'e';
	}
	else if (is_float($var))
	{
		return 'i'. sprintf('%.0f', $var) .'e';
	}
	else if (is_array($var))
	{
		if (count($var) == 0)
		{
			return 'de';
		}
		else
		{
			$assoc = false;

			foreach ($var as $key => $val)
			{
				if (!is_int($key))
				{
					$assoc = true;
					break;
				}
			}

			if ($assoc)
			{
				ksort($var, SORT_REGULAR);
				$ret = 'd';

				foreach ($var as $key => $val)
				{
					$ret .= bencode($key) . bencode($val);
				}
				return $ret .'e';
			}
			else
			{
				$ret = 'l';

				foreach ($var as $val)
				{
					$ret .= bencode($val);
				}
				return $ret .'e';
			}
		}
	}
	else
	{
		trigger_error('bencode error: wrong data type', E_USER_ERROR);
	}
}


if ( $tr_cfg['debug'] > 0 ) { fwrite($fh, "\n"); fclose($fn); };

?>
