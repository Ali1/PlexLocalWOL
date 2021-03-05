<?php

use \Diegonz\PHPWakeOnLan\PHPWakeOnLan;

require __DIR__ . '/../vendor/autoload.php';

$config = require('config.php');

try {
    $ping = new \JJG\Ping($config['host'], 128, 2);
}
catch (Exception $e) {
}

$is_on = $ping->ping() !== false;
$last_ping = $last_wol = 0;

$out = array();
$tail = exec("tail -1 \"{$config['log_file_location']}\"", $out);
$time = \Cake\Chronos\Chronos::parse(substr($tail, 0, 25) . '00');
$last_log = $time;

echo logg('Logging Starting - PC is ' . ($is_on ? 'on' : 'off'));
while (true) {
    $old_is_on = $is_on;
    $is_on = $ping->ping() !== false;
    if ($is_on !== $old_is_on) {
        sleep(3); // double check after 3 seconds
        $is_on = $ping->ping() !== false;
        if ($is_on !== $old_is_on) {
            if ($is_on) {
                echo logg('PC Has Turned On - will not monitor logs');
            } else {
                echo logg('PC Has Turned Off - resetting logs then begin monitoring');
                $out = array();
                $tail = exec("tail -1 \"{$config['log_file_location']}\"", $out);
                $time = \Cake\Chronos\Chronos::parse(substr($tail, 0, 25) . '00');
                $last_log = $time;
            }
        }
    }
    if ($is_on) {
        echo "PC is on so sleeping for 20 seconds\n";
        sleep(20);
    } else {
        $out = array();
        $tail = exec("tail -50 \"{$config['log_file_location']}\"", $out);
        $new_lines = false;
        foreach($out as $k => $line) {
            $log_time = \Cake\Chronos\Chronos::parse(substr($line, 0, 25) . '00');
            if ($last_log->gte($log_time)) {
                continue;
            }
            if (!$new_lines) {
                echo "*** NEW LINES ***\n";
            }
            $new_lines = true;
            echo $line;
            if (strpos($line, 'Completed: [') !== false) {
                echo logg($line);
                try {
                    $wol = new PHPWakeOnLan();
                    print_r($wol->wake([$config['mac']]));
                    echo "****\n";
                    echo logg('WOL Sent - sleeping 15 seconds and ignoring log entries');
                    echo "****\n";
                    sleep(15);
                    $out = array();
                    $tail = exec("tail -1 \"{$config['log_file_location']}\"", $out);
                    $time = \Cake\Chronos\Chronos::parse(substr($tail, 0, 25) . '00');
                    $last_log = $time;
                    break;
                } catch (Exception $e) {
                    echo logg('Error sending WOL - ' . $e->getMessage());
                    break;
                }
            }
            echo $line . "\n";
        }
        if (!$new_lines) {
            echo 'Pulled ' . count($out) . " lines from log file - no news\n";
        } else {
            echo "********\n";
        }
        $out = array_reverse($out);
        if ($out) {
            $last_log = \Cake\Chronos\Chronos::parse(substr($out[0], 0, 25) . '00');
        }
        sleep(2);
    }
}


function logg($message) {
    global $config;
    if ($config['http_logger']) {
        file_get_contents($config['http_logger'] . urlencode($message));
        return "Logged: $message\n";
    }
    return "$message\n";
}