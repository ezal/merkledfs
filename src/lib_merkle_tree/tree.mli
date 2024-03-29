type node

type t = node

val encoding : t Data_encoding.t

(** Get the root hash of the given Merkle tree. *)
val root_hash : t -> Hash.t

(** Build a Merkle tree from a list of hashes. *)
val of_hash_list : ?rev:bool -> Hash.t list -> t

(** Build a Merkle tree from a list of strings. *)
val of_string_list : ?rev:bool -> string list -> t

(** Build a Merkle tree from a list of bytes. *)
val of_bytes_list : ?rev:bool -> bytes list -> t

(** Pretty-print tree. *)
val pp : Format.formatter -> t -> unit

(** Merkle proofs *)
module Proof : sig
  type t

  val encoding : t Data_encoding.t

  (** Pretty-print proof. *)
  val pp : Format.formatter -> t -> unit

  (** Generate the proof the given hash is part of the given Merkle tree. Return
    [None] if that is not the case. *)
  val generate : node -> Hash.t -> t option

  (** Check the validity of the given proof, which states that [leaf] hash is
      part of the Merkle tree with the given [root] hash. *)
  val verify : t -> root:Hash.t -> leaf:Hash.t -> bool
end
