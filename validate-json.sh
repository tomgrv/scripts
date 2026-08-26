#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/zz_wrap.sh" 2>/dev/null || . zz_wrap
zz_use jq curl

eval $(
    zz_args "Validate JSON according to schema" $0 "$@" <<-help
        a -         allow	    allow additional properties at root level
        d -         debug	    debug output
        c -         cache	    allow caching
        f fallback  fallback	fallback schema to use if none found locally
        l local     local	    infer schema in <local> folder from json file name (x.y.json => <local>/y.schema.json). Use "true" to use script folder
        i -         import	    infer on schema store if nothing found locally (x.y.json => "y" on schema store)
        s schema	schema		schema to use to validate json
        - json	    json		json to validate
help
)

is_json() {
    jq empty 2>/dev/null
}

is_json_array() {
    local path=${1:-.}
    get_path "$path" -r | jq -e 'if type == "array" then . else null end' >/dev/null
}

is_json_object() {
    local path=${1:-.}
    get_path "$path" -r | jq -e 'if type == "object" then . else null end' >/dev/null
}

is_json_ref() {
    local path=${1:-.}
    get_path "$path" -r | jq -e 'if type == "object" and has("$ref") then . else null end' >/dev/null
}

is_existing_path() {
    local path=${1:-.}
    get_path "$path" 2>/dev/null >/dev/null

}

is_true() {
    local path=${1:-.}
    get_path "$path" -r | jq -e 'if . == true then . else null end' >/dev/null
}

get_json_array() {
    local path=${1:-.}
    get_path "$path" -r | jq -r 'type | tojson'
}

get_json_type() {
    local path=${1:-.}
    get_path "$path" -r | jq -r 'type | tojson'
}

get_json() {
    local path=${1:-.}
    get_path "$path" -r | jq -r 'if . == null then {} else . end | tojson'
}

get_array_size() {
    local path=${1:-.}
    get_path "$path" -r | jq -r 'length'
}

get_array_items() {
    local path=${1:-.}
    get_path "$path" -r | jq -r 'if type == "array" then .[] else . end | tojson'
}

get_keys() {
    local path=${1:-.}
    get_path "$path" -r | jq -r 'if type == "object" then keys_unsorted else [] end' | sed -e 's/^\[//g' -e 's/\]$//g' -e 's/,$//g' -e 's/^[[:blank:]]*//g' -e '/^$/d'
}

get_path() {
    local path=${1:-.}
    local raw=$(test -z "$2" && echo "-r" || echo "")

    jq -e --arg path "$path" $raw '
        def split_path:
            gsub("\\["; ".") | gsub("\\]"; "") | split(".") | map(
                select(length > 0) | gsub("^\"|\"$";"") | if test("^[0-9]+$") then tonumber else . end
            );
        getpath($path | split_path)' 2>/dev/null
}

oneOf_rule() {
    local size=$1
    local count=$2
    local index=$3

    test $count -eq 1
}

allOf_rule() {
    local size=$1
    local count=$2
    local index=$3

    test $count -eq $size
}

anyOf_rule() {
    local size=$1
    local count=$2
    local index=$3

    test "$count" -gt "0" && test $index -eq $(expr $size - 1)
}

get_schema_url() {
    local name=$1
    local catalog=https://raw.githubusercontent.com/SchemaStore/schemastore/master/src/api/json/catalog.json
    curl -s $catalog | jq -r -e ".schemas[] | select(.name == \"$name\") | .url"
}

