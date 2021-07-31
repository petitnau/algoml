include Typecheck
open Types
open Batteries

let has_duplicates (l:'a list) : bool =
  let rec has_duplicates_aux ll rl = match rl with
    | hd::tl when (List.mem hd ll) || (List.mem hd tl) -> true
    | hd::tl -> has_duplicates_aux (hd::ll) tl
    | [] -> false
  in has_duplicates_aux [] l

let rec list_of_optlist (l:'a option list) : 'a list = match l with
  | (Some hd)::tl -> hd::(list_of_optlist tl)
  | None::tl -> (list_of_optlist tl)
  | [] -> [] 

let get_clause_oncomplete (o:clause) : oncomplete option = match o with
  | FunctionClause(onc,_,_,_) -> Some onc
  | _ -> None 

let get_aclause_oncompletes (ao:aclause) : oncomplete list = 
  list_of_optlist (List.map (get_clause_oncomplete) ao)

let get_contract_oncompletes (Contract(_,cl):contract) : oncomplete list = 
  List.fold_right (fun a b -> a@b) (List.map (get_aclause_oncompletes) cl) []

let check_create_in_contract (p:contract) : bool = 
  let oncompletes = get_contract_oncompletes p in
  List.mem Create oncompletes

let check_aclauses_funcclause (Contract(_,cl):contract) : bool = 
  let oncompletes = List.map (get_aclause_oncompletes) cl in
  not (List.mem [] oncompletes)

let check_duplicates (Contract(dl,_):contract) : bool = 
  let get_ides dl = 
    List.map (function Declaration(_,_,_,i) -> i) dl
  in
  let filter_statetype st dl =
    List.filter (function Declaration(st',_,_,_) when st' = st -> true | _ -> false) dl
  in
  let globs = get_ides (filter_statetype TGlob dl) in 
  let locs = get_ides (filter_statetype TLoc dl) in 
  not(has_duplicates globs) && not(has_duplicates locs)
