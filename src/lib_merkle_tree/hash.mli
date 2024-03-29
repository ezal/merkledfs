type t

val encoding : t Data_encoding.t

val equal : t -> t -> bool

val size : int

val hash_string : string -> t

val hash_bytes : bytes -> t

val pair : t -> t -> t

val to_hex : t -> string

val from_hex : string -> t

val to_bytes : t -> bytes

val of_bytes : bytes -> t

val to_string : t -> string
