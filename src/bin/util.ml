let default_port = 4321

type op = Upload | Retrieve

let upload_tag = '\001'

let retrieve_tag = '\002'

let op_tag = function Upload -> upload_tag | Retrieve -> retrieve_tag

let op_tag_of_char c =
  if c = upload_tag then Some Upload
  else if c = retrieve_tag then Some Retrieve
  else None

let ( let* ) = Lwt.bind

let read_file filename =
  Lwt_io.with_file ~mode:Lwt_io.input filename (fun ic ->
      let* file_size = Lwt_io.length ic in
      let file_size = Int64.to_int file_size in
      let buffer = Bytes.create file_size in
      let* () = Lwt_io.read_into_exactly ic buffer 0 file_size in
      Lwt.return buffer)

let write_file filename bytes =
  Lwt_io.with_file ~mode:Lwt_io.output filename (fun oc ->
      Lwt_io.write oc (Bytes.to_string bytes))

type error = Read_error of string

(* A variant of [Lwt_result.bind]. The notation is non-standard. *)
let ( let+ ) = Lwt_result.bind

(* awful! *)
let debug = false

let log_debug =
  if debug then Format.printf
  else
    let null_formatter =
      Format.make_formatter (fun _ _ _ -> ()) (fun () -> ())
    in
    Format.fprintf null_formatter

(* Receive a given number of bytes. Note that the name may be confusing; to be
   renamed (and similarly for the other functions). *)
let recv_bytes_with_length msg fd ~length =
  let buffer = Bytes.create length in
  let* bytes_read = Lwt_unix.read fd buffer 0 length in
  log_debug "recv: [%s] received %d bytes out of %d@." msg bytes_read length ;
  if bytes_read < length then
    (* end of input or unexpected input *)
    Lwt.return (Error (Read_error msg))
  else Lwt.return (Ok buffer)

let send_bytes_with_length msg fd bytes ~length =
  let* bytes_written = Lwt_unix.write fd bytes 0 length in
  log_debug "send: [%s] sent %d bytes out of %d@." msg bytes_written length ;
  Lwt.return_unit

let recv_int32 msg fd =
  let+ bytes = recv_bytes_with_length msg fd ~length:4 in
  let n = Bytes.get_int32_be bytes 0 |> Int32.to_int in
  Lwt.return_ok n

let int32_to_bytes n =
  let bytes = Bytes.create 4 in
  Bytes.set_int32_be bytes 0 n ;
  bytes

let send_int32 msg fd n =
  let buffer = int32_to_bytes n in
  send_bytes_with_length msg fd buffer ~length:4

let recv_bytes msg fd =
  let+ length = recv_int32 (msg ^ " length") fd in
  recv_bytes_with_length msg fd ~length

let send_bytes msg fd bytes =
  let length = Bytes.length bytes in
  let* () = send_int32 (msg ^ " length") fd (Int32.of_int length) in
  send_bytes_with_length msg fd bytes ~length

let hash_of_indexed_file index file =
  let open Merkle_tree.Hash in
  let hash_idx = int32_to_bytes (Int32.of_int index) |> hash_bytes in
  let hash_file = hash_bytes file in
  pair hash_idx hash_file
