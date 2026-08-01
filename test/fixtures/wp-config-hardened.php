<?php
/*
define('DB_NAME', 'commented_before');
define('DB_PASSWORD', 'commented-secret-before');
*/
define('DB_NAME', 'shop//primary#blue/*literal*/'); // keep comment markers inside the string
$table_prefix = 'secure_'; # an inline PHP comment
define('DISABLE_WP_CRON', true);
define('MULTISITE', false);
define('WP_CACHE', true);
/* define('DB_NAME', 'commented_after'); */
// define('DB_NAME', 'line_comment');
# define('DB_NAME', 'hash_comment');
define('DB_PASSWORD', 'active-secret-must-never-appear');
