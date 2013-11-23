#!/bin/bash
file=${1%.txt}
pandoc -fmarkdown $1.txt -o $1.html \
   --table-of-contents \
   --include-in-header=style.css
