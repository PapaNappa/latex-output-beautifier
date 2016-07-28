#!/bin/bash

function error() { #{{{
    echo "$0: $1" >&2
    if [[ $# -eq 2 ]]; then
        exit $2
    else
        exit 1
    fi
} #}}}

# --color=auto is the default
if [ -t 1 ]; then
    COLOR=0
else
    COLOR=v
fi

# parse arguments {{{1
while [[ $# -ge 1 ]]; do
    case $1 in
        --pdf-dest) PDF_DEST=1;;
        --color=*)
            mode=${1#*=}
            case $mode in
                 never) COLOR=0;;
                  auto) ! [ -t 1 ]; COLOR=$?;;
                always) COLOR=1;;
                visual) COLOR=v;;
                     *) error "Unknown argument to --color: $mode";;
            esac
            shift;;
        *) error "Unknown option $1";;
    esac
    shift
done

# variables to set color escape codes {{{1
if [[ $COLOR -eq 1 ]]; then
    C_RED=$'\x1B[91m'
    C_YELLOW=$'\x1B[93m'
    C_MAGENTA=$'\x1B[95m'
    C_RESET=$'\x1B[0m'
    C_BOLD=$'\x1B[1m'
else
    # if we are not connected to a terminal, simply set these to empty strings
    C_RED=''
    C_YELLOW=''
    C_MAGENTA=''
    C_RESET=''
    C_BOLD=''
fi

C_WARN=$C_YELLOW
C_ERR=$C_RED
C_BOX=$C_MAGENTA
C_CHAPTER=$C_BOLD

# different snippets of AWK code for different cases {{{1

# DIST_FILES: remove any references to files in the LateX distribution {{{2
# (e.g. /usr/share/texmf-dist/….sty)
DIST_FILES='{
    n = gsub(/\s*[<{]?(\/usr\/share\/texmf|\/var\/lib\/texmf)[^<>(){}]*[>}]?\s*/, "")
    if (n)
        changed = 1
}'

# EMPTY_GROUPS: remove empty groups "()" {{{2
EMPTY_GROUPS='{
    do {
        n = gsub(/\s*\(\s*\)\s*/, "")
        if (n)
            changed = 1
    } while (n)
}'

# PDF_DEST: remove pdfTeX warning of non-existing link target {{{2
# (happens e.g. when compiling only individual chapters with references to other chapters)
if [[ $PDF_DEST == 1 ]]; then
    PDF_DEST='{
        n = gsub(/pdfTeX warning \(dest\):.*has been referenced but does not exist, replaced by a fixed one/, "")
        if (n)
            changed = 1
    }'
fi

# COLORIZE_CHAPTER: highlight chapters in the output {{{2
if [[ $COLOR -eq 1 ]]; then
    COLORIZE_CHAPTER='{
        gsub(/^(part|chapter|section) .*/, c_chapter "&" c_reset)
    }'
elif [[ $COLOR == v ]]; then
    # visually highlight chapters
    COLORIZE_CHAPTER=' /^(part|chapter|section)/ {
        $0 = "\n" $0 "\n" repeat("=", length())
    }'
fi

# PULL_MESSAGES_APART: pull apart some messages to different lines {{{2
PULL_MESSAGES_APART='{
    $0 = gensub(/(\w|\.)\s*\[/, "\\1\n[", "g")
}'

# at this point, one record may contain multiple lines, {{{2
# so case must be taken to affect only single output lines

# COLORIZE: colorize errors and warnings {{{2
COLORIZE='
    /warning/ { gsub(/[^\n]*warning[^\n]*/, c_warn "&" c_reset) }
    /error/ { gsub(/[^\n]*error[^\n]*/, c_err "&" c_reset) }
    /underfull|overfull/ { gsub(/[^\n]*(overfull|underfull)[^\n]*/, c_box "&" c_reset) }
'

# MERGE_EMPTY: merge multiple empty lines
MERGE_EMPTY='empty && lastempty { next }'

# utility functions {{{1

FUNCTIONS='
function repeat(str, n,    rep, i ) {
    for (i = 0 ; i < n; i++)
        rep = rep str
    return rep
}
'

# now run gawk, compiling the single snippets together {{{1
# note: the spaces in the -e option front of the variable names are required to prevent
#   warnings about empty arguments in cases where a snippet is disabled
gawk \
    -v c_warn=$C_WARN -v c_err=$C_ERR -v c_box=$C_BOX -v c_chapter=$C_CHAPTER -v c_reset=$C_RESET \
    -e "$FUNCTIONS" \
    -e 'BEGIN { IGNORECASE=1 }' \
    -e '{ changed = 0; lastempty = empty }' \
    -e " $DIST_FILES" \
    -e " $EMPTY_GROUPS" \
    -e " $PDF_DEST" \
    -e " $COLORIZE_CHAPTER" \
    -e " $PULL_MESSAGES_APART" \
    -e " $COLORIZE" \
    -e '{ empty = length() == 0 }' \
    -e " $MERGE_EMPTY" \
    -e '{ if (!changed || !empty) print }'


# vim: ft=sh expandtab sw=4 ts=4 foldenable fdm=marker
