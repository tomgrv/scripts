#!/bin/bash
set -e

zz_use zz_colors zz_args jq
. zz_colors

eval $(
    zz_args "Normalize JSON according to schema" $0 "$@" <<-help
        w -         write	    write normalized json to original file
        t tabSize   tabSize	    tab size for indentation
        c -         cache	    allow caching of schema validation map
        a -         allow	    allow additional properties at root level
        d -         debug	    debug output
        f fallback  fallback	fallback schema to use if none found locally
        l local     local	    infer schema in <local> folder from json file name (x.y.json => <local>/y.schema.json)
        i -         import	    infer on schema store if nothing found locally (x.y.json => "y" on schema store)
        s schema	schema		schema to use for normalization
        + files	    files		jsons to normalize

help
)

if test -z "$files" || test "$files" = "-" || test "$files" = "/dev/stdin"; then

    if [ -n "$write" ]; then
        zz_log e "Cannot write to stdin. Please unset -w option" && exit 1
    fi

    cat /dev/stdin >/tmp/$$.json
    files="/tmp/$$.json"
fi

for file in $files; do

    if ! test -s "$file"; then
        zz_log e "File {U $file} not found" && continue
    fi

    zz_log i "Normalizing {U $file}..."
    list=$(validate-json ${allow:+-a} ${cache:+-c} ${debug:+-d} ${fallback:+-f "$fallback"} ${local:+-l "$local"} ${import:+-i} ${schema:+-s"$schema"} $file)

    if [ -z "$list" ]; then
        zz_log e "{U $file} not valid, cannot normalize" && exit 1
    fi

    if test -z "$tabSize"; then
        tabSize=$(head -n 2 "$file" | tail -n 1 | sed 's/^\( *\).*/\1/' | tr -d '\n' | wc -c)
        if test -z "$tabSize"; then
            tabSize=2
        fi
    fi

    zz_log i "Tab size: $tabSize"

    script='def xpath($ary):
            . as $in
            | if ($ary|length) == 0 then null
                else $ary[0] as $k
                    | if $k == []
                        then range(0;length) as $i | $in[$i] | xpath($ary[1:]) | [$i] + .
                        else .[$k] | xpath($ary[1:]) | [$k] + .
                        end
                end;
        def paths($ary): $ary[] as $path | xpath($path);
        def traverse($paths):
            . as $in
            | reduce paths($paths) as $p
                (null; setpath($p; $in
                            | getpath($p)
                            | if type == "object" then with_entries(.key |= .)
                            | to_entries
                            | sort_by(.key)
                            | from_entries else . end
                        )
                );'

    echo "$list" | sed 's/^\(.*\)$/path(\1)/' | paste -sd, -  | jq "$script traverse([$(cat)])" $file >/tmp/$$.norm

    if test -s /tmp/$$.norm; then
        if test -z "$write"; then
            jq -M --indent ${tabSize:-2} . /tmp/$$.norm
        else
            jq -M --indent ${tabSize:-4} . /tmp/$$.norm >$file
        fi
        zz_log s "File {U $file} normalized"
    else
        zz_log e "File {U $file} not normalized"
    fi

    rm -f /tmp/$$.*
done
