define('DB_NAME', 'fake_outside_php');
<?php
$single_quoted = 'define(\'DB_NAME\', \'fake_single\');';
$double_quoted = "define('DB_NAME', 'fake_double');";
$prefix_decoy = '$table_prefix = "fake_prefix_";';
$const_decoy = "const MULTISITE = true;";
define('UNRELATED_SETTING', "define('WP_CACHE', true);");
define('DB_NAME', 'real_database'); $table_prefix = 'real_'; define('WP_CACHE', false);
?>
define('DB_NAME', 'fake_after_php');
