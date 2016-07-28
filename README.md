latex-output-beautifier is a small set of routines that filter the verbose output produced by LaTeX.

The intended usage is for those who run LaTeX without external tools (such as latexmk) and want to see the console output of LaTeX, but get distracted by the loads of messages.
This tool filters most of the rather uninformative messages, and tries to format the informative messages to reduce the visual clutter.


# Usage

```bash
export max_print_line=100000
pdflatex … | filter-latex.sh [options]
```

Use `--help` to see a list of available options.

# Features

* colouring of errors and warnings
* suppress listing of loaded files that are part of your TeX distribution (these can make a large amount of the output, in particular at the beginning and end)
* format the output where it helps reading messages or reflects the structure of the document


# Dependencies

* GNU awk
* bash
