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
    --color=<mode>
            Use colours to highlight errors and warnings. <mode> can be one of
            "auto", "never", "always" or "visual".
            "visual" tries to replace some colors with text markup,
            where appropriate.
    --pdf-dest
            Supress pdftex warnings about non-existing link targets ("has been
            referenced but does not exist, replaced by a fixed one").
            Can be handy when compiling individual chapters
            using \include / \includeonly.
    --tex-dist=<regex>
            Set the regular expression that matches files in your TeX-
            distribution. Any listing of loaded files from your distribution
            will be supressed. Use an empty string to show these files, too.
            Uses GNU awk regular expression, except that you do not
            need to escape /. Default:
            '$TEX_DIST'
    --strip-path=<regex>
            Strip any path components matching regex. This results in shorter
            filenames.
    --graphics[=<mode>]
            Filter all occurances of included graphics according to <mode>.
            If <mode> is not given, defaults to "loading,reference,path".
            <mode> can be a comma-separated list of the following values:
            * loading: filter loaded graphics (includes dimensions)
            * reference: filter referenced graphics (\includegraphics),
                         does not contain dimensions
            * combined: keep exactly one of these
            * placement: filter graphics placed at pages
            * all: eq. to "loading,reference,placement"
            * path: filter path, only keep filename
            The default value is "combined,placement,path"
'
}

# default values {{{1

# --color=auto is the default
# if connected to a terminal, uses colors, otherwise uses --color=visual
function color_auto() {
    if [[ -t 1 ]]; then
        COLOR=1
    else
        COLOR=v
    fi
}
color_auto

# values may also be set using environment variables
# thus, use default values only when the variables are not set

[ -z $TEX_DIST] && TEX_DIST='/usr/share/texmf|/var/lib/texmf'
[ -z $GRAPHICS] && GRAPHICS=combined,placement,path

# parse arguments {{{1
while [[ $# -ge 1 ]]; do
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
            esac;;

        --tex-dist) TEX_DIST=$2; shift;;
        --tex-dist=*) TEX_DIST=${1#*=};;

        --strip-path) STRIP_PATH=$2; shift;;
        --strip-path=*) STRIP_PATH=${1#*=};;

        --graphics) GRAPHICS="loading,reference,path";;
        --graphics=*)
            mode=${1#*=}
            case $mode in
                 all) GRAPHICS="loading,reference,placement";;
                 none) GRAPHICS="";;
                 *) GRAPHICS="$mode";;
            esac
            shift;;

        --help|-h) help; exit 0;;
        *) opt_error "Unknown option $1";;
    esac
    shift
done

# replace / in regexes by the escaped \/ required in awk regular expressions
TEX_DIST=${TEX_DIST//\//\\\/}
STRIP_PATH=${STRIP_PATH//\//\\\/}

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
if [[ -n $TEX_DIST ]]; then
    DIST_FILES='{
        changed += gsub(/\s*[<{]?('"${TEX_DIST}"')[^<>(){}]*[>}]?\s*/, "")
    }'
fi

# STRIP_PATH: strip path components {{{2
if [[ -n $STRIP_PATH ]]; then
    STRIP_PATH='{ changed += gsub(/'"$STRIP_PATH"'/, "") }'
fi

# EMPTY_GROUPS: remove empty groups "()" {{{2
EMPTY_GROUPS='{
    do {
        n = gsub(/\s*\(\s*\)\s*/, " ")
        if (n) {
            merge_space()
            changed = 1
        }
    } while (n)
}'

# PDF_DEST: remove pdfTeX warning of non-existing link target {{{2
# (happens e.g. when compiling only individual chapters with references to other chapters)
if [[ $PDF_DEST == 1 ]]; then
    PDF_DEST='{
        changed += gsub(/pdfTeX warning \(dest\):.*has been referenced but does not exist, replaced by a fixed one/, "")
    }'
fi

# FILTER_GRAPHICS: reduce the amount of listing included graphic files {{{2
# Each included graphic is usually mentioned three times: time of first reference (loading), once for each actual reference, and once for every actual float placement
# The first loading of images has the form <path/to/image.pdf, id=42, 217.3pt x 200.61pt>
# Every reference (\includegraphics) has the form <use path/to/image.pdf>
# When the figure float is placed on page 13, the page is printed as [13 <path/to/image.pdf>]

# Different strategies may be used to reduce the output, depending on the user's preferences
# loading: only print first loading
# reference: only print references
# combined: print first loading, and any subsequent references (thus, image size is printed, which may be useful for debugging graphics)
# placement: only show placements
# none: filter all
# all: filter none

graphics_regex_load='<[^,>]+, id=[0-9]+, [0-9.]+pt x [0-9.]+pt>'
graphics_regex_reference='<use [^>]+>'
graphics_regex_place='<[^>]+>'
graphics_regex_pathfile='([^,>]*\/)?([^\/,>]+)'

FILTER_GRAPHICS='{ n = 0'$'\n'

for g in ${GRAPHICS//,/ }; do
    case $g in
        load*) FILTER_GRAPHICS+='n += gsub(/'"$graphics_regex_load"'/, "")'$'\n';;
         ref*) FILTER_GRAPHICS+='n += gsub(/'"$graphics_regex_reference"'/, "")'$'\n';;
        plac*) FILTER_GRAPHICS+='
                # TODO: extract all [page ...] blocks and, for each, remove every $graphics_regex_place
                # this should ensure that any other hints are not removed
                $0 = gensub(/\[([0-9]+)(\s*'"$graphics_regex_place"'\s*)+\]/, "[\\1]", "g")
            ';;
        comb*) FILTER_GRAPHICS+='
                # exploit the fact that every loading is immediately followed by a reference
                # thus, replace <load> <reference> by <load>, leave the remaining references as-is
                $0 = gensub(/('"$graphics_regex_load"')\s*'"$graphics_regex_reference"'/, "\\1", "g")
            ';;
        path) FILTER_GRAPHICS+='
                $0 = gensub(/<'"$graphics_regex_pathfile"', id=/, "<\\2, id=", "g")
                $0 = gensub(/<use '"$graphics_regex_pathfile"'>/, "<use \\2>", "g")
                # TODO multiple graphics on one page
                $0 = gensub(/\[([0-9]+) <'"$graphics_regex_pathfile"'>\]/, "[\\1 <\\3>]", "g")
            ';;
        *) error "Invalid value of \$GRAPHICS: $GRAPHICS" 2
    esac
done

FILTER_GRAPHICS+='
        if (n) {
            merge_space()
            changed = 1
        }
    }'

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
if [[ $COLOR -eq 1 ]]; then
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
function merge_space() {
    gsub(/\s+/, " ") # merge multiple spaces
    gsub(/^\s/, "") # trim
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
    -e " $STRIP_PATH" \
    -e " $EMPTY_GROUPS" \
    -e " $PDF_DEST" \
    -e " $FILTER_GRAPHICS" \
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
