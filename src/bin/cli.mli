type address = Ipaddr.t * int

(** [make ~run] attaches a callback to each command. *)
val make :
  run_upload:(address option -> string -> unit Cmdliner.Term.ret) ->
  run_retrieve:(address option -> int -> string -> unit Cmdliner.Term.ret) ->
  unit Cmdliner.Cmd.t
