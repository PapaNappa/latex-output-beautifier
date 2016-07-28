#!/bin/bash

function error() { #{{{1
    echo "$0: $1" >&2
    if [[ $# -eq 2 ]]; then
        exit $2
    else
        exit 1
    fi
}

function opt_error() { #{{{1
    local msg="$1"
    shift
    error "$msg"$'\n'"Use --help to see a list of available options." "$@"
}

function help() { #{{{1
    echo 'Usage: max_print_line=100000 latex | $0 [options ...]
Options:
    --color=<mode>  Use colours to highlight errors and warnings. <mode> can be
                    one of "auto", "never", "always" or "visual".
                    "visual" tries to replace some colors with text markup,
                    where appropriate.
    --pdf-dest      Supress pdftex warnings about non-existing link targets
                    ("has been referenced but does not exist, replaced by a
                    fixed one").
                    Can be handy when compiling individual chapters
                    using \include / \includeonly.
    --tex-dist <regex>
                    Set the regular expression that matches files in your TeX-
                    distribution. Any listing of loaded files from your dis-
                    tribution will be supressed. Use an empty string to show
                    these files, too.
                    Uses GNU awk regular expression, except that you do not
                    need to escape /. Default:
                    '$TEX_DIST'
'
}

# default values {{{1

# --color=auto is the default
# if connected to a terminal, uses colors, otherwise uses --color=visual
function color_auto() {
    if [ -t 1 ]; then
        COLOR=1
    else
        COLOR=v
    fi
}
color_auto

TEX_DIST='/usr/share/texmf|/var/lib/texmf'

# parse arguments {{{1
while [ $# -ge 1 ]; do
    case $1 in
        --pdf-dest) PDF_DEST=1;;
        --color=*)
            mode=${1#*=}
            case $mode in
                 never) COLOR=0;;
                  auto) color_auto;;
                always) COLOR=1;;
                visual) COLOR=v;;
                     *) opt_error "Unknown argument to --color: $mode";;
            esac
            shift;;
        --tex-dist) TEX_DIST=$2; shift;;
        --tex-dist=*) TEX_DIST=${1#*=};;
        --help|-h) help; exit 0;;
        *) opt_error "Unknown option $1";;
    esac
    shift
done

# replace / in $TEX_DIST by the escaped \/ required in awk regular expressions
TEX_DIST=${TEX_DIST//\//\\\/}

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

# }}}1

# different snippets of AWK code for different cases {{{1

# DIST_FILES: remove any references to files in the LateX distribution {{{2
# (e.g. /usr/share/texmf-dist/….sty)
if [ -n $TEX_DIST ]; then
    DIST_FILES='{
        n = gsub(/\s*[<{]?('"${TEX_DIST}"')[^<>(){}]*[>}]?\s*/, "")
        if (n)
            changed = 1
    }'
fi

# EMPTY_GROUPS: remove empty groups "()" {{{2
EMPTY_GROUPS='{
    do {
        n = gsub(/\s*\(\s*\)\s*/, " ")
        if (n) {
            gsub(/\s+/, " ") # merge multiple spaces
            gsub(/^\s/, "") # trim
            changed = 1
        }
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

# COMPRESS_WARNINGS: remove empty lines sorrounding warnings {{{2
# when multiple warnings are printed next to each other, up to two empty lines separate them
# in particular for the first two latex runs, when there can be lots of warnings (esp. undefined citations or references), this fills much space in the terminal
COMPRESS_WARNINGS='/warning/ { skip_next_blanks = 1 }'

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

# }}}2

# at this point, one record may contain multiple lines,
# so case must be taken to affect only single output lines

# COLORIZE_*: colorize errors and warnings {{{2
if [ $COLOR -eq 1 ]; then
    color_warn_regexp='warning|^Runaway argument'
    COLORIZE_WARN='/'"$color_warn_regexp"'/ { gsub(/[^\n]*('"$color_warn_regexp"')[^\n]*/, c_warn "&" c_reset) }'
    color_error_regexp='error|^!|^[^(){}<>:]+\.tex:[0-9]+:'
    COLORIZE_ERROR='/'"$color_error_regexp"'/ { gsub(/[^\n]*('"$color_error_regexp"')[^\n]*/, c_err "&" c_reset) }'
    color_boxes_regexp='underfull|overfull'
    COLORIZE_BOXES='/'"$color_boxes_regexp"'/ { gsub(/[^\n]*('"$color_boxes_regexp"')[^\n]*/, c_box "&" c_reset) }'
fi

# MERGE_EMPTY: merge multiple empty lines {{{2
MERGE_EMPTY='empty && lastempty { next }'

# }}}1

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
    -e 'skip_next_blanks && length() == 0 { next }' \
    -e 'length() > 0 { skip_next_blanks = 0 }' \
    -e '{ changed = 0; lastempty = empty }' \
    -e " $DIST_FILES" \
    -e " $EMPTY_GROUPS" \
    -e " $PDF_DEST" \
    -e " $COMPRESS_WARNINGS" \
    -e " $COLORIZE_CHAPTER" \
    -e " $PULL_MESSAGES_APART" \
    -e " $COLORIZE_WARN" \
    -e " $COLORIZE_ERROR" \
    -e " $COLORIZE_BOXES" \
    -e '{ empty = $0 ~ /^\s*$/ }' \
    -e " $MERGE_EMPTY" \
    -e '{ if (!changed || !empty) print }'


# vim: ft=sh expandtab sw=4 ts=4 foldenable fdm=marker
