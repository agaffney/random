#!/bin/bash

contains() {
    local n=$#
    local value=${!n}
    local i
    for ((i=1;i < $#;i++)) {
        if [ "${!i}" == "${value}" ]; then
            return 0
        fi
    }
    return 1
}

message() {
        local line=$1
        shift
        local msg=$@
        echo "${template}:${line}: ${msg}"
}

ruby_tag() {
        local ruby_open=$1
        if [ $ruby_open = 0 ]; then
                echo '<%=\? *'
        fi
}

template=$1

ORIG_IFS=$IFS

if [ -z "$template" ]; then
        echo "You must specify a template"
        exit 1
fi

if [ ! -f $template ]; then
        echo "The specified template '${template}' doesn't exist"
        exit 1
fi

declare -a defined_vars=( )

linenum=0
ruby_open=0
while read line; do
        linenum=$((linenum + 1))
        # Look for opening ruby tags without closing
        if echo "$line" | grep -q '<%' && ! echo "$line" | grep -q -- '-\?%>'; then
                ruby_open=1
        fi
        # Look for closing ruby tag
        if ! echo "$line" | grep -q '<%' && echo "$line" | grep -q -- '-\?%>'; then
                ruby_open=0
        fi
        # Simple assignment
        if [ $ruby_open = 1 ]; then
                foo=$(echo "$line" | grep -o '^[[:space:]]*[a-z0-9_A-Z]\+[[:space:]]*=' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]\+=$//')
                if [ -n "$foo" ]; then
                        defined_vars=( "${defined_vars[@]}" $foo )
                fi
        fi
        # Iterator variables
        matches=$(IFS=', '; echo "$line" | grep -o '\(\<do\|{\)[[:space:]]\+|[a-z0-9_A-Z, ]\+|' | sed -e 's/^[^|]*|//' -e 's/|.*$//' | tr ',' ' ')
        if [ -n "$matches" ]; then
                for match in $matches; do
                        defined_vars=( "${defined_vars[@]}" $match )
                done
        fi
        # Simple variable replacements
        matches=$(echo "$line" | grep -o '<%= *[a-z0-9_A-Z]\+ *-\?%>')
        if [ -n "$matches" ]; then
                IFS=$'\n'
                for match in $matches; do
                        IFS=$ORIG_IFS
                        var=$(echo "$match" | sed -e 's:\(<%=\? *\| *%-\?>\)::g')
                        IFS=$'\n'
                        if ! contains  "${defined_vars[@]}" $var; then
                                message $linenum "Simple variable replacement without instance variable: ${match}"
                        fi
                done
                IFS=$ORIG_IFS
        fi
        # Variable in 'if' statement
        matches=$(echo "$line" | grep -o "$(ruby_tag $ruby_open)\(\(el\)\?if\|&&\|||\) *[a-z0-9_A-Z]\+[^a-z0-9_A-Z?(]")
        if [ -n "$matches" ]; then
                IFS=$'\n'
                found=0
                for match in $matches; do
                        var=$(echo "$match" | sed -e 's:^.*\([a-z0-9_A-Z]\+\)$:\1:')
                        if ! contains "${defined_vars[@]}" $var; then
                                found=1
                        fi
                done
                if [ $found = 1 ]; then
                        message $linenum "If statement without instance variable"
                fi
        fi
done < $template
