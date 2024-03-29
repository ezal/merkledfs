#!/bin/bash

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <server_ip> <server_port> <number_of_files_to_upload>"
    exit 1
fi

ip="$1"
port="$2"
num_files="$3"
client=_build/default/src/bin/client.exe

echo "Generate the directory 'test' with $num_files files."
scripts/gen_test_dir.sh test $num_files

echo -e "\n> ls -1 test | head"
ls -1 test | head

echo -e "\n> find test -regex 'test/0\+42' -exec cat {} \;"
find test -regex 'test/0\+42' -exec cat {} \;

# test uploading
echo -e "\n> $client upload --endpoint=$ip:$port test"
$client upload --endpoint="$ip:$port" test

echo -e "\n> ls -l test"
ls -1 test | wc -l

# test retrieval
echo -e "\n> $client retrieve --endpoint=$ip:$port 1 file1"
$client retrieve --endpoint="$ip:$port" 1 file1

echo -e "\n> cat file1"
cat file1

echo -e "\n> $client retrieve --endpoint=$ip:$port $num_files file$num_files"
$client retrieve --endpoint="$ip:$port" $num_files file$num_files

echo -e "\n> cat file$num_files"
cat file$num_files

echo -e "\n> $client retrieve --endpoint=$ip:$port 42 file42"
$client retrieve --endpoint="$ip:$port" 42 file42

echo -e "\n> cat file42"
cat file42
