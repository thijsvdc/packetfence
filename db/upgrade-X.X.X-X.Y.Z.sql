--
-- PacketFence SQL schema upgrade from X.X.X to X.Y.Z
--


--
-- Setting the major/minor/sub-minor version of the DB
--

SET @MAJOR_VERSION = 9;
SET @MINOR_VERSION = 3;
SET @SUBMINOR_VERSION = 9;



SET @PREV_MAJOR_VERSION = 9;
SET @PREV_MINOR_VERSION = 3;
SET @PREV_SUBMINOR_VERSION = 0;


--
-- The VERSION_INT to ensure proper ordering of the version in queries
--

SET @VERSION_INT = @MAJOR_VERSION << 16 | @MINOR_VERSION << 8 | @SUBMINOR_VERSION;

SET @PREV_VERSION_INT = @PREV_MAJOR_VERSION << 16 | @PREV_MINOR_VERSION << 8 | @PREV_SUBMINOR_VERSION;

DROP PROCEDURE IF EXISTS ValidateVersion;


--
-- Create the pki table cas
--

\! echo "Creating table 'pki_cas'...";
CREATE TABLE IF NOT EXISTS `pki_cas` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  `cn` varchar(255) DEFAULT NULL,
  `mail` varchar(255) DEFAULT NULL,
  `organisation` varchar(255) DEFAULT NULL,
  `country` varchar(255) DEFAULT NULL,
  `state` varchar(255) DEFAULT NULL,
  `locality` varchar(255) DEFAULT NULL,
  `street_address` varchar(255) DEFAULT NULL,
  `postal_code` varchar(255) DEFAULT NULL,
  `key_type` int(11) DEFAULT NULL,
  `key_size` int(11) DEFAULT NULL,
  `digest` int(11) DEFAULT NULL,
  `key_usage` varchar(255) DEFAULT NULL,
  `extended_key_usage` varchar(255) DEFAULT NULL,
  `days` int(11) DEFAULT NULL,
  `key` longtext,
  `cert` longtext,
  `issuer_key_hash` varchar(255) DEFAULT NULL,
  `issuer_name_hash` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `cn` (`cn`),
  UNIQUE KEY `uix_cas_issuer_key_hash` (`issuer_key_hash`),
  UNIQUE KEY `uix_cas_issuer_name_hash` (`issuer_name_hash`),
  KEY `mail` (`mail`),
  KEY `organisation` (`organisation`),
  KEY `idx_cas_deleted_at` (`deleted_at`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=latin1;

--
-- Create the pki table certs
--

\! echo "Creating table 'pki_certs'...";
CREATE TABLE IF NOT EXISTS `pki_certs` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  `cn` varchar(255) DEFAULT NULL,
  `mail` varchar(255) DEFAULT NULL,
  `ca_id` int(10) unsigned DEFAULT NULL,
  `ca_name` varchar(255) DEFAULT NULL,
  `street_address` varchar(255) DEFAULT NULL,
  `organisation` varchar(255) DEFAULT NULL,
  `country` varchar(255) DEFAULT NULL,
  `state` varchar(255) DEFAULT NULL,
  `locality` varchar(255) DEFAULT NULL,
  `postal_code` varchar(255) DEFAULT NULL,
  `key` longtext,
  `cert` longtext,
  `profile_id` int(10) unsigned DEFAULT NULL,
  `profile_name` varchar(255) DEFAULT NULL,
  `valid_until` timestamp NULL DEFAULT NULL,
  `date` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `serial_number` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `cn` (`cn`),
  KEY `profile_name` (`profile_name`),
  KEY `valid_until` (`valid_until`),
  KEY `idx_certs_deleted_at` (`deleted_at`),
  KEY `mail` (`mail`),
  KEY `ca_id` (`ca_id`),
  KEY `ca_name` (`ca_name`),
  KEY `organisation` (`organisation`),
  KEY `profile_id` (`profile_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=latin1;

--
-- Create the pki table profiles
--

\! echo "Creating table 'pki_profiles'...";
CREATE TABLE IF NOT EXISTS `pki_profiles` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  `name` varchar(255) DEFAULT NULL,
  `ca_id` int(10) unsigned DEFAULT NULL,
  `ca_name` varchar(255) DEFAULT NULL,
  `validity` int(11) DEFAULT NULL,
  `key_type` int(11) DEFAULT NULL,
  `key_size` int(11) DEFAULT NULL,
  `digest` int(11) DEFAULT NULL,
  `key_usage` varchar(255) DEFAULT NULL,
  `extended_key_usage` varchar(255) DEFAULT NULL,
  `p12_mail_password` int(11) DEFAULT NULL,
  `p12_mail_subject` varchar(255) DEFAULT NULL,
  `p12_mail_from` varchar(255) DEFAULT NULL,
  `p12_mail_header` varchar(255) DEFAULT NULL,
  `p12_mail_footer` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`),
  KEY `idx_profiles_deleted_at` (`deleted_at`),
  KEY `ca_id` (`ca_id`),
  KEY `ca_name` (`ca_name`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=latin1;


--
-- Create the pki table revoked_certs
--

\! echo "Creating table 'pki_revoked_certs'...";
CREATE TABLE IF NOT EXISTS `pki_revoked_certs` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  `cn` varchar(255) DEFAULT NULL,
  `mail` varchar(255) DEFAULT NULL,
  `ca_id` int(10) unsigned DEFAULT NULL,
  `ca_name` varchar(255) DEFAULT NULL,
  `street_address` varchar(255) DEFAULT NULL,
  `organisation` varchar(255) DEFAULT NULL,
  `country` varchar(255) DEFAULT NULL,
  `state` varchar(255) DEFAULT NULL,
  `locality` varchar(255) DEFAULT NULL,
  `postal_code` varchar(255) DEFAULT NULL,
  `key` longtext,
  `cert` longtext,
  `profile_id` int(10) unsigned DEFAULT NULL,
  `profile_name` varchar(255) DEFAULT NULL,
  `valid_until` timestamp NULL DEFAULT NULL,
  `date` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `serial_number` varchar(255) DEFAULT NULL,
  `revoked` timestamp NULL DEFAULT NULL,
  `crl_reason` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `valid_until` (`valid_until`),
  KEY `crl_reason` (`crl_reason`),
  KEY `idx_revoked_certs_deleted_at` (`deleted_at`),
  KEY `cn` (`cn`),
  KEY `mail` (`mail`),
  KEY `ca_id` (`ca_id`),
  KEY `profile_id` (`profile_id`),
  KEY `profile_name` (`profile_name`),
  KEY `ca_name` (`ca_name`),
  KEY `organisation` (`organisation`),
  KEY `revoked` (`revoked`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Updating to current version
--
DELIMITER //
CREATE PROCEDURE ValidateVersion()
BEGIN
    DECLARE PREVIOUS_VERSION int(11);
    DECLARE PREVIOUS_VERSION_STRING varchar(11);
    DECLARE _message varchar(255);
    SELECT id, version INTO PREVIOUS_VERSION, PREVIOUS_VERSION_STRING FROM pf_version ORDER BY id DESC LIMIT 1;

      IF PREVIOUS_VERSION != @PREV_VERSION_INT THEN
        SELECT CONCAT('PREVIOUS VERSION ', PREVIOUS_VERSION_STRING, ' DOES NOT MATCH ', CONCAT_WS('.', @PREV_MAJOR_VERSION, @PREV_MINOR_VERSION, @PREV_SUBMINOR_VERSION)) INTO _message;
        SIGNAL SQLSTATE VALUE '99999'
              SET MESSAGE_TEXT = _message;
      END IF;
END
//

DELIMITER ;
\! echo "Checking PacketFence schema version...";
call ValidateVersion;
DROP PROCEDURE IF EXISTS ValidateVersion;

--
-- Table structure for table `dhcppool`
--
\! echo "Creating table 'dhcppool'...";
CREATE TABLE IF NOT EXISTS dhcppool (
  id                    int(11) unsigned NOT NULL auto_increment,
  pool_name             varchar(30) NOT NULL,
  idx                   int(11) NOT NULL,
  mac                   VARCHAR(30) NOT NULL,
  free                  BOOLEAN NOT NULL default '1',
  released              DATETIME(6) NULL default NULL,
  PRIMARY KEY (id),
  UNIQUE KEY dhcppool_poolname_idx (pool_name, idx),
  KEY mac (mac),
  KEY released (released)
) ENGINE=INNODB;

\! echo "Adding new table bandwidth_accounting";
CREATE TABLE IF NOT EXISTS bandwidth_accounting (
    node_id BIGINT UNSIGNED NOT NULL,
    unique_session_id BIGINT UNSIGNED NOT NULL,
    time_bucket DATETIME NOT NULL,
    in_bytes BIGINT SIGNED NOT NULL,
    out_bytes BIGINT SIGNED NOT NULL,
    mac CHAR(17) NOT NULL,
    tenant_id SMALLINT NOT NULL,
    processed BOOLEAN NOT NULL DEFAULT 0,
    last_updated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total_bytes BIGINT SIGNED AS (in_bytes + out_bytes) VIRTUAL,
    PRIMARY KEY (node_id, time_bucket, unique_session_id),
    KEY bandwidth_aggregate_buckets (time_bucket, node_id, unique_session_id, in_bytes, out_bytes),
    KEY bandwidth_accounting_tenant_id_mac (tenant_id, mac)
);

\! echo "Alter table radius_nas";
ALTER TABLE radius_nas
  ADD COLUMN IF NOT EXISTS unique_session_attributes varchar(255),
  ADD INDEX IF NOT EXISTS radius_nas_start_ip_end_ip (start_ip, end_ip);

--
-- Table structure for table `bandwidth_accounting_history`
--

CREATE TABLE IF NOT EXISTS bandwidth_accounting_history (
    node_id BIGINT UNSIGNED NOT NULL,
    time_bucket DATETIME NOT NULL,
    in_bytes BIGINT SIGNED NOT NULL,
    out_bytes BIGINT SIGNED NOT NULL,
    total_bytes BIGINT SIGNED AS (in_bytes + out_bytes) VIRTUAL,
    mac CHAR(17) NOT NULL,
    tenant_id SMALLINT NOT NULL,
    PRIMARY KEY (node_id, time_bucket),
    KEY bandwidth_aggregate_buckets (time_bucket, node_id, in_bytes, out_bytes),
    KEY bandwidth_accounting_tenant_id_mac (tenant_id, mac)
);

DROP PROCEDURE IF EXISTS `bandwidth_aggregation`;
DELIMITER /
CREATE PROCEDURE `bandwidth_aggregation` (
  IN `p_end_bucket` datetime,
  IN `p_batch` int(11) unsigned
)
BEGIN

    DROP TABLE IF EXISTS to_delete;
    SET @end_bucket= p_end_bucket, @batch = p_batch;
    SET @create_table_to_delete_stmt = CONCAT('CREATE TEMPORARY TABLE to_delete ENGINE=MEMORY, MAX_ROWS=', @batch, ' SELECT node_id, time_bucket as new_time_bucket, time_bucket, unique_session_id, in_bytes, out_bytes FROM bandwidth_accounting LIMIT 0');
    PREPARE create_table_to_delete FROM @create_table_to_delete_stmt;
    EXECUTE create_table_to_delete;
    DEALLOCATE PREPARE create_table_to_delete;
    PREPARE insert_into_to_delete FROM  'INSERT INTO to_delete SELECT node_id, DATE_ADD(DATE(time_bucket), INTERVAL HOUR(time_bucket) HOUR) as new_time_bucket, time_bucket, unique_session_id, in_bytes, out_bytes FROM bandwidth_accounting WHERE time_bucket <= ? AND processed = 1 LIMIT ?';

    START TRANSACTION;
    EXECUTE insert_into_to_delete using @end_bucket, @batch;
    SELECT COUNT(*) INTO @count FROM to_delete;
    IF @count > 0 THEN

        INSERT INTO bandwidth_accounting_history
        (node_id, time_bucket, in_bytes, out_bytes)
         SELECT
             node_id,
             new_time_bucket,
             sum(in_bytes) AS in_bytes,
             sum(out_bytes) AS out_bytes
            FROM to_delete
            GROUP BY node_id, new_time_bucket
            ON DUPLICATE KEY UPDATE
                in_bytes = in_bytes + VALUES(in_bytes),
                out_bytes = out_bytes + VALUES(out_bytes)
            ;

        DELETE bandwidth_accounting
            FROM to_delete INNER JOIN bandwidth_accounting
            WHERE
                to_delete.node_id = bandwidth_accounting.node_id AND
                to_delete.time_bucket = bandwidth_accounting.time_bucket AND
                to_delete.unique_session_id = bandwidth_accounting.unique_session_id;
    END IF;
    COMMIT;

    DROP TABLE to_delete;
    DEALLOCATE PREPARE insert_into_to_delete;
    SELECT @count AS aggreated;
END /
DELIMITER ;

DROP PROCEDURE IF EXISTS `bandwidth_aggregation`;
DELIMITER /
CREATE PROCEDURE `bandwidth_aggregation` (
  IN `p_end_bucket` datetime,
  IN `p_batch` int(11) unsigned
)
BEGIN

    DROP TABLE IF EXISTS to_delete;
    SET @end_bucket= p_end_bucket, @batch = p_batch;
    SET @create_table_to_delete_stmt = CONCAT('CREATE TEMPORARY TABLE to_delete ENGINE=MEMORY, MAX_ROWS=', @batch, ' SELECT node_id, tenant_id, mac, time_bucket as new_time_bucket, time_bucket, unique_session_id, in_bytes, out_bytes FROM bandwidth_accounting LIMIT 0');
    PREPARE create_table_to_delete FROM @create_table_to_delete_stmt;
    EXECUTE create_table_to_delete;
    DEALLOCATE PREPARE create_table_to_delete;
    PREPARE insert_into_to_delete FROM  'INSERT INTO to_delete SELECT node_id, tenant_id, mac, DATE_ADD(DATE(time_bucket), INTERVAL HOUR(time_bucket) HOUR) as new_time_bucket, time_bucket, unique_session_id, in_bytes, out_bytes FROM bandwidth_accounting WHERE time_bucket <= ? AND processed = 1 LIMIT ?';

    START TRANSACTION;
    EXECUTE insert_into_to_delete using @end_bucket, @batch;
    SELECT COUNT(*) INTO @count FROM to_delete;
    IF @count > 0 THEN

        INSERT INTO bandwidth_accounting_history
        (node_id, tenant_id, mac, time_bucket, in_bytes, out_bytes)
         SELECT
             node_id,
             tenant_id,
             mac,
             new_time_bucket,
             sum(in_bytes) AS in_bytes,
             sum(out_bytes) AS out_bytes
            FROM to_delete
            GROUP BY node_id, new_time_bucket
            ON DUPLICATE KEY UPDATE
                in_bytes = in_bytes + VALUES(in_bytes),
                out_bytes = out_bytes + VALUES(out_bytes)
            ;

        DELETE bandwidth_accounting
            FROM to_delete INNER JOIN bandwidth_accounting
            WHERE
                to_delete.node_id = bandwidth_accounting.node_id AND
                to_delete.time_bucket = bandwidth_accounting.time_bucket AND
                to_delete.unique_session_id = bandwidth_accounting.unique_session_id;
    END IF;
    COMMIT;

    DROP TABLE to_delete;
    DEALLOCATE PREPARE insert_into_to_delete;
    SELECT @count AS aggreated;
END /
DELIMITER ;

DROP PROCEDURE IF EXISTS `process_bandwidth_accounting`;
DELIMITER /
CREATE PROCEDURE `process_bandwidth_accounting` (
  IN `p_batch` int(11) unsigned
)
BEGIN
    SET @batch = p_batch;
    DROP TABLE IF EXISTS to_process;
    CREATE TEMPORARY TABLE to_process ENGINE=MEMORY SELECT node_id, tenant_id, mac, time_bucket, unique_session_id, total_bytes FROM bandwidth_accounting LIMIT 0;
    START TRANSACTION;
    PREPARE insert_into_to_process FROM 'INSERT to_process SELECT node_id, tenant_id, mac, time_bucket, unique_session_id, total_bytes FROM bandwidth_accounting WHERE processed = 0 LIMIT ?';
    EXECUTE insert_into_to_process USING @batch;
    DEALLOCATE PREPARE insert_into_to_process;
    SELECT COUNT(*) INTO @count FROM to_process;
    IF @count > 0 THEN
        UPDATE 
            (SELECT tenant_id, mac, SUM(total_bytes) AS total_bytes FROM to_process GROUP BY node_id) AS x 
            LEFT JOIN node USING(tenant_id, mac)
            SET node.bandwidth_balance = GREATEST(node.bandwidth_balance - total_bytes, 0)
            WHERE node.bandwidth_balance IS NOT NULL;

        UPDATE to_process LEFT JOIN bandwidth_accounting USING(node_id, time_bucket, unique_session_id)
        SET processed = 1;

        COMMIT;
    END IF;

    DROP TABLE to_process;
    SELECT @count as count;
END/

DELIMITER ;

DROP PROCEDURE IF EXISTS `bandwidth_aggregation_history`;
DELIMITER /
CREATE PROCEDURE `bandwidth_aggregation_history` (
  IN `p_bucket_size` varchar(255),
  IN `p_end_bucket` datetime,
  IN `p_batch` int(11) unsigned
)
BEGIN

    DROP TABLE IF EXISTS to_delete;
    SET @end_bucket= p_end_bucket, @batch = p_batch;
    SET @create_table_to_delete_stmt = CONCAT('CREATE TEMPORARY TABLE to_delete ENGINE=MEMORY, MAX_ROWS=', @batch, ' SELECT node_id, tenant_id, mac, time_bucket as new_time_bucket, time_bucket, in_bytes, out_bytes FROM bandwidth_accounting_history LIMIT 0');
    PREPARE create_table_to_delete FROM @create_table_to_delete_stmt;
    EXECUTE create_table_to_delete;
    DEALLOCATE PREPARE create_table_to_delete;
    IF p_bucket_size = 'monthly' THEN
        PREPARE insert_into_to_delete FROM 'INSERT INTO to_delete SELECT node_id, tenant_id, mac, date_add(DATE(time_bucket),interval -DAY(time_bucket)+1 DAY ) as new_time_bucket, time_bucket, in_bytes, out_bytes FROM bandwidth_accounting_history WHERE time_bucket <= ? AND time_bucket != date_add(DATE(time_bucket),interval -DAY(time_bucket)+1 DAY ) LIMIT ?';
    ELSE
        PREPARE insert_into_to_delete FROM 'INSERT INTO to_delete SELECT node_id, tenant_id, mac, DATE(time_bucket) as new_time_bucket, time_bucket, in_bytes, out_bytes FROM bandwidth_accounting_history WHERE time_bucket <= ? AND time_bucket != DATE(time_bucket) LIMIT ?';
    END IF;

    START TRANSACTION;
    EXECUTE insert_into_to_delete using @end_bucket, @batch;
    SELECT COUNT(*) INTO @count FROM to_delete;
    IF @count > 0 THEN
        INSERT INTO bandwidth_accounting_history
        (node_id, tenant_id, mac, time_bucket, in_bytes, out_bytes)
         SELECT
             node_id,
             tenant_id,
             mac,
             new_time_bucket,
             sum(in_bytes) AS in_bytes,
             sum(out_bytes) AS out_bytes
            FROM to_delete
            GROUP BY node_id, new_time_bucket
            ON DUPLICATE KEY UPDATE
                in_bytes = in_bytes + VALUES(in_bytes),
                out_bytes = out_bytes + VALUES(out_bytes)
            ;

        DELETE bandwidth_accounting_history
            FROM to_delete INNER JOIN bandwidth_accounting_history
            WHERE
                to_delete.node_id = bandwidth_accounting_history.node_id AND
                to_delete.time_bucket = bandwidth_accounting_history.time_bucket;
        COMMIT;
    END IF;

    DROP TABLE to_delete;
    DEALLOCATE PREPARE insert_into_to_delete;
    SELECT @count AS aggreated;
END /
DELIMITER ;

\! echo "Incrementing PacketFence schema version...";
INSERT IGNORE INTO pf_version (id, version) VALUES (@VERSION_INT, CONCAT_WS('.', @MAJOR_VERSION, @MINOR_VERSION, @SUBMINOR_VERSION));

\! echo "Upgrade completed successfully.";

