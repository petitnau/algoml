include Typecheck
open Types
open Batteries

module Ide_set = Set.Make (struct
                             type t = ide
                             let compare = compare
                           end);;
(* let set_of_list = List.fold_left (fun acc x -> Ide_set.add x acc) Ide_set.empty;; *)
let list_intersection l1 l2 = 
  let s1 = Ide_set.of_list l1 in
  let s2 = Ide_set.of_list l2 in
  Ide_set.elements (Ide_set.inter s1 s2)

let clause_filter_map (f: clause -> 'a option) (aol: aclause list) =
  List.map (fun ao -> List.filter_map f ao) aol

let rem_duplicates (l:'a list) : 'a list =
  let rec rem_duplicates_aux ll rl = match rl with
    | hd::tl when (List.mem hd ll) -> rem_duplicates_aux ll tl
    | hd::tl -> rem_duplicates_aux (hd::ll) tl
    | [] -> ll
  in rem_duplicates_aux [] l

let has_duplicates (l:'a list) : bool =
  List.length l <> List.length (rem_duplicates l)

let get_contract_oncompletes (Contract(_,cl):contract) : oncomplete list list = 
  clause_filter_map (function FunctionClause(onc,_,_,_) -> Some onc | _ -> None) cl

let check_create_in_contract (p:contract) : bool = 
  let oncompletes = get_contract_oncompletes p in
  (List.length (List.filter (fun onc -> onc = Create) (List.flatten oncompletes))) = 1

let check_aclauses_funcclause (p:contract) : bool = 
  List.for_all (fun e -> List.length e = 1) (get_contract_oncompletes p)

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

let get_contract_transitions (Contract(_,cl):contract) : (statetype * ide option * ide option) list = 
   List.flatten (clause_filter_map (function StateClause(s,sfr,sto) -> Some(s,sfr,sto) | _ -> None) cl)

let check_reachable_states (p:contract) : bool = 
  let rec initial_states l = match l with
    | (None, Some(sto))::tl -> sto::(initial_states tl)
    | _::tl -> initial_states tl
    | [] -> []
  in
  let rec all_states l = match l with
    | (Some(sfr), Some(sto))::tl -> sfr::sto::(all_states tl)
    | (None, Some(sto))::tl -> sto::(all_states tl)
    | (Some(sfr), None)::tl -> sfr::(all_states tl)
    | _::tl -> all_states tl
    | [] -> []
  in
  let eps_delta transitions initial = 
    let rec eps_delta_aux initial transitions = match transitions with
      | (Some sfr, Some sto)::tl when initial = sfr -> sto::(eps_delta_aux initial tl)
      | (None, Some sto)::tl -> sto::(eps_delta_aux initial tl)
      | (Some sfr, None)::tl when initial = sfr -> sfr::(eps_delta_aux initial tl)
      | (None, None)::tl -> initial::(eps_delta_aux initial tl)
      | _::tl -> eps_delta_aux initial tl
      | [] -> []
    in rem_duplicates (initial::(eps_delta_aux initial transitions))
  in
  let rec visit initials transitions = 
    let new_initials = rem_duplicates (List.flatten (List.map (eps_delta transitions) initials)) in
    if List.length initials = List.length new_initials then new_initials
    else visit new_initials transitions 
  in 
  let check_reachable_statetype stype = 
    let transitions = List.filter_map (fun (stype',sfr,sto) -> if stype' = stype then Some(sfr,sto) else None) (get_contract_transitions p) in
    let states = rem_duplicates (all_states transitions) in
    let initials = rem_duplicates (initial_states transitions) in
    let visited = visit initials transitions in 
    List.length visited = List.length states
  in
  check_reachable_statetype TGlob && check_reachable_statetype TLoc

(* 
let get_create_block (Contract(_,cl):contract) : cmd list = 
  List.flatten (List.flatten (clause_filter_map (function FunctionClause(Create,_,_,cl) -> Some cl | _ -> None ) cl))

let check_double_immutable (p:contract) =
  let Contract(_,cl) = p in
  let rec get_all_assignments = function
    | Assign(GlobVar(i),_)::tl -> i::(get_all_assignments tl)
    | Ifte(_,cl1,cl2)::tl -> (get_all_assignments cl1)@(get_all_assignments cl2)@(get_all_assignments tl)
    | _:: tl -> get_all_assignments tl
    | [] -> []
  in
  let rec get_sure_assignments = function
    | Assign(GlobVar(i),_)::tl -> i::(get_sure_assignments tl)
    | Ifte(_,cl1,cl2)::tl -> (list_intersection (get_sure_assignments cl1) (get_sure_assignments cl2))@(get_sure_assignments tl)
    | _::tl -> get_sure_assignments tl
    | [] -> []
  in
  let check_duplicates cl1 cl2 =
    List.length (list_intersection cl1 cl2) = 0
  in
  let create_block = get_create_block p in 
  let non_create_cmd_list = 
    List.flatten (List.flatten (clause_filter_map (function FunctionClause(onc,_,_,cl) when onc <> Create -> Some cl | _ -> None) cl)) in
  true || check_duplicates (get_sure_assignments create_block) (get_all_assignments non_create_cmd_list) *)
