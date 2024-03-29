type node =
  | Leaf of {hash : Hash.t}
  | Node of {hash : Hash.t; left : node; right : node}

let encoding =
  let open Data_encoding in
  mu "t" (fun e ->
      union
        [
          case
            ~title:"leaf"
            (Tag 0)
            Hash.encoding
            (function Leaf {hash} -> Some hash | _ -> None)
            (fun hash -> Leaf {hash});
          case
            ~title:"node"
            (Tag 1)
            (obj3 (req "hash" Hash.encoding) (req "left" e) (req "right" e))
            (function
              | Node {hash; left; right} -> Some (hash, left, right) | _ -> None)
            (fun (hash, left, right) -> Node {hash; left; right});
        ])

let hash_of_node = function Leaf {hash} | Node {hash; _} -> hash

let rec of_node_list = function
  | [] -> invalid_arg "empty list"
  | [x] -> x
  | nodes ->
      let rec build_tree acc = function
        | [] -> acc
        | [node] -> node :: acc
        | n1 :: n2 :: rest ->
            let hash = Hash.pair (hash_of_node n1) (hash_of_node n2) in
            let node = Node {hash; left = n1; right = n2} in
            build_tree (node :: acc) rest
      in
      let nodes = build_tree [] nodes in
      of_node_list nodes

let of_hash_list ?(rev = false) data =
  let map = if rev then List.rev_map else List.map in
  map (fun hash -> Leaf {hash}) data |> of_node_list

let of_string_list ?(rev = false) data =
  let map = if rev then List.rev_map else List.map in
  map (fun str -> Leaf {hash = Hash.hash_string str}) data |> of_node_list

let of_bytes_list ?(rev = false) data =
  let map = if rev then List.rev_map else List.map in
  map (fun d -> Leaf {hash = Hash.hash_bytes d}) data |> of_node_list

let pp fmt node =
  let rec pp_aux node depth =
    match node with
    | Leaf {hash} ->
        Format.fprintf
          fmt
          "%sLeaf: %s\n"
          (String.make (depth * 2) ' ')
          (Hash.to_hex hash)
    | Node {hash; left; right} ->
        Format.fprintf
          fmt
          "%sNode: %s\n"
          (String.make (depth * 2) ' ')
          (Hash.to_hex hash) ;
        pp_aux left (depth + 1) ;
        pp_aux right (depth + 1)
  in
  pp_aux node 0

type t = node

let root_hash = hash_of_node

module Proof = struct
  type sibling_kind = Left | Right

  (** A proof is a list that represents a path in the Merkle tree from the root to
    a leaf. The path is given indirectly, by providing the sibling nodes (of the
    one in the paths). At each level of the path, the hash of the sibling node
    is present in the list, together with the sibling kind, that is, whether the
    sibling is a left node or a right node. The head of the list refers to the
    leaf, the tail to the root.*)
  type t = (sibling_kind * Hash.t) list

  let kind_encoding =
    let open Data_encoding in
    union
      ~tag_size:`Uint8
      [
        case
          ~title:"Left"
          (Tag 0)
          unit
          (function Left -> Some () | _ -> None)
          (fun () -> Left);
        case
          ~title:"Right"
          (Tag 1)
          unit
          (function Right -> Some () | _ -> None)
          (fun () -> Right);
      ]

  let encoding =
    let open Data_encoding in
    list @@ obj2 (req "kind" kind_encoding) (req "hash" Hash.encoding)

  let pp =
    Format.pp_print_list
      ~pp_sep:(fun fmt () -> Format.fprintf fmt "; ")
      (fun fmt (kind, hash) ->
        Format.fprintf
          fmt
          "(%s,%s)"
          (match kind with Left -> "L" | Right -> "R")
          (Hash.to_hex hash))

  let rec generate t leaf_hash =
    match t with
    | Leaf {hash} -> if Hash.equal hash leaf_hash then Some [] else None
    | Node {hash = _; left; right} -> (
        match generate left leaf_hash with
        | Some proof -> Some ((Right, hash_of_node right) :: proof)
        | None -> (
            match generate right leaf_hash with
            | Some proof -> Some ((Left, hash_of_node left) :: proof)
            | None -> None))

  (* Note: to ensure the proof is not too large, the verifier should have the root
     and the maximum depth in the tree. *)
  let verify proof ~root ~leaf =
    let computed_root =
      List.fold_left
        (fun node (kind, sibling_node) ->
          match kind with
          | Left -> Hash.pair sibling_node node
          | Right -> Hash.pair node sibling_node)
        leaf
        (List.rev proof)
    in
    Hash.equal root computed_root
end
