open Types
open General

let get_function_clause (ao:aclause) = 
  List.find (function FunctionClause(_,_,_,_) -> true | _ -> false) ao

let rec any_exp_check fe (e:exp) = 
  let any_exp_check = any_exp_check fe in
  (match fe with Some(fe) -> fe e | None -> false) || (match e with
  | Not(e1) -> (any_exp_check e1)
  | IBop(_,e1,e2) | LBop(_,e1,e2) | CBop(_,e1,e2) -> List.exists any_exp_check [e1;e2]
  | _ -> false) 
let rec any_cmd_check fe fc (c:cmd) =
  let any_exp_check = any_exp_check fe in
  let any_cmd_check = any_cmd_check fe fc in
  (match fc with Some(fc) -> fc c | None -> false) || (match c with
  | Assign(LocVar(_,Some(e1)),e2) -> List.exists any_exp_check [e1;e2]
  | Assign(_,e1) -> any_exp_check e1
  | Ifte(e1,c1,None) -> (any_exp_check e1) || (any_cmd_check c1)
  | Ifte(e1,c1,Some c2) -> (any_exp_check e1) || (any_cmd_check c1) || (any_cmd_check c2)
  | Block(cl) -> List.exists any_cmd_check cl)
let any_pattern_check fe _ fp (p:pattern) =
  let any_exp_check = any_exp_check fe in
  (match fp with Some(fp) -> fp p | None -> false) || (match p with
  | RangePattern(e1,e2,_) ->
      let check1 = (match e1 with Some(e1) -> any_exp_check e1 | None -> false) in
      let check2 = (match e2 with Some(e2) -> any_exp_check e2 | None -> false) in
      check1 || check2
  | FixedPattern(e1,_) -> any_exp_check e1
  | AnyPattern(_) -> false)
let any_clause_check fe fc fp fo (o:clause) = 
  let any_exp_check = any_exp_check fe in
  let any_cmd_check = any_cmd_check fe fc in
  let any_pattern_check = any_pattern_check fe fc fp in
  (match fo with Some(fo) -> fo o | None -> false) || (match o with
  | PayClause(p1,p2,p3,p4) -> List.exists any_pattern_check [p1;p2;p3;p4] 
  | CloseClause(p1,p2,p3) -> List.exists any_pattern_check [p1;p2;p3] 
  | TimestampClause(p1) | RoundClause(p1) | FromClause(p1) -> any_pattern_check p1
  | AssertClause(e1) -> any_exp_check e1
  | FunctionClause(_,_,_,cl) -> List.exists any_cmd_check cl
  | NewtokClause(p1,_,p2) -> List.exists any_pattern_check [p1;p2]
  | StateClause(_,_,_) -> false)
let any_aclause_check fe fc fp fo fao (ao:aclause) = 
  let any_clause_check = any_clause_check fe fc fp fo in
  (match fao with Some(fao) -> fao ao | None -> false) 
  || (List.exists any_clause_check ao)
let any_contract_check fe fc fp fo fao (Contract(_,aol):contract) = 
  let any_aclause_check = any_aclause_check fe fc fp fo fao in
  List.exists (any_aclause_check) aol

let rec map_exp fe (e:exp) = 
  let map_exp = map_exp fe in
  let e = (match fe with Some(fe) -> fe e | None -> e) in
  (match e with
  | Not(e1) -> (map_exp e1)
  | IBop(op,e1,e2) -> IBop(op, map_exp e1, map_exp e2)
  | LBop(op,e1,e2) -> LBop(op, map_exp e1, map_exp e2)
  | CBop(op,e1,e2) -> CBop(op, map_exp e1, map_exp e2)
  | _ -> e) 
let rec map_cmd fe fc (c:cmd) =
  let map_cmd = map_cmd fe fc in
  let map_exp = map_exp fe in
  let c = (match fc with Some(fc) -> fc c | None -> c) in 
  (match c with
  | Assign(LocVar(i,Some(e1)),e2) -> Assign(LocVar(i,Some(map_exp e1)), map_exp e2)
  | Assign(k,e1) -> Assign(k, map_exp e1)
  | Ifte(e1,c1,Some c2) -> Ifte(map_exp e1, map_cmd c1, Some(map_cmd c2))
  | Ifte(e1,c1,None) -> Ifte(map_exp e1, map_cmd c1, None)
  | Block(cl) -> Block(List.map map_cmd cl))
let map_pattern fe _ fp (p:pattern) =
  let map_exp = map_exp fe in
  let p = (match fp with Some(fp) -> fp p | None -> p) in
  (match p with
  | RangePattern(e1,e2,i) ->
      let e1' = (match e1 with Some(e1) -> Some(map_exp e1) | None -> None) in
      let e2' = (match e2 with Some(e2) -> Some(map_exp e2) | None -> None) in
      RangePattern(e1',e2',i)
  | FixedPattern(e1,i) -> FixedPattern(map_exp e1, i)
  | _ -> p)
