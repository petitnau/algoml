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
  raise(TypeError(Printf.sprintf "%s operands have type %s, but should have type %s." s at_str ft_str))

let raise_operand_difftype s at1 at2 : 'a = 
  let at_str = String.concat "," (List.map (string_of_vartype) [at1;at2]) in
  raise(TypeError(Printf.sprintf "%s operand types don't correspond: they have type %s." s at_str))

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

      
  let bind_pattern (td:typeenv) (t:vartype) (p:pattern) : typeenv = match p with
    | RangePattern(_,_,Some(x)) | FixedPattern(_,Some(x)) | AnyPattern(Some(x)) ->
      bind td (NormVar x) t
    | RangePattern(_,_,None) | FixedPattern(_,None) | AnyPattern(None) ->
      td
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

and check_exp_same_type td e e1 e2 : unit = 
  ignore e;
  let at1 = eval_type td e1 in
  let at2 = eval_type td e2 in
  if at1 <> at2 then raise_operand_difftype "e" at1 at2
  
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
  | CBop(Eq,e1,e2) ->
    check_exp_same_type td e e1 e2;
    TBool  
  | CBop(Neq,e1,e2) ->
    check_exp_same_type td e e1 e2;
    TBool    
  | CBop(_,e1,e2) ->
    check_exp_operand_type td e [e1;e2] [TInt;TInt];
    TBool
  | LBop(_,e1,e2) ->
    check_exp_operand_type td e [e1;e2] [TBool;TBool];
    TBool
  | Not(e1) ->
    check_exp_operand_type td e [e1] [TBool];
    TBool
  | Len(e1) ->
    check_exp_operand_type td e [e1] [TString];
    TInt 
  | Sha256(e1) ->
    check_exp_operand_type td e [e1] [TString];
    TString
  | GetInt(e1) ->
    check_exp_operand_type td e [e1] [TString];
    TInt
  | Substring(e1,_,_) ->
    check_exp_operand_type td e [e1] [TString];
    TString
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

    | Ifte(e, c1, c2) ->
      check_cmd_operand_type td c [e] [TBool];
      check_cmd td c1;
      (match c2 with 
      | Some(c2) -> check_cmd td c2
      | None -> ())
    
    | Block(cl) ->
      check_cmdl td cl
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
      let td = TypeEnv.bind_pattern td TInt amt_p in
      let td = TypeEnv.bind_pattern td TToken tkn_p in
      let td = TypeEnv.bind_pattern td TAddress afr_p in
      let td = TypeEnv.bind_pattern td TAddress ato_p in
      td

    | CloseClause(tkn_p, afr_p, ato_p) ->
      let td = TypeEnv.bind_pattern td TToken tkn_p in
      let td = TypeEnv.bind_pattern td TAddress afr_p in
      let td = TypeEnv.bind_pattern td TAddress ato_p in
      td

    | TimestampClause(timestamp_p) -> 
      TypeEnv.bind_pattern td TInt timestamp_p

    | RoundClause(round_p) -> 
      TypeEnv.bind_pattern td TInt round_p

    | FromClause(caller_p) -> 
      TypeEnv.bind_pattern td TAddress caller_p 

    | FunctionClause(_, _, pl, _) ->
      bind_params td pl

    | NewtokClause(amt_p, i, xto_p) -> 
      let td = TypeEnv.bind_pattern td TInt amt_p in
      let td = TypeEnv.bind td (NormVar i) TToken in
      TypeEnv.bind_pattern td TAddress xto_p
        
    | AssertClause(_) | GStateClause(_,_) | LStateClause(_,_,_) -> td

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

    | GStateClause(_,_) | LStateClause(_,_,_) -> ()
    
    | NewtokClause(amt_p, _, xto_p) -> 
      check_pattern td TInt amt_p;
      check_pattern td TAddress xto_p;

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
