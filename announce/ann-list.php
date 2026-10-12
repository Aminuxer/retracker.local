<?php

require("config.php");

$conn = mysqli_connect($tr_cfg['tr_db']['mysql']['dbhost'], $tr_cfg['tr_db']['mysql']['dbuser'], $tr_cfg['tr_db']['mysql']['dbpasswd']);
mysqli_select_db($conn, $tr_cfg['tr_db']['mysql']['dbname']);

  $a0 = mysqli_query($conn, "SELECT COUNT(DISTINCT(ip)) AS uniq_ip_count,
        FROM_UNIXTIME(MAX(update_time)) AS max_date, FROM_UNIXTIME(MIN(update_time)) AS min_date,
        COUNT(DISTINCT(info_hash)) AS uniq_hash_count
     FROM `tracker`") or print mysqli_error($conn);
  $r0 = mysqli_fetch_array($a0);

  $a = mysqli_query($conn, "SELECT ip, FROM_UNIXTIME(MAX(update_time)) AS last_act, COUNT(info_hash) AS cnt_hash,
        CONCAT('...', (SUBSTRING(ip,8)) ) AS ok_ip
     FROM `tracker`
     GROUP BY ip
     -- HAVING cnt_hash > 32
     ORDER BY cnt_hash DESC
     LIMIT 20 ") or print mysqli_error($conn);
 $id = 0;

 print '<!DOCTYPE html>
<html>
<head>
      <title>retracker.local top</title>
      <link href="/favicon.ico" rel="shortcut icon" type="image/x-icon" />
      <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
      <meta name="robots" content="noindex,follow" />
      <style>body { background-color: silver; color: blue; }
       .ph { color: green; }
       .st { color: magenta; }</style>
</head>

<body>
      <h2>retracker.local top</h2>
      <pre>make torrents great again!</pre>';

print '<pre class="st"><B>'.$r0['uniq_hash_count'].'</B> torrents from <B>'.$r0['uniq_ip_count'].'</B> seeders.<Br/>'
.$r0['min_date'].'<Br/>'.$r0['max_date'].'</pre>';

print '       <pre><font color="green">
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
