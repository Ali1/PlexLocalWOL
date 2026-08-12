<?php

require __DIR__ . '/../src/log_reader.php';

function assert_same($expected, $actual, string $message): void
{
    if ($expected !== $actual) {
        fwrite(STDERR, $message . PHP_EOL);
        fwrite(STDERR, 'Expected: ' . var_export($expected, true) . PHP_EOL);
        fwrite(STDERR, 'Actual: ' . var_export($actual, true) . PHP_EOL);
        exit(1);
    }
}

$path = tempnam(sys_get_temp_dir(), 'plexlocalwol-');
if ($path === false) {
    throw new RuntimeException('Could not create temporary log file');
}

try {
    file_put_contents($path, "old Completed: [client] request\n");
    $offset = log_end_offset($path);
    assert_same([], read_new_log_lines($path, $offset), 'Existing requests must not be replayed at startup.');

    file_put_contents($path, "routine server activity\n", FILE_APPEND);
    assert_same(["routine server activity\n"], read_new_log_lines($path, $offset), 'Only appended activity should be returned.');
    assert_same([], read_new_log_lines($path, $offset), 'An appended line must only be returned once.');

    file_put_contents($path, "new Completed: [client] request\n", FILE_APPEND);
    assert_same(["new Completed: [client] request\n"], read_new_log_lines($path, $offset), 'A new client request should be returned.');

    file_put_contents($path, 'partial Completed: [client]', FILE_APPEND);
    assert_same([], read_new_log_lines($path, $offset), 'A partially written record should wait for its newline.');
    file_put_contents($path, " request\n", FILE_APPEND);
    assert_same(["partial Completed: [client] request\n"], read_new_log_lines($path, $offset), 'A completed record should be returned intact.');

    file_put_contents($path, "replacement log after rotation\n");
    assert_same(["replacement log after rotation\n"], read_new_log_lines($path, $offset), 'A truncated or rotated log should be read from its beginning.');

    unlink($path);
    assert_same(null, read_new_log_lines($path, $offset), 'An unavailable log should return null.');
} finally {
    if (file_exists($path)) {
        unlink($path);
    }
}

echo "log reader tests passed\n";
