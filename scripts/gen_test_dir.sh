#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <dir> <number_of_files>"
    exit 1
fi

dir="$1"
mkdir -p "$dir"

num_files="$2"

for ((i=1; i<=num_files; i++)); do
    num_digits=${#num_files}
    printf -v filename "%0${num_digits}d" "$i"
    echo "$i" > "$dir/$filename"
done
