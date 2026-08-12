<?php

/**
 * Return the current end of a log so existing requests are not replayed.
 */
function log_end_offset(string $path): int
{
    clearstatcache(true, $path);
    $size = @filesize($path);

    return $size === false ? 0 : $size;
}

/**
 * Read each complete line appended since the previous call exactly once.
 *
 * A null result means the log is unavailable. If Plex rotates or truncates its
 * log, reading resumes from the beginning of the replacement file.
 *
 * @return list<string>|null
 */
function read_new_log_lines(string $path, int &$offset): ?array
{
    clearstatcache(true, $path);
    $size = @filesize($path);
    if ($size === false) {
        return null;
    }

    if ($size < $offset) {
        $offset = 0;
    }

    if ($size === $offset) {
        return [];
    }

    $handle = @fopen($path, 'rb');
    if ($handle === false || fseek($handle, $offset) !== 0) {
        if (is_resource($handle)) {
            fclose($handle);
        }

        return null;
    }

    $lines = [];
    while (($lineStart = ftell($handle)) !== false && ($line = fgets($handle)) !== false) {
        if (!str_ends_with($line, "\n")) {
            // Plex may still be writing this record. Leave it for the next poll.
            fseek($handle, $lineStart);
            break;
        }
        $lines[] = $line;
    }

    $newOffset = ftell($handle);
    fclose($handle);
    if ($newOffset !== false) {
        $offset = $newOffset;
    }

    return $lines;
}
