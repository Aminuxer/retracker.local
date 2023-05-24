<?php

require("config.php");

$conn = mysqli_connect($tr_cfg['tr_db']['mysql']['dbhost'],
                       $tr_cfg['tr_db']['mysql']['dbuser'],
                       $tr_cfg['tr_db']['mysql']['dbpasswd'],
                       $tr_cfg['tr_db']['mysql']['dbname']);

  $a = mysqli_query($conn, "SELECT ip, FROM_UNIXTIME(MAX(update_time)) AS last_act, COUNT(info_hash) AS cnt_hash,
        CONCAT_WS(\".\", CONV(SUBSTRING(ip,1,2), 16, 10), CONV(SUBSTRING(ip,3,2), 16, 10), CONV(SUBSTRING(ip,5,2), 16, 10), CONV(SUBSTRING(ip,7,2), 16, 10) ) AS ok_ip
     FROM `tracker`
     GROUP BY ip
     -- HAVING cnt_hash > 32
     ORDER BY cnt_hash DESC
     LIMIT 20 ") or print mysqli_error($conn);;
 $id = 0;

 print '<!DOCTYPE html>
<html>
<head>
      <title>retracker.local</title>
      <link href="favicon.ico" rel="shortcut icon" type="image/x-icon" />
      <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
      <meta name="robots" content="noindex,follow" />
      <style>body { background-color: silver; color: blue; }</style>
</head>

<body>
      <h2>retracker.local</h2>
      <pre>make torrents great again!</pre>

       <h3>ReTracker.Local Top</h3>
       <pre><font color="green">
#      IP                  last-activity            Hashes</font>'."\n";
  while ($r = mysqli_fetch_array($a)) {
    $id++;
    print str_pad($id, 7).str_pad(htmlspecialchars($r['ok_ip']), 20).str_pad($r['last_act'], 25).$r['cnt_hash'].' '."\n";
  };



  $b = mysqli_query($conn, "SELECT HEX(info_hash) as hex, COUNT(*) as cnt
     FROM `tracker`
     GROUP BY info_hash
     -- HAVING cnt > 9
     ORDER BY cnt DESC
     LIMIT 12 ") or print mysqli_error($conn);;
 $id = 0;

 print '</pre>

<pre><font color="green">
#      HEX(Hash)                                    Seeders</font>'."\n";
  while ($r = mysqli_fetch_array($b)) {
    $id++;
    print str_pad($id, 7).htmlspecialchars($r['hex']).'     '.$r['cnt'].' '."\n";
  };

print '</pre></body></html>';

?>
