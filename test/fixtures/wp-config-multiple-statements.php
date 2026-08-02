<?php
define('DB_NAME', 'shop;primary' . '_db'); $table_prefix = "store_"; define('DISABLE_WP_CRON', true); // trailing comment
define('MULTISITE', getenv('WORDPRESS_MULTISITE') ?: false); define('WP_CACHE', false); /* define('DB_NAME', 'commented'); */
const DB_NAME = resolve_database_name(); $table_prefix = 'dynamic_' . prefix_suffix(); define('DISABLE_WP_CRON', false);
define(
    "DB_NAME",
    "multi" . "_line"
); $table_prefix = 'multi_line_'; # ignore define('WP_CACHE', true);
define('DB_PASSWORD', 'fixture-secret-must-never-appear'); define('WP_CACHE', "cache_$dynamic");
