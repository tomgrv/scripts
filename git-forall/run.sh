#!/bin/sh
(
    git ls-files --exclude-standard
    git ls-files --exclude-standard --others
) | while read f; do
    $* $f
done
