let bind o f =
  match o with
  | Some x  -> f x
  | None    -> None

let ( >>= ) o f = bind o f
let (let*) x f = bind x f

let rec range a b =
  if a >= b then []
  else a::(range (a+1) b)

let (--) a b = range a b

let uniq_cons x xs = if List.mem x xs then xs else x :: xs
let remove_from_right xs = List.fold_right uniq_cons xs []

let split_4 l = 
  let rec split_4_aux al bl cl dl = function
    | (a,b,c,d)::tl -> split_4_aux (a::al) (b::bl) (c::cl) (d::dl) tl
    | [] -> al, bl, cl, dl
  in
  split_4_aux [] [] [] [] l