let map_clause fe fc fp fo (o:clause) = 
  let map_pattern = map_pattern fe fc fp in
  let map_cmd = map_cmd fe fc in
  let map_exp = map_exp fe in
  let o = (match fo with Some(fo) -> fo o | None -> o) in
  (match o with
  | PayClause(p1,p2,p3,p4) -> PayClause(map_pattern p1, map_pattern p2, map_pattern p3, map_pattern p4)
  | CloseClause(p1,p2,p3) -> CloseClause(map_pattern p1, map_pattern p2, map_pattern p3)
  | TimestampClause(p1) -> TimestampClause(map_pattern p1)
  | RoundClause(p1) -> RoundClause(map_pattern p1)
  | FromClause(p1) -> FromClause(map_pattern p1)
  | AssertClause(e1) -> AssertClause(map_exp e1)
  | FunctionClause(onc,fn,pl,cl) -> FunctionClause(onc, fn, pl, List.map map_cmd cl)
  | NewtokClause(amt,i,xto) -> NewtokClause(map_pattern amt, i, map_pattern xto)
  | _ -> o)
let map_aclause fe fc fp fo fao (ao:aclause) = 
  let map_clause = map_clause fe fc fp fo in
  let ao = (match fao with Some(fao) -> fao ao | None -> ao) in
  List.map map_clause ao
let map_contract fe fc fp fo fao (Contract(dl,aol):contract) = 
  Contract(dl, List.map (map_aclause fe fc fp fo fao) aol)

let rec filter_exp fe (e:exp) : exp list = 
  let filter_exp = filter_exp fe in
  let curr_filter = (match fe with Some(fe) when fe e -> Some e | _ -> None) in
  let next_filter_e = (match e with
    | Not(e1) -> (filter_exp e1)
    | IBop(_,e1,e2) | LBop(_,e1,e2) | CBop(_,e1,e2) -> (filter_exp e1)@(filter_exp e2)
    | _ -> []) in
  let filter_e = match curr_filter with Some(curr_filter) -> curr_filter::next_filter_e | None -> next_filter_e in
  filter_e

let rec filter_cmd fe fc (c:cmd) : exp list * cmd list=
  let filter_cmd = filter_cmd fe fc in
  let filter_exp = filter_exp fe in
  let curr_filter = (match fc with Some(fc) when fc c -> Some c | _ -> None) in 
  let filter_e, next_filter_c = (match c with
    | Assign(LocVar(_,Some(e1)),e2) -> 
      let el1 = filter_exp e1 in
      let el2 = filter_exp e2 in
      el1@el2, []
    | Assign(_,e1) -> 
      let el1 = filter_exp e1 in
      el1, []
    | Ifte(e1,c1,c2) -> 
      let el1 = filter_exp e1 in
      let el2, cl1 = filter_cmd c1 in
      let el3, cl2 = (match c2 with Some(c2) -> filter_cmd c2 | None -> [], []) in
      el1@el2@el3, cl1@cl2
    | Block(cl) ->
      let el1, cl1 = List.split (List.map filter_cmd cl) in
      let el1, cl1 = List.flatten el1, List.flatten cl1 in
      el1, cl1) in
  let filter_c = match curr_filter with Some(curr_filter) -> curr_filter::next_filter_c | None -> next_filter_c in
  filter_e, filter_c

let filter_pattern fe _ fp (p:pattern) : exp list * cmd list * pattern list =
  let filter_exp = filter_exp fe in
  let curr_filter = (match fp with Some(fp) when fp p -> Some p | _ -> None) in
  let filter_e, filter_c, next_filter_p = (match p with
    | RangePattern(e1,e2,_) ->
      let el1 = (match e1 with Some(e1) -> filter_exp e1 | None -> []) in
      let el2 = (match e2 with Some(e2) -> filter_exp e2 | None -> []) in
      el1@el2, [], []
    | FixedPattern(e1,_) ->
      let el1 = filter_exp e1 in
      el1, [], []
    | _ -> [],[],[]) in
  let filter_p = match curr_filter with Some(curr_filter) -> curr_filter::next_filter_p | None -> next_filter_p in
  filter_e, filter_c, filter_p