validate() {

    local json=$1       # JSON to validate (mandatory)
    local schema=$2     # Schema to use (mandatory)
    local path=$3       # Path to schema (optional)
    local real=$4       # Real path in JSON (optional)
    local call=${5:-$3} # Reference flag (optional)
    local not=$6        # Not flag (optional)
    local level=$7      # Recursive level for logs (optional)

    if test -f "$json" || test -n "$(echo $json | grep -E '^http')"; then
        json=$(load-json $json)
    fi

    if ! is_json <<<"$json"; then
        zz_log e "Invalid json" && exit 1
    fi

    if test -f "$schema" || test -n "$(echo $schema | grep -E '^http')"; then
        zz_log "${lvl} -" "Loading ${Yellow}${uri}${None}..."
        schema=$(load-json -s $schema)
    fi

    if ! is_json <<<"$schema"; then
        zz_log e "Invalid schema" && exit 1
    fi

    local entry=""
    local props=""
    local items=""
    local prop=""
    local more=""
    local type=""
    local lvl=""
    local id=$(get_path ".\$id" <<<"$schema")

    if test -z "$level"; then
        level=0
    else
        level=$(expr $level + 1)

        for i in $(seq 1 $level); do
            lvl="$lvl   |"
        done
    fi

    zz_log "${lvl}" "{Blue Parsing schema <${path:-.}> == <${real:-.}>} {None at level <$level>}"

    for entry in '"$id"' '"not"' '"oneOf"' '"allOf"' '"anyOf"' '"type"' '"required"' '"$ref"' '"properties"' '"items"' '"additionalProperties"'; do

        if ! is_existing_path "$path.$entry" <<<"$schema"; then
            continue
        fi

        zz_log "${lvl} -" "Processing <{Blue ${path}:$entry}>"

        case $entry in

        \"\$id\")

            zz_log "${lvl} -" "Processing {B Id}"

            id=$(get_json "$path.$entry" <<<"$schema" || echo ".")

            zz_log "${lvl} -" "Resolving ${Yellow}$id"
            ;;

        \"\$ref\")

            local ref=$(get_path "$path.$entry" <<<"$schema")

            if test "$ref" == "null" || test -z "$ref"; then
                zz_log e "Reference not found for $path.$entry" && exit 1
            fi

            zz_log "${lvl} -" "Ref is {Yellow ${ref}}"
            zz_log "${lvl}  " "From {Yellow ${id}}..."

            local uri=$(echo $ref | awk -F '#' '{print $1}')
            local fgt=$(echo $ref | awk -F '#' '{print $2}')

            if test -n "$uri"; then
                if test -f "$uri" || test -n "$(echo $uri | grep -E '^http')"; then
                    zz_log "${lvl} -" "Loading ${Yellow}${uri}${None}..."
                    schema=$(load-json -s $uri)
                elif test -n "$id"; then
                    zz_log "${lvl} -" "Loading ${Yellow}$(dirname $id)/$uri${None}..."
                    schema=$(load-json -s $(dirname $id)/$uri)
                else
                    zz_log e "Unable to resolve reference {U $ref} using {B $id}" && exit 1
                fi
            fi

            if ! is_json <<<"$schema"; then
                zz_log e "Unable to load reference {U $uri}" && exit 1
            fi

            if ! validate "$json" "$schema" "$(echo $fgt | tr '/' '.')" "$real" "$path" "$not" "$level"; then
                zz_log "${lvl} -" "{Yellow Reference $ref is invalid}"
                return 1
            fi
            ;;

        \"not\")
            zz_log "${lvl} -" "{Purple Start Not}"

            if ! validate "$json" "$schema" "$path.$entry" "$real" "$path.$entry" "!" "$level"; then
                zz_log "${lvl} -" "{Yellow Condition is invalid}"
                return 1
            fi

            zz_log "${lvl} -" "{Purple End Not}"
            ;;

        \"oneOf\" | \"allOf\" | \"anyOf\")

            if ! is_json_array "$path.$entry" <<<"$schema"; then
                zz_log e "Invalid $entry schema" && exit 1
            fi

            local size=$(get_array_size "$path.$entry" <<<"$schema")
            local last=$(expr $size - 1)
            local count=0

            zz_log "${lvl} -" "{Cyan Start $entry loop}"

            for i in $(seq 0 $last); do
                if validate "$json" "$schema" "$path.$entry[$i]" "$real" "$path.$entry[$i]" "$not" "$level"; then
                    count=$(expr $count + 1)
                fi
                ${entry//\"/}_rule $size $count $i && break
            done

            zz_log "${lvl} -" "{Cyan End $entry loop ($count/$size)}"
            ${entry//\"/}_rule $size $count $last || return 1
            ;;

        \"type\")

            zz_log "${lvl} -" "Processing {B Type}"

            local type_json=$(get_json_type "$real" <<<"$json")

            for type_schema in $(get_array_items "$path.$entry" <<<"$schema"); do

                if test "$type_schema" == "\"integer\""; then
                    type_schema="\"number\""
                fi

                if test "$type_json" != "$type_schema"; then
                    continue
                fi

                type=$type_schema
            done

            if test -z "$type"; then
                zz_log "${lvl} -" "${Yellow}Property ${real:-.} is ${type_json}, not of expected type ${type_schema}"
                return 1
            fi

            echo ${real:-.}

            zz_log "${lvl} -" "${Green}Property ${real:-.} is of expected type ${type}"
            ;;

        \"required\")

            local count=0
            local size=0

            if test "$type" != "\"object\""; then
                zz_log "${lvl} -" "${Yellow}Skip required not an object ($type)"
                continue
            fi

            for prop in $(get_array_items "$path.$entry" <<<"$schema"); do

                size=$(expr $size + 1)

                if is_existing_path "$real.$prop" <<<"$json"; then
                    if test -n "$not"; then
                        zz_log "${lvl} -" "${Yellow}Property $prop is present but not required"
                        return 1
                    fi
                else
                    if test -z "$not"; then
                        zz_log "${lvl} -" "${Yellow}Property $prop is missing but required"
                        return 1
                    fi
                fi

                zz_log "${lvl} -" "${Green}Property requirement is valid for $prop"
            done
            ;;

        \"items\")

            if test "$type" != "\"array\""; then
                zz_log "${lvl} -" "${Yellow}Skip properties not an  ($type)"
                continue
            fi

            zz_log "${lvl} -" "Processing ${BWhite}Items"

            for item_index in $(seq 0 $(expr $(get_array_size "${real:-.}" <<<"$json") - 1)); do

                item=$(get_array_items "${real:-.}[$item_index]" <<<"$json" )

                zz_log "${lvl} -" "Processing item <${Purple}${real:-.}[$item_index]${None}>"

                if ! validate "$json" "$schema" "$path.$entry" "${real:-.}[$item_index]" "$path.$entry[$item_index]" "$not" "$level"; then
                    zz_log "${lvl} -" "${Red}Item $item is invalid"
                    return 1
                fi
            done
            ;;

        \"properties\")

            if test "$type" != "\"object\""; then
                zz_log "${lvl} -" "${Yellow}Skip properties not an object ($type)"
                continue
            fi

            zz_log "${lvl} -" "Processing ${BWhite}Properties"

            props=$(get_keys "$path.$entry" <<<"$schema" | tr "\n" " ")

            for prop in $props; do

                if $not is_existing_path "$real.$prop" <<<"$json"; then

                    zz_log "${lvl} -" "Processing <${Purple}$prop${None}>"

                    if ! validate "$json" "$schema" "$path.$entry.$prop" "$real.$prop" "$path.$entry.$prop" "$not" "$level"; then
                        zz_log e "Property $prop is present but invalid${Red}" >&2
                        return 1
                    fi
                else
                    zz_log "${lvl} -" "${Yellow}Skip property $real.$prop not present"
                fi
            done
            ;;

        \"additionalProperties\")

            zz_log "${lvl} -" "Processing ${BWhite}Additional properties"
            if is_existing_path "$path.$entry" <<<"$schema"; then

                zz_log "${lvl} -" "${Purple}Additional properties allowed for ${real:-.}"

                for prop in $(get_keys "$real" <<<"$json" | sort); do

                    if ! grep -q -x "$prop" <<<"$props"; then
                        zz_log "${lvl} -" "Adding additional property <${Purple}$real.$prop${None}>"

                        echo "$real.$prop"
                    fi
                done
            fi
            ;;
        esac
    done

    zz_log "${lvl}" "{Blue End Parsing, all valid!}" >&2
}

if [ -z "$schema" ]; then

    schema=$(load-json $json | jq -r '."$schema" // empty')

    if test -n "$schema"; then
        zz_log i "Found schema reference in JSON file: {U $schema}"
    fi
fi

if [ -n "$local" ] && [ -z "$schema" ]; then

    type=$(basename -s .json $json | sed -E 's/.*\.(.*)/\1/')

    if [ "$local" == "true" ]; then
        local=$(dirname $(readlink -f $0))/config
    fi

    if [ -f "$local/_$type.schema.json" ]; then
        schema=$local/_$type.schema.json
    fi

    zz_log i "Infering schema from local folder {U $local} for {UYellow $json}"
fi

if [ -n "$import" ] && [ -z "$schema" ]; then

    search=$(basename -s .json $json | sed -E 's/.*\.(.*)/\1/').json

    schema=$(get_schema_url $search)

    zz_log i "Infering schema from schema store for {UYellow $search} ${schema:+"found!"}"
fi

if [ -n "$fallback" ] && [ -z "$schema" ]; then

    if [ "$fallback" == "local" ] && [ -n "$local" ]; then
        schema=$(dirname $(readlink -f $0))/config/_default.schema.json
    elif [ -f "$fallback" ]; then
        schema=$fallback
    else
        zz_log e "Fallback schema $fallback not found" && exit 1
    fi

    zz_log w "Using fallback schema {UYellow $schema}"
fi

if test -z "$schema"; then
    zz_log e "Schema is missing" && exit 1
fi

schema=$(load-json -s "$schema")

if test -z "$schema"; then
    zz_log e "Schema is empty" && exit 1
fi

if ! is_json <<<"$schema"; then
    zz_log e "Invalid schema" && exit 1
fi

if test -n "$allow"; then
    zz_log w "Additional properties allowed at root level"
    schema=$(echo "$schema" | jq '. + {"additionalProperties": true}' -)
fi

hash=$(
    (
        jq 'paths | map(tostring) | join(".")' $json
        echo "$schema" | jq 'paths | map(tostring) | join(".")'
    ) | sort -u | md5sum | awk '{print $1}'
)
map=~/.cache/$hash.schema.map
zz_log i "Hash is {B $hash}"

if test -n "$cache" && test -s $map; then
    zz_log - "Using cached validation map"
    cat $map
else
    validate "$json" "$schema" | sed -n -e 's/^.$//g' -e '/^$/d' -e 'G; s/\n/&&/; /^\([ -~]*\n\).*\n\1/d; s/\n//; h; P'
    status=${PIPESTATUS[0]}

    if [ "$status" -eq 0 ]; then
        zz_log s "JSON {U $json} valid"
    else
        zz_log e "JSON {U $json} empty or invalid"
        exit 1
    fi
fi
