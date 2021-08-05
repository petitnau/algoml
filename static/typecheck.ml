open General
open Types
open Amlprinter

type typeenv = (key * vartype) list

let string_of_typeenv : typeenv -> string = fun td ->
  let rec string_of_typeenv_elements tdl = match tdl with
    | (k,t)::tl -> "["^(string_of_key k)^"/"^(string_of_vartype t)^"]"^(string_of_typeenv_elements tl)
    | [] -> ""
  in
  "TypeEnv"^(string_of_typeenv_elements td)

let string_of_typeenv_opt : typeenv option -> string = function
  | Some(td) -> string_of_typeenv td
  | None -> "None"

let empty_typeenv : typeenv = []

let rec apply_typeenv (td:typeenv) (k:key) : vartype option =
  let k = (match k with
  | LocVar(i,_) -> LocVar(i,None)
  | k -> k) in
  match td with
  | (k', t)::_ when k = k' -> Some(t)
  | _::tl -> apply_typeenv tl k
  | [] -> None

let bind_typeenv (td:typeenv) (k:key) (t:vartype) = (k,t)::td

let rec eval_type (td:typeenv) (e:exp) : vartype option = match e with
  | EInt(_) -> Some TInt
  | EString(_) -> Some TString
  | EBool(_) -> Some TBool
  | EToken(_) -> Some TToken
  | EAddress(_) -> Some TAddress
  | Val(LocVar(_,Some(e)) as k) -> 
    if eval_type td e = Some TAddress
    then apply_typeenv td k else None
  | Val(k) -> apply_typeenv td k
  | IBop(_,e1,e2) -> 
    if eval_type td e1 = Some TInt
      && eval_type td e2 = Some TInt
    then Some TInt else None
  | CBop(_,e1,e2) ->
    if eval_type td e1 = Some TInt
      && eval_type td e2 = Some TInt
    then Some TBool else None
  | LBop(_,e1,e2) ->
    if eval_type td e1 = Some TBool
      && eval_type td e2 = Some TBool
    then Some TBool else None
  | Not(e) ->
    if eval_type td e = Some TBool
    then Some TBool else None
  | Creator -> Some TAddress
  | Caller -> Some TAddress
  | Escrow -> Some TAddress

let check_pattern td t p = match p with
  | RangePattern(e1, e2, x) ->
    let td = (match x with 
      | None -> td
      | Some(i) -> bind_typeenv td (NormVar i) TInt) in
    let t1 = (match e1 with
      | None -> Some TInt
      | Some(e1) -> eval_type td e1) in
    let t2 = (match e2 with
      | None -> Some TInt
      | Some(e2) -> eval_type td e2) in
    if t1 = t2
      && t1 = Some TInt
      && t = TInt
    then Some td else None

  | FixedPattern(e1, x) ->
    let td = (match x with 
      | None -> td
      | Some(i) -> bind_typeenv td (NormVar i) t) in
    if eval_type td e1 = Some t
    then Some td else None

  | AnyPattern(x) ->
    let td = (match x with 
      | None -> td
      | Some(i) -> bind_typeenv td (NormVar i) TInt) in
    Some td
      

let rec check_cmdl td cl =
  let rec check_cmd td cmd = match cmd with
    | Assign(LocVar(i,Some(e1)), e2) ->
      if eval_type td e1 = Some TAddress
      then check_cmd td (Assign(LocVar(i,None), e2)) else None

    | Assign(k, e) -> 
      let* t1 = apply_typeenv td k in
      let* t2 = eval_type td e in
      if t1 = t2 
      then Some td else None

    | Ifte(e, cl1, cl2) ->
      if eval_type td e = Some TBool
        && check_cmdl td cl1 <> None 
        && check_cmdl td cl2 <> None
      then Some td else None

  in match cl with
  | cmd::cmdtl -> 
    let* td = check_cmd td cmd in
    check_cmdl td cmdtl
  | [] -> Some td


let rec bind_decls (td:typeenv) (dl:decl list) = 
  let bind_decl (td:typeenv) (d:decl) =
    (* let te = (match d with 
    | Declaration(_,_,_,_,Some(e)) -> eval_type td e
    | Declaration(_,_,t,_,None) -> 
    else  *)
    match d with
    | Declaration(TGlob,_,t,i) -> Some(bind_typeenv td (GlobVar i) t)
    | Declaration(TLoc,_,t,i) -> Some(bind_typeenv td (LocVar(i,None)) t)
    (* | _ -> None *)
  in 
  match dl with
  | d::tl -> 
    let* td = bind_decl td d in
    bind_decls td tl
  | [] -> Some td

let rec bind_params (td:typeenv) (pl:parameter list) = 
  let bind_param (td:typeenv) (Parameter(t,i):parameter) = 
    Some(bind_typeenv td (NormVar i) t)
  in
  match pl with
  | p::tl -> 
    let* td = bind_param td p in
    bind_params td tl
  | [] -> Some td
  
let check_function td p cl = 
  let* td = bind_params td p in
  check_cmdl td cl


let rec check_aclause td ao =
   let check_clause td o = match o with
    | PayClause(amt_p, tkn_p, afr_p, ato_p) ->
      let* td = check_pattern td TInt amt_p in
      let* td = check_pattern td TToken tkn_p in
      let* td = check_pattern td TAddress afr_p in
      check_pattern td TAddress ato_p 

    | CloseClause(tkn_p, afr_p, ato_p) ->
      let* td = check_pattern td TToken tkn_p in
      let* td = check_pattern td TAddress afr_p in
      check_pattern td TAddress ato_p 

    | TimestampClause(timestamp_p) -> 
      check_pattern td TInt timestamp_p

    | RoundClause(round_p) -> 
      check_pattern td TInt round_p

    | FromClause(caller_p) -> 
      check_pattern td TAddress caller_p 

    | AssertClause(e) -> 
      if eval_type td e = Some TBool 
      then Some td else None
    
    | FunctionClause(_, _, p, cl) ->
      check_function td p cl

    | StateClause(_,_,_) -> Some td

  in match ao with
  | aohd::aotl -> 
    let* td = check_clause td aohd in
    check_aclause td aotl

  | [] -> Some td

let check_program (Contract(dl,aol):contract) = 
  let* td = bind_decls empty_typeenv dl in
  let tds = List.map (check_aclause td) aol in
  (* print_endline (String.concat "\n" (List.map (fun x -> string_of_typeenv_opt x) tds)); *)
  if List.mem None tds then None else Some tds