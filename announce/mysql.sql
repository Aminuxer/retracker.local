SET NAMES utf8;
SET time_zone = '+00:00';
SET foreign_key_checks = 0;
SET sql_mode = 'NO_AUTO_VALUE_ON_ZERO';

CREATE TABLE `tracker` (
  `info_hash` binary(20) NOT NULL,
  `ip` varchar(128) NOT NULL,
  `port` smallint(5) unsigned NOT NULL DEFAULT 0,
  `update_time` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`info_hash`,`ip`,`port`) USING BTREE
) ENGINE=MEMORY DEFAULT CHARSET=cp1251 COLLATE=cp1251_bin;