let filter_clause fe fc fp fo (o:clause) : exp list * cmd list * pattern list * clause list = 
  let filter_pattern = filter_pattern fe fc fp in
  let filter_cmd = filter_cmd fe fc in
  let filter_exp = filter_exp fe in
  let curr_filter = (match fo with Some(fo) when fo o -> Some o | _ -> None) in
  let filter_e, filter_c, filter_p, next_filter_o = (match o with
    | PayClause(p1,p2,p3,p4) -> 
      let el1, cl1, pl1 = filter_pattern p1 in
      let el2, cl2, pl2 = filter_pattern p2 in
      let el3, cl3, pl3 = filter_pattern p3 in
      let el4, cl4, pl4 = filter_pattern p4 in
      el1@el2@el3@el4, cl1@cl2@cl3@cl4, pl1@pl2@pl3@pl4, []

    | CloseClause(p1,p2,p3) -> 
      let el1, cl1, pl1 = filter_pattern p1 in
      let el2, cl2, pl2 = filter_pattern p2 in
      let el3, cl3, pl3 = filter_pattern p3 in
      el1@el2@el3, cl1@cl2@cl3, pl1@pl2@pl3, []

    | TimestampClause(p1) | RoundClause(p1) | FromClause(p1) -> 
      let el1, cl1, pl1 = filter_pattern p1 in
      el1, cl1, pl1, []

    | AssertClause(e1) -> 
      let el1 = filter_exp e1 in
      el1, [], [], []

    | FunctionClause(_,_,_,cl) -> 
      let el1, cl1 = List.split (List.map filter_cmd cl) in
      let el1, cl1 = List.flatten el1, List.flatten cl1 in
      el1, cl1, [], []

    | NewtokClause(p1,_,p2) ->
      let el1, cl1, pl1 = filter_pattern p1 in
      let el2, cl2, pl2 = filter_pattern p2 in
      el1@el2, cl1@cl2, pl1@pl2, []

    | _ -> [],[],[],[]) in
  let filter_o = match curr_filter with Some(curr_filter) -> curr_filter::next_filter_o | None -> next_filter_o in
  filter_e, filter_c, filter_p, filter_o

let filter_aclause fe fc fp fo (ao:aclause) =
  let filter_clause = filter_clause fe fc fp fo in
  let el1, cl1, pl1, ol1 = split_4 (List.map filter_clause ao) in
  let el1, cl1, pl1, ol1 = List.flatten el1, List.flatten cl1, List.flatten pl1, List.flatten ol1 in
  el1, cl1, pl1, ol1
  
let filter_contract fe fc fp fo (Contract(_,aol):contract) : exp list * cmd list * pattern list * clause list =
  let filter_aclause = filter_aclause fe fc fp fo in
  let el1, cl1, pl1, ol1 = split_4 (List.map filter_aclause aol) in
  let el1, cl1, pl1, ol1 = List.flatten el1, List.flatten cl1, List.flatten pl1, List.flatten ol1 in
  el1, cl1, pl1, ol1

let is_escrow_used (p:contract) = any_contract_check (Some(fun e -> e = Escrow)) None None None None p

let get_init_state (p:contract) = 
  let get_create_aclause (Contract(_,aol):contract) : aclause = 
    List.find (List.exists (function FunctionClause(Create,_,_,_) -> true | _ -> false)) aol
  in 
  let ao = get_create_aclause p in
  let gs = List.find_opt (function StateClause(TGlob, None, Some(_)) -> true | _ -> false) ao in
  match gs with
  | Some(StateClause(TGlob, None, Some(i))) -> Some i
  | _ -> None

let change_init_state (Contract(dl,aol):contract) (i:ide) : contract =
  let change_aclause (ao:aclause) = 
    if List.exists (function FunctionClause(Create,_,_,_) -> true | _ -> false) ao then
      if List.exists (function StateClause(TGlob, None, Some(_)) -> true | _ -> false) ao
        then List.map (function StateClause(TGlob, None, Some(_)) -> StateClause(TGlob, None, Some(i)) | o -> o) ao
      else if List.exists (function StateClause(TGlob, _, _) -> true | _ -> false) ao
        then failwith "Create can only have init state"
      else ao
    else ao
  in
  Contract(dl, List.map change_aclause aol)

let longest_aclause (Contract(_,aol):contract) : int = 
  let get_txn_clauses = List.filter (function PayClause(_,_,_,_) | CloseClause(_,_,_) | FunctionClause(_,_,_,_) | NewtokClause(_,_,_) -> true | _ -> false) in
  List.fold_left (fun a b -> max a b) 0 (List.map (fun x -> List.length (get_txn_clauses x)) aol)
  
let is_aclause_clearstate (ao:aclause) : bool =
  let onc = List.hd (List.filter_map (function FunctionClause(onc,_,_,_) -> Some onc | _ -> None) ao) in
  onc = ClearState

let get_clause_vars (o:clause) : key list = 
  let el, _, _, _  = filter_clause (Some (function
    | Val(_) | Escrow -> true 
    | _ -> false
  )) None None None o in
  remove_from_right (List.filter_map (function 
    | Val(k) -> Some k 
    | Escrow -> Some (GlobVar (Ide "escrow")) 
    | _ -> None
  ) el)  

let has_token_transfers (p:contract) : bool =
    (* todo newtokclause -> assign *)
  let _, _, _, ol =  filter_contract None None None (Some (function 
    | PayClause(_, FixedPattern(Val(_), _), _, _) -> true
    | CloseClause(FixedPattern(Val(_), _), _, _) -> true
    | _ -> false
  )) p in
  (List.length ol) > 0

let get_gstate ao = 
  let _, _, _, ol = filter_aclause None None None (Some (function StateClause(TGlob, _, _) -> true | _ -> false)) ao in
  match ol with
  | [s] -> Some s
  | [] -> None
  | _ -> failwith "Multiple state changes in one function"

let is_create_aclause ao = List.exists (function FunctionClause(Create,_,_,_) -> true | _ -> false) ao

let remove_gstate ao = List.filter (function StateClause(TGlob,_,_) -> false | _ -> true) ao