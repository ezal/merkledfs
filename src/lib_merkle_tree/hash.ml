include Digest

let encoding = Data_encoding.string

let size = 16

let hash_string = string

let hash_bytes = bytes

let pair str1 str2 = str1 ^ str2 |> Digest.string

let to_string t = t

let to_bytes t = Bytes.of_string t

let of_bytes t = Bytes.to_string t
