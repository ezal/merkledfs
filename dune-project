(lang dune 3.14)

(name merkledfs)

(source
  (github ezal/merkledfs))

(authors "ezal <eugen.zalinescu@gmail.com")

(maintainers "ezal <eugen.zalinescu@gmail.com")

(package
  (name merkledfs)
  (synopsis "A Merkle tree-based file storing server")
  (description "A very simple Merkle tree-based file storing server")
  (depends
    data-encoding
    cmdliner
    ipaddr
    lwt)
  (allow_empty))

(generate_opam_files)
