<?php

use \Diegonz\PHPWakeOnLan\PHPWakeOnLan;

require __DIR__ . '/../vendor/autoload.php';

$config = require(__DIR__ . '/../config/config.php');

try {
    $ping = new \JJG\Ping($config['host'], 128, 3);
}
catch (Exception $e) {
}

$is_on = is_on();
if (!$is_on) {
    sleep(3); // double check after 5 seconds
    $is_on = is_on();
}

$last_ping = $last_wol = 0;

$last_log = last_log_time();

if ($is_on) {
    echo logg('Service Started. PC is On - will not monitor logs, will recheck in 20 seconds');
    sleep(22);
} else {
    echo logg('Service Started. PC is Off - begin monitoring');
}

while (true) {
    $old_is_on = $is_on;
    $is_on = is_on();
    if ($is_on !== $old_is_on) { // change in PC status
        $times_to_recheck_ping = $is_on ? 2 : 10; // if turned off, check ping recurrently for at least 20 seconds
        for ($i = 0; $i < $times_to_recheck_ping; $i++) {
            sleep(2); // double check a few times
            $is_on = is_on();
            if ($is_on === $old_is_on) {
                break;
            }
        }
    }
    if ($is_on !== $old_is_on) {
        if ($is_on) {
            echo logg('PC Has Turned On - will not monitor logs', 'debug');
        } else {
            echo logg('PC Has Turned Off - resetting logs then begin monitoring', 'debug');
            $last_log = last_log_time();
        }
    }
    if ($is_on) {
        echo "PC is on, will recheck in 20 seconds\n";
        sleep(20);
    } else {
        $out = array();
        $log_time = last_log_time(); // null or time
        if (!$log_time || $last_log->greaterThanOrEquals($log_time)) {
            if (!$log_time) {
                echo logg('No log entries in ' . $config['log_file_location'] . ' - Invalid log file location??', 'error');
            } else {
                echo "No new log entries\n";
            }
            $last_log = $log_time;
            sleep(2);
            continue;
        }
        $tail = exec("tail -50 \"{$config['log_file_location']}\"", $out);
        echo "*** NEW LINES ***\n";
        foreach($out as $k => $line) {
            echo $line;
            try {
                $log_time = \Cake\Chronos\Chronos::parse(substr($line, 0, 25) . '00'); // @todo preg match this in case log format changes
            } catch (Exception $e) {
                logg($line, 'debug');
                echo logg('Log line without parsable time (ignoring line)', 'error');
                continue;
            }
            if (strpos($line, 'Completed: [') !== false) {
                logg($line);
                foreach ($config['ignored_hosts'] as $ignored_host) {
                    if (strpos($line, $ignored_host) !== false) {
                        echo logg('Ignoring valid string due to configured ignored host ' . $ignored_host, 'debug');
                        continue(2);
                    }
                }
                try {
                    $wol = new PHPWakeOnLan();
                    echo "****\n";
                    print_r($wol->wake([$config['mac']]));
                    echo logg('WOL Sent to wake computer');
                    $has_switched_on = false;
                    for ($i = 1; $i <= 15; $i++) {
                        // for 15 seconds, keep checking if success
                        sleep(1);
                        if (is_on()) {
                            echo logg('Successfully switch on PC');
                            $has_switched_on = true;
                            break;
                        } elseif ($i === 5 || $i === 10) {
                            echo logg('Reattempting WOL after ' . $i . ' seconds');
                            print_r($wol->wake([$config['mac']])); // reattempt WOL twice
                        }
                    }
                    if (!$has_switched_on) {
                        echo logg('ERROR - did not switch on after 3 WOLs', 'error');
                    }
                    $last_log = last_log_time();
                    break;
                } catch (Exception $e) {
                    echo logg('Error sending WOL - ' . $e->getMessage(), 'error');
                    break;
                }
            }
            echo $line . "\n";
        }
        $last_log = last_log_time();
        sleep(2);
    }
}


function logg($message, $type = 'info') {
    global $config;
    if ($config['http_logger']) {
        $context  = stream_context_create(['http' => [
            'method'  => 'POST',
            'header'  => 'Content-Type: application/x-www-form-urlencoded',
            'content' => http_build_query([
                'message' => $message . ' (PID ' . getmypid() . ')',
                'type' => $type
            ])
        ]]);
        file_get_contents($config['http_logger'], false, $context);
        return "Logged: $message\n";
    }
    return "$message\n";
}

function last_log_time() {
    global $config;
    $out = array();
    $tail = exec("tail -1 \"{$config['log_file_location']}\"", $out);
    if (!$tail) {
        return null;
    }
    try {
        return \Cake\Chronos\Chronos::parse(substr($tail, 0, 25) . '00');
    } catch (Exception $e) {
        return null;
    }
}

function is_on() {
    global $config, $ping;
    return $ping->ping() !== false;
}
