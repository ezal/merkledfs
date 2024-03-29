open Merkle_tree
open Util

(* Note: There is no need to use Lwt, except for sharing code with the
   server. *)

let connect addr_arg =
  let inet_addr, port =
    match addr_arg with
    | Some (ip, port) ->
        let ip = Ipaddr.to_string ip in
        (Unix.inet_addr_of_string ip, port)
    | None -> (Unix.inet_addr_of_string "127.0.0.1", default_port)
  in
  let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  let* () = Lwt_unix.connect socket (Unix.ADDR_INET (inet_addr, port)) in
  Lwt.return socket

let bytes_of_char c =
  let b = Bytes.create 1 in
  Bytes.set b 0 c ;
  b

let root_hash_filename = "_root_hash"

(* To protect against (inadvertently or maliciously) sending another file from
   the stored set than the requested one, hash the file index along with the file
   itself. *)
let merkle_tree_of_files files =
  List.mapi (fun i -> hash_of_indexed_file (i + 1)) files |> Tree.of_hash_list

(* Precondition: at least one file *)
let send_files socket files =
  let num_files = List.length files in
  let* () = send_int32 "number of files" socket (Int32.of_int num_files) in
  Format.printf "Sent request to upload %d files.@." num_files ;
  let* (_ : int) =
    Lwt_list.fold_left_s
      (fun i file ->
        let* () = send_bytes ("file_" ^ string_of_int i) socket file in
        Lwt.return (i + 1))
      1
      files
  in
  let+ bytes = recv_bytes_with_length "root hash" socket ~length:Hash.size in
  Format.printf "Received root hash.@." ;
  let root_hash =
    files |> merkle_tree_of_files |> Tree.root_hash |> Hash.to_bytes
  in
  if Bytes.equal bytes root_hash then (
    Format.printf "Same root hash. We continue.@." ;
    let* () = write_file root_hash_filename root_hash in
    Lwt.return_ok ())
  else (
    Format.printf "Different root hashes! Aborting.@." ;
    Lwt.return_ok ())

(* Select only regular files from the given directory *)
let files_in_dir dir =
  let filter_regular_files file =
    let path = Filename.concat dir file in
    match Unix.lstat path with
    | {Unix.st_kind = Unix.S_REG; _} -> Some path
    | _ -> None
  in
  Sys.readdir dir |> Array.to_list |> List.filter_map filter_regular_files

let run_upload address_arg dir =
  let* dir_exists = Lwt_unix.file_exists dir in
  if not dir_exists then (
    Format.printf "Directory %s does not exist.@." dir ;
    Lwt.return_ok ())
  else
    let file_paths = files_in_dir dir in
    if file_paths = [] then (
      Format.printf
        "No files to upload. Directory %s contains no regular files.@."
        dir ;
      Lwt.return_ok ())
    else
      let* socket = connect address_arg in
      let tag = op_tag Upload |> bytes_of_char in
      let* () = send_bytes_with_length "upload tag" socket tag ~length:1 in
      (* We only do this for UX reasons, to make clear what the association
         between indexes and files names is. This association should be made
         explicit, for instance by keeping it an a json file. *)
      let file_paths = List.sort String.compare file_paths in
      let* contents = Lwt_list.map_s (fun path -> read_file path) file_paths in
      let* _res = send_files socket contents in
      Format.printf "Sent files.@." ;
      let* _tag_for_ok =
        recv_bytes_with_length "tag for closing" socket ~length:1
      in
      Format.printf "Received upload ack from server.@." ;
      (* delete files *)
      let* () = Lwt_list.iter_p Lwt_unix.unlink file_paths in
      Format.printf "Deleted files.@." ;
      let* () = Lwt_unix.close socket in
      Lwt.return_ok ()

let run_retrieve address_arg file_index file_path =
  let* socket = connect address_arg in
  let tag = op_tag Retrieve |> bytes_of_char in
  let* () = send_bytes_with_length "retrieve tag" socket tag ~length:1 in
  let* () = send_int32 "file index" socket (Int32.of_int file_index) in
  Format.printf "Sent retrieve request for file with index %d.@." file_index ;
  let+ file_contents = recv_bytes "file contents" socket in
  Format.printf "Received file.@." ;
  let hash = hash_of_indexed_file file_index file_contents in
  let* root_hash_bytes = read_file root_hash_filename in
  let root_hash = Hash.of_bytes root_hash_bytes in
  let+ proof_bytes = recv_bytes "Merkle proof" socket in
  Format.printf "Received Merkle proof.@." ;
  let proof =
    Data_encoding.Binary.of_bytes_exn Tree.Proof.encoding proof_bytes
  in
  let valid = Tree.Proof.verify proof ~root:root_hash ~leaf:hash in
  let* () =
    if valid then (
      Format.printf "The Merkle proof is valid.@." ;
      let* () = write_file file_path file_contents in
      Format.printf "Saved file %s.@." file_path ;
      Lwt.return_unit)
    else (
      Format.printf
        "Invalid Merkle proof for index %d (hash %s).@."
        file_index
        (Hash.to_hex hash) ;
      Lwt.return_unit)
  in
  let* () = Lwt_unix.close socket in
  Lwt.return_ok ()

let wrap run_promise =
  let* res = run_promise in
  Lwt.return
  @@
  match res with
  | Ok () -> `Ok ()
  | Error _ -> `Error (false, "There were errors.")

let () =
  let run_upload addr dir = Lwt_main.run @@ wrap @@ run_upload addr dir in
  let run_retrieve addr idx path =
    Lwt_main.run @@ wrap @@ run_retrieve addr idx path
  in
  let cmds = Cli.make ~run_upload ~run_retrieve in
  exit @@ Cmdliner.Cmd.eval cmds
