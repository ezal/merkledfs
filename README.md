# merkledfs: a Merkle tree-backed file storage

## Build and Usage

Clone the repo and then go in the project's root directory.

Build the docker images:
```
docker build -t merkledfs-client-image -f client.Dockerfile .
```
```
docker build -t merkledfs-server-image -f server.Dockerfile .
```

To start the server, run:
```
docker run -p <port>:4321 merkledfs-server-image
```

The server's listening port must be 4321.

To run the client, use:
```
docker run merkledfs-client-image ./client.exe upload [--endpoint <ip:port>] <dir>
# or
docker run merkledfs-client-image ./client.exe retrieve [--endpoint <ip:port>] <file_index> <file_path>
```

The first command uploads the files in a given directory to the server. The
Merkle root of the hashes of the files (and their indexes) is checked and
stored. The files are ordered alphabetically/lexicographically.

The second command retrieves a file with the given index from the server. The
file is checked for consistency by verifying its Merkle proof.

More details on using the client can be obtained with:
```
./client.exe --help
./client.exe upload --help
./client.exe retrieve --help
```

### Demo

To run the demo:
```
docker run merkledfs-client-image scripts/test.sh <ip> <port> <num_files>
```
The ip should that of the host machine, and the port should be the host port, that is, it should match the one given
when running the server container.

Here is a sample output, on the client side:
```
$ docker run merkledfs-client-image scripts/test.sh 192.168.1.32 4000 100000
Generate the directory 'test' with 100000 files.

> ls -1 test | head
000001
000002
000003
000004
000005
000006
000007
000008
000009
000010

> find test -regex 'test/0\+42' -exec cat {} \;
42

> _build/default/src/bin/client.exe upload --endpoint=192.168.1.32:4000 test
Sent request to upload 100000 files.
Received root hash.
Same root hash. We continue.
Sent files.
Received upload ack from server.
Deleted files.

> ls -l test
0

> _build/default/src/bin/client.exe retrieve --endpoint=192.168.1.32:4000 1 file1
Sent retrieve request for file with index 1.
Received file.
Received Merkle proof.
The Merkle proof is valid.
Saved file file1.

> cat file1
1

> _build/default/src/bin/client.exe retrieve --endpoint=192.168.1.32:4000 100000 file100000
Sent retrieve request for file with index 100000.
Received file.
Received Merkle proof.
The Merkle proof is valid.
Saved file file100000.

> cat file100000
100000

> _build/default/src/bin/client.exe retrieve --endpoint=192.168.1.32:4000 42 file42
Sent retrieve request for file with index 42.
Received file.
Received Merkle proof.
The Merkle proof is valid.
Saved file file42.

> cat file42
42
```

And on the server side:
```
$ docker run --name server-container -p 4000:4321 merkledfs-server
New connection!
Received request to upload ...
  ... 100000 files.
Received 100000 files.
Sent root hash.
Stored Merkle tree.
Stored the uploaded files.
Sent closing flag.

New connection!
Received retrieve request for file with index 1.
Sent file.
Sent Merkle proof.

New connection!
Received retrieve request for file with index 100000.
Sent file.
Sent Merkle proof.

New connection!
Received retrieve request for file with index 42.
Sent file.
Sent Merkle proof.
```

## Project structure

* `scripts/` contains two shell scripts used for the demo and for testing:
  - `gen_test_dir.sh` generates a given number of files in a given directory
  - `test.sh` sets up the test (using the previous script) and emit several requests to the server
* `src/` contains the implementation:
  - `lib_merkle_tree/` contains two OCaml modules:
     - `Hash`, based on MD5, provides the hashing algorithm
     - `Tree` implements Merkle trees and proofs
  - `bin/` contains the client and server implementation:
     - `Cli` provides the CLI for the client
     - `Util` provides utilities used by both the client and the server
     - `Client` implements the client
     - `Server` implements the client

How the client and server work can be deduced from the sampled output above.

## Limitations and next steps

(The distinction between the two categories is shallow.)

Limitations:

* The server supports only one upload request. Concurrent upload and retrieval
  is also not supported. However, concurrent retrievals are supported.

* The server's listening port is hard-coded.

Next steps:

* Add proper error handling. Also, the client and the server would report errors
  to each other.

* Add proper logging.

* Test more thoroughly.

* Use a more secure hashing algorithm, like SHA2.

* Clients identify themselves using user ids. The server maintains then a store
  and Merkle tree for each user. The same user can then upload files several
  times and the Merkle tree would be updated accordingly.

* The client could remember the names (and paths) of the uploaded file, to
  properly restore files after retrieval.

* Some operations can be done in parallel (like saving the Merkle tree, the
  received files, and sending the root hash).

## Other remarks

Fixed bugs detected during testing:

* Initially, the hashes in the Merkle tree leafs represented the digests of the
  file contents alone. However, in this way, the server may (inadvertently or
  maliciously) send another file from the stored set than the requested one. To
  solve this issue, we hash the file index along with the file itself.

* The server did not send an acknowledgment to the client that it finished
  saving the files. The client therefore exited immediately after having sent
  the files. A subsequent retrieval request was then processed by the server
  before files were stored on disk and resulted in a server error. This issue
  was partially solved by having the client wait for an acknowledgment from the
  server. However, the server should be hardened so that it does not process a
  retrieval request before finishing processing an upload request.
