let bind o f =
  match o with
  | Some x  -> f x
  | None    -> None

let ( >>= ) o f = bind o f
let (let*) x f = bind x f