(* open General *)
open Types
open Amlprinter

let raise_var_not_found k : 'a = 
  raise(TypeError(Printf.sprintf "Var %s was not found" (string_of_key k)))

let raise_duplicate_var k : 'a = 
  raise(TypeError(Printf.sprintf "Var %s is duplicate" (string_of_key k)))

let raise_var_mistype c t1 t2 : 'a = 
  ignore c;
  raise(TypeError(Printf.sprintf "Command %s is assigning type %s to var of type %s" ("c") (string_of_vartype t2) (string_of_vartype t1)))

let raise_operand_type s atl ftl : 'a = 
  let ft_str = String.concat "," (List.map (string_of_vartype) ftl) in
  let at_str = String.concat "," (List.map (string_of_vartype) atl) in
  raise(TypeError(Printf.sprintf "%s operands have type %s, but should have type %s." s ft_str at_str))

type typeenv = (key * vartype) list
module TypeEnv = struct
  let empty : typeenv = []
  
  let rec apply_opt (td:typeenv) (k:key) : (vartype) option =
    let k = (match k with
      | LocVar(i,_) -> LocVar(i,None)
      | k -> k) in
    match td with
    | (k', t)::_ when k = k' -> Some(t)
    | _::tl -> apply_opt tl k
    | [] -> None

  let apply (td:typeenv) (k:key) : vartype = 
    match apply_opt td k with
    | Some(t) -> t
    | None -> raise_var_not_found k
  
  let bind (td:typeenv) (k:key) (t:vartype) : typeenv = 
    if apply_opt td k = None then (k,t)::td
    else raise_duplicate_var k
end
  
let string_of_typeenv : typeenv -> string = fun td ->
  let rec string_of_elements tdl = match tdl with
    | (k,t)::tl -> 
      Printf.sprintf "[%s/%s]%s" (string_of_key k) (string_of_vartype t) (string_of_elements tl)
    | [] -> ""
  in
  "TypeEnv"^(string_of_elements td)

let string_of_typeenv_opt : typeenv option -> string = function
  | Some(td) -> string_of_typeenv td
  | None -> "None"

let rec check_exp_operand_type td e el ftl : unit = 
  ignore e;
  let atl = List.map (eval_type td) el in
  if atl <> ftl then raise_operand_type "e" atl ftl
  
and eval_type (td:typeenv) (e:exp) : vartype = match e with
  | EInt(_) -> TInt
  | EString(_) -> TString
  | EBool(_) -> TBool
  | EToken(_) -> TToken
  | EAddress(_) -> TAddress
  | Val(LocVar(_,Some(e1)) as k) -> 
    check_exp_operand_type td e [e1] [TAddress]; 
    TypeEnv.apply td k
  | Val(k) -> TypeEnv.apply td k
  | IBop(_,e1,e2) -> 
    check_exp_operand_type td e [e1;e2] [TInt;TInt];
    TInt
  | CBop(_,e1,e2) ->
    check_exp_operand_type td e [e1;e2] [TInt;TInt];
    TBool
  | LBop(_,e1,e2) ->
    check_exp_operand_type td e [e1;e2] [TBool;TBool];
    TBool
  | Not(e1) ->
    check_exp_operand_type td e [e1] [TBool];
    TBool
  | Creator -> TAddress
  | Caller -> TAddress
  | Escrow -> TAddress

let check_pattern_operand_type td p el ftl : 'a = 
  ignore p;
  let atl = List.map (eval_type td) el in
  if atl <> ftl then raise_operand_type "p" atl ftl
  
let check_pattern (td:typeenv) (t:vartype) (p:pattern) : 'a = match p with
  | RangePattern(Some(e1), Some(e2), _) ->
    check_pattern_operand_type td p [e1;e2] [TInt;TInt]

  | RangePattern(None, Some(e2), _) ->
    check_pattern_operand_type td p [e2] [TInt]

  | RangePattern(Some(e1), None, _) ->
    check_pattern_operand_type td p [e1] [TInt]
  
  | FixedPattern(e1, _) ->
    check_pattern_operand_type td p [e1] [t]
      
  | RangePattern(None, None, _) | AnyPattern(_) -> ()

let bind_pattern (td:typeenv) (t:vartype) (p:pattern) : typeenv = match p with
  | RangePattern(_,_,Some(x)) | FixedPattern(_,Some(x)) | AnyPattern(Some(x)) ->
    TypeEnv.bind td (NormVar x) t
  | RangePattern(_,_,None) | FixedPattern(_,None) | AnyPattern(None) ->
    td

let check_cmd_operand_type td c el ftl : 'a = 
  ignore c;
  let atl = List.map (eval_type td) el in
  if atl <> ftl then raise_operand_type "c" atl ftl

let rec check_cmdl td cl =
  let rec check_cmd td c = match c with
    | Assign(LocVar(i,Some(e1)), e2) ->
      check_cmd_operand_type td c [e1] [TAddress];
      check_cmd td (Assign(LocVar(i,None), e2))

    | Assign(k, e) -> 
      let t1 = TypeEnv.apply td k in
      let t2 = eval_type td e in
      if t1 <> t2 then raise_var_mistype c t1 t2

    | Ifte(e, cl1, cl2) ->
      check_cmd_operand_type td c [e] [TBool];
      check_cmdl td cl1;
      check_cmdl td cl2
  in 
  match cl with
  | cmd::cmdtl -> 
    check_cmd td cmd;
    check_cmdl td cmdtl
  | [] -> ()

let rec bind_decls (td:typeenv) (dl:decl list) : typeenv = 
  let bind_decl td d =
    match d with
    | Declaration(TGlob,_,t,i) -> TypeEnv.bind td (GlobVar i) t
    | Declaration(TLoc,_,t,i) -> TypeEnv.bind td (LocVar(i,None)) t
  in 
  match dl with
  | d::tl -> 
    let td = bind_decl td d in
    bind_decls td tl
  | [] -> td 

let rec bind_params (td:typeenv) (pl:parameter list) : typeenv = 
  match pl with
  | Parameter(t,i)::tl -> 
    let td = TypeEnv.bind td (NormVar i) t in
    bind_params td tl
  | [] -> td
  
let rec bind_aclause td ao = 
  let bind_clause td o = match o with
    | PayClause(amt_p, tkn_p, afr_p, ato_p) ->
      let td = bind_pattern td TInt amt_p in
      let td = bind_pattern td TToken tkn_p in
      let td = bind_pattern td TAddress afr_p in
      let td = bind_pattern td TAddress ato_p in
      td

    | CloseClause(tkn_p, afr_p, ato_p) ->
      let td = bind_pattern td TToken tkn_p in
      let td = bind_pattern td TAddress afr_p in
      let td = bind_pattern td TAddress ato_p in
      td

    | TimestampClause(timestamp_p) -> 
      bind_pattern td TInt timestamp_p

    | RoundClause(round_p) -> 
      bind_pattern td TInt round_p

    | FromClause(caller_p) -> 
      bind_pattern td TAddress caller_p 

    | FunctionClause(_, _, pl, _) ->
      bind_params td pl
        
    | AssertClause(_) | StateClause(_,_,_) -> td

  in match ao with
  | aohd::aotl -> 
    let td = bind_clause td aohd in
    bind_aclause td aotl
  | [] -> td

let check_clause_operand_type td o el ftl : 'a = 
  ignore o;
  let atl = List.map (eval_type td) el in
  if atl <> ftl then raise_operand_type "o" atl ftl

let check_aclause td ao =
  let check_clause td o = match o with
    | PayClause(amt_p, tkn_p, afr_p, ato_p) ->
      check_pattern td TInt amt_p;
      check_pattern td TToken tkn_p;
      check_pattern td TAddress afr_p;
      check_pattern td TAddress ato_p 

    | CloseClause(tkn_p, afr_p, ato_p) ->
      check_pattern td TToken tkn_p;
      check_pattern td TAddress afr_p;
      check_pattern td TAddress ato_p 

    | TimestampClause(timestamp_p) -> 
      check_pattern td TInt timestamp_p

    | RoundClause(round_p) -> 
      check_pattern td TInt round_p

    | FromClause(caller_p) -> 
      check_pattern td TAddress caller_p 

    | AssertClause(e) -> 
      check_clause_operand_type td o  [e] [TBool]
    
    | FunctionClause(_, _, _, cl) ->
      check_cmdl td cl

    | StateClause(_,_,_) -> ()
  in
  let rec check_aclause_aux td ao =
    (match ao with
    | aohd::aotl -> 
      check_clause td aohd;
      check_aclause_aux td aotl
    | [] -> ())
  in
  let td = bind_aclause td ao in
  check_aclause_aux td ao

let check_program (Contract(dl,aol):contract) = 
  let td = bind_decls TypeEnv.empty dl in
  List.iter (check_aclause td) aol;