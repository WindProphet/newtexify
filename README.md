# newtexify

Command line tool for rendering tex file and also preview.

## Usage

```
Usage newtexify.rb [options] [file]

    -e, --engine [ENGINE]            Choose TeX type engine
                                     default engine is XeLaTeX

    -t, --type [TYPE]                Select output type
                                     default output type is PDF

    -1, --[no-]onetime               only compile onetime
    -b, --[no-]bibtex                use BibTeX
    -m, --main FILE                  set main TeX file
    -M, --makefile [option]          run make before compiling
    -c, --[no-]clean                 clean cache
    -o, --output FILE                set output filename
    -p, --preview                    show preview
        --[no-]shell-escape          disable/enable \write18{SHELL COMMAND}
    -d, --dir DIR
    -h, --help                       Prints this help
```

