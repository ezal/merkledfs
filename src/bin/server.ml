open Merkle_tree
open Util

let merkle_tree_file = "_merkle_tree"

let store_dir = "_store"

let read_files socket max_iter =
  let rec iter i acc =
    if i > max_iter then Lwt.return_ok acc
    else
      let msg = "file_" ^ string_of_int i in
      let+ bytes = recv_bytes msg socket in
      iter (i + 1) (bytes :: acc)
  in
  iter 1 []

(* Similar to [Client.merkle_tree_of_files].
   Note: the file list is in reverse wrt to how the client sent it. *)
let merkle_tree_of_files ~number_of_files files =
  let _0, hash_list =
    List.fold_left
      (fun (i, acc) file ->
        let hash = hash_of_indexed_file i file in
        (i - 1, hash :: acc))
      (number_of_files, [])
      files
  in
  (* Due to the accumulation in [fold_left], the hash list is now again in the
     client order. *)
  Tree.of_hash_list hash_list

let handle_upload_request socket =
  Format.printf "Received request to upload ...@." ;
  let number_of_stored_files = Sys.readdir store_dir |> Array.length in
  if number_of_stored_files > 0 then (
    Format.printf
      "The store is non-empty. The server does support several upload \
       requests.@." ;
    Lwt.return_ok ())
  else
    let+ number_of_files = recv_int32 "number of files" socket in
    Format.printf "  ... %d files.@." number_of_files ;
    if number_of_files < 1 then (
      Format.printf
        "The number of files should be positive (got %d).@."
        number_of_files ;
      Lwt.return_ok ())
    else
      let+ files = read_files socket number_of_files in
      Format.printf "Received %d files.@." (List.length files) ;
      (* Three independent actions, which can be done in parallel:
         1. send the root hash
         2. save the Merkle tree
         3. save the received files *)
      let merkle_tree = merkle_tree_of_files ~number_of_files files in
      let root_hash = Tree.root_hash merkle_tree |> Hash.to_bytes in
      let* () =
        send_bytes_with_length "root hash" socket root_hash ~length:Hash.size
      in
      Format.printf "Sent root hash.@." ;
      let merkle_tree_bytes =
        Data_encoding.Binary.to_bytes_exn Tree.encoding merkle_tree
      in
      let* () = write_file merkle_tree_file merkle_tree_bytes in
      Format.printf "Stored Merkle tree.@." ;
      let* (_ : int) =
        Lwt_list.fold_left_s
          (fun i file ->
            let path = Filename.concat store_dir (string_of_int i) in
            let* () = write_file path file in
            Lwt.return (i - 1))
          number_of_files
          files
      in
      Format.printf "Stored the uploaded files.@." ;
      let* () =
        send_bytes_with_length
          "flag for closing"
          socket
          (Bytes.create 1)
          ~length:1
      in
      Format.printf "Sent closing flag.@." ;
      Lwt_result.return ()

let handle_retrieve_request socket =
  let+ index = recv_int32 "file index" socket in
  Format.printf "Received retrieve request for file with index %d.@." index ;
  let number_of_stored_files = Sys.readdir store_dir |> Array.length in
  if number_of_stored_files = 0 then (
    Format.printf "No file stored.@." ;
    Lwt.return_ok ())
  else if index < 1 || index > number_of_stored_files then (
    Format.printf
      "Invalid file index %d. Expecting a number between 1 and %d.@."
      index
      number_of_stored_files ;
    Lwt.return_ok ())
  else
    let path = Filename.concat store_dir (string_of_int index) in
    let* contents = read_file path in
    let* () = send_bytes "file contents" socket contents in
    Format.printf "Sent file.@." ;
    let* merkle_tree_bytes = read_file merkle_tree_file in
    let merkle_tree =
      Data_encoding.Binary.of_bytes_exn Tree.encoding merkle_tree_bytes
    in
    let hash = hash_of_indexed_file index contents in
    let proof_opt = Tree.Proof.generate merkle_tree hash in
    match proof_opt with
    | None ->
        Format.printf
          "Unable to generate the Merkle proof for the file with index %d.@."
          index ;
        Lwt.return_ok ()
    | Some proof ->
        let proof =
          Data_encoding.Binary.to_bytes_exn Tree.Proof.encoding proof
        in
        let* () = send_bytes "proof" socket proof in
        Format.printf "Sent Merkle proof.@." ;
        Lwt.return_ok ()

let handle_connection socket =
  let+ tag_byte = recv_bytes_with_length "tag" socket ~length:1 in
  let tag = Bytes.get tag_byte 0 |> op_tag_of_char in
  match tag with
  | Some Upload -> handle_upload_request socket
  | Some Retrieve -> handle_retrieve_request socket
  | None ->
      Format.printf "Unknown request.@." ;
      Lwt_result.return ()

let run_server (port : int) : unit Lwt.t =
  let* dir_exists = Lwt_unix.file_exists store_dir in
  let* () =
    if not dir_exists then Lwt_unix.mkdir store_dir 0o755 else Lwt.return ()
  in
  let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  let* () = Lwt_unix.bind socket (Unix.ADDR_INET (Unix.inet_addr_any, port)) in
  let max_pending_connections = 10 in
  Lwt_unix.listen socket max_pending_connections ;
  let rec accept_connections () =
    let* client_socket, _ = Lwt_unix.accept socket in
    Format.printf "New connection!@." ;
    (* handle each connection concurrently *)
    Lwt.async (fun () ->
        let* _res = handle_connection client_socket in
        Format.printf "@." ;
        Lwt_unix.close client_socket) ;
    accept_connections ()
  in
  accept_connections ()

let () = Lwt_main.run (run_server default_port)
