open Cmdliner

let version = "0.1"

let default_port = 4321

type address = Ipaddr.t * int

let address_pp fmt (ip, port) = Format.fprintf fmt "%a:%d" Ipaddr.pp ip port

let address_arg =
  let decoder str = Ipaddr.with_port_of_string ~default:default_port str in
  Arg.conv (decoder, address_pp)

let address_term =
  let doc =
    Format.sprintf
      "The address of the server. The default ip is '127.0.0.1'. The default \
       port is %d."
      default_port
  in
  Arg.(
    value
    & opt (some address_arg) None
    & info ~docs:"OPTIONS" ~doc ~docv:"IP[:PORT]" ["endpoint"])

module Upload = struct
  let description =
    [
      `S "DESCRIPTION";
      `P
        "Uploads the files in a given directory to the server. The Merkle root \
         of the files' hashes is checked and stored.";
    ]

  let man = description

  let info = Cmd.info ~doc:"Upload files to the server" ~man ~version "upload"

  let dir_term =
    let doc = "Directory from which files will be uploaded" in
    Arg.(required & pos 0 (some dir) None & info [] ~docv:"DIR" ~doc)

  let cmd run = Cmd.v info @@ Term.(ret (const run $ address_term $ dir_term))
end

module Retrieve = struct
  let description =
    [
      `S "DESCRIPTION";
      `P
        "Retrieves a file with the given index from the server. The file is \
         checked for consistency by verifying its Merkle proof.";
    ]

  let man = description

  let info = Cmd.info ~doc:"Retrieve file from server" ~man ~version "retrieve"

  let index_term =
    let doc = "Index of the file to retrieve" in
    Cmdliner.Arg.(required & pos 0 (some int) None & info [] ~docv:"INDEX" ~doc)

  let path_term =
    let doc =
      "Name (with or without path) under which to store the retrieved file"
    in
    Cmdliner.Arg.(
      required & pos 1 (some string) None & info [] ~docv:"FILE_PATH" ~doc)

  let cmd run =
    Cmd.v info @@ Term.(ret (const run $ address_term $ index_term $ path_term))
end

let make ~run_upload ~run_retrieve =
  let default = Cmdliner.Term.(ret (const (`Help (`Pager, None)))) in
  let info =
    Cmd.info
      ~doc:"The client for a simple Merkle tree-based file storage"
      ~version
      "client"
  in
  Cmd.group ~default info [Upload.cmd run_upload; Retrieve.cmd run_retrieve]
