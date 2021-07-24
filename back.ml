type state = {accounts : address -> account option;
              round : int;
              timestamp : int}
              
and account = 
  | UserAccount of address * balance * localenvs
  | ContractAccount of address * balance * localenvs * contract * env
and address = Address of int
and balance = tok -> int option
and localenvs = address -> env option
and env = ide -> eval
and tok = Token of int | Algo

and ide = Ide of string
and contract = Contract of decl list * aclause list
and decl = Declaration of statetype * muttype * vartype * ide * exp option
and parameter = Parameter of vartype * ide
and aclause = clause list
and clause =
  | PayClause of pattern * pattern * pattern * pattern
  | CloseClause of pattern * pattern * pattern
  | TimestampClause of pattern
  | RoundClause of pattern
  | FromClause of pattern
  | AssertClause of exp
  | FunctionClause of oncomplete * ide * parameter list * cmd list 
and dval = 
  | DMutable of eval
  | DImmutable of eval
  | Unbound
and eval = 
  | VInt of int
  | VString of string
  | VBool of bool
  | VToken of tok
  | VAddress of address
  | Undefined
and exp = 
  | EInt of int
  | EString of string
  | EBool of bool
  | EToken of tok
  | EAddress of address
  | Val of key 
  | IBop of ibop * exp * exp
  | LBop of lbop * exp * exp
  | CBop of cbop * exp * exp
  | Not of exp
  | Global of ide
  | Call of ide
  | Escrow of ide
and cmd = 
  | Assign of key * exp
  | AssignOp of ibop * key * exp
  | Ifte of exp * cmd list * cmd list
  | Nop
and pattern = 
  | RangePattern of exp option * exp option * ide option
  | FixedPattern of exp * ide option
  | AnyPattern of ide option
and key = 
  | GlobVar of ide
  | LocVar of ide
  | NormVar of ide
  
and vartype = TInt | TString | TBool | TToken | TAddress
and statetype = TGlob | TLoc | TNorm
and muttype = Mutable | Immutable
and oncomplete = Create | NoOp | Update | Delete | OptIn | OptOut | ClearState
and ibop = Sum | Diff | Mul | Div 
and lbop = And | Or
and cbop = Gt | Geq | Lt | Leq | Eq | Neq

and stateop =   
  | Wait of int * int
  | Transaction of transaction list
and transaction =
  | PayTransaction of int * tok * address * address
  | CloseTransaction of tok * address * address
  | CallTransaction of address * address * oncomplete * ide * eval list
  | CreateTransaction of address * contract * eval list
and opres =
  | ContractAddr of address
  | OpFailed
and callinfo = {caller : address; called : address; onc : oncomplete; fn : ide; params : eval list}

let address_counter = ref (-1)
let get_latest_address () : address = Address(!address_counter)
let create_address () : address =
  address_counter := !address_counter + 1;
  Address(!address_counter)

let empty_state : state = {accounts = (fun _ -> None); round = 0; timestamp = 0}
let empty_env : env = fun _ -> Undefined
let empty_localenvs : localenvs = fun _ -> None
let start_balance : balance = fun t -> if t = Algo then Some(0) else None
let empty_useraccount : account = UserAccount(create_address(), start_balance, empty_localenvs)
let empty_contractaccount (p:contract) : account = ContractAccount(create_address(), start_balance, empty_localenvs, p, empty_env)
  (* let rec bind_globdeclarations d dl = match dl with
  | Declaration(  )
and decl = Declaration of statetype * muttype * vartype * ide * exp option

  match p with 
  | Contract(dl, _) ->
|  *)

let apply_state (s:state) (x:address) : account option = s.accounts x
let apply_env (d:env) (i:ide) : eval = d i
let apply_localenvs (l:localenvs) (x:address) : env option = l x 
let apply_balance (a:account) (t:tok) : int option = match a with
  | UserAccount(_, b, _) | ContractAccount(_, b, _, _, _) -> b t 

let get_address a = (match a with UserAccount(x,_,_) | ContractAccount(x,_,_,_,_) -> x)

let bind_state (s:state) (a:account) : state = 
  let x = (match a with 
    | UserAccount(x, _, _) -> x
    | ContractAccount(x, _, _, _, _) -> x) in
  {s with accounts = fun x' -> if x <> x' then apply_state s x' else Some(a)}
let bind_env (d:env) (i:ide) (v:eval) : env = 
  fun i' -> if i <> i' then d i' else v
let bind_localenvs (l:localenvs) (x:address) (d:env) : localenvs = 
  fun x' -> if x <> x' then l x' else Some(d)
let bind_balance (a:account) (t:tok) (n:int option) : account = 
  match a with
  | UserAccount(x, b, l) ->
    let b' = fun t' -> if t <> t' then b t' else n in
    UserAccount(x, b', l)
  | ContractAccount(x, b, l, p, d) -> 
    let b' = fun t' -> if t <> t' then b t' else n in
    ContractAccount(x, b', l, p, d)
let rec bind_params (d:env) (pl:parameter list) (apl:eval list) : env option =
  match pl, apl with
  | Parameter(TInt,x)::pltl, (VInt(_) as v)::apltl
  | Parameter(TString,x)::pltl, (VString(_) as v)::apltl
  | Parameter(TBool,x)::pltl, (VBool(_) as v)::apltl
  | Parameter(TToken,x)::pltl, (VToken(_) as v)::apltl
  | Parameter(TAddress,x)::pltl, (VAddress(_) as v)::apltl -> 
    let d' = bind_env d x v in
    bind_params d' pltl apltl
  | [], [] -> Some(d)
  | _ -> None
  
let rec eval_exp (s:state) (d:env) (ci:callinfo) (e:exp) : eval = 
  match e with
  | EInt(i) -> VInt(i)
  | EBool(b) -> VBool(b)
  | EString(s) -> VString(s)
  | EToken(t) -> VToken(t)
  | EAddress(a) -> VAddress(a)

  | Val(NormVar(x)) -> 
    let v = apply_env d x in
    if v = Undefined then failwith "Not in env"
    else v

  | Val(GlobVar(x)) -> 
    let gd = (match apply_state s ci.called with
      | Some(ContractAccount(_,_,_,_,gd)) -> gd 
      | _ -> failwith "Called must be a contract") in
    let v = apply_env gd x in
    if v = Undefined then failwith "Not in env"
    else v
    
  | Val(LocVar(x)) -> 
    let ld = (match apply_state s ci.called with 
      | Some(UserAccount(_,_,ld)) | Some(ContractAccount(_,_,ld,_,_)) -> ld ci.called
      | _ -> failwith "Called must be a contract") in
    let ld = (match ld with
      | Some(ld) -> ld
      | None -> failwith "User not opted in") in
    let v = apply_env ld x in
    if v = Undefined then failwith "Not in env"
    else v

  | IBop(op, e1, e2) -> 
    let v1 = eval_exp s d ci e1 in
    let v2 = eval_exp s d ci e2 in
    (match v1, v2 with
    | VInt(v1), VInt(v2) ->
      (match op with
      | Sum -> VInt(v1 + v2)
      | Diff -> VInt(v1 - v2)
      | Mul -> VInt(v1 * v2)
      | Div -> VInt(v1 / v2))
    | _, _ -> failwith "Type Error")
      

  | LBop(op, e1, e2) -> 
    let v1 = eval_exp s d ci e1 in
    let v2 = eval_exp s d ci e2 in
    (match v1, v2 with
    | VBool(v1), VBool(v2) ->
      (match op with
      | And -> VBool(v1 && v2)
      | Or -> VBool(v1 || v2))
    | _, _ -> failwith "Type Error")

  | CBop(op, e1, e2) -> 
    let v1 = eval_exp s d ci e1 in
    let v2 = eval_exp s d ci e2 in
    (match v1, v2 with
    | VInt(v1), VInt(v2) ->
      (match op with
      | Gt -> VBool(v1 > v2)
      | Geq -> VBool(v1 >= v2)
      | Lt -> VBool(v1 < v2)
      | Leq -> VBool(v1 <= v2)
      | Eq -> VBool(v1 = v2)
      | Neq -> VBool(v1 <> v2))
    | _, _ -> failwith "Type Error")

  | Not(e1) ->
    let v1 = eval_exp s d ci e1 in
    (match v1 with
    | VBool(v1) -> VBool(not(v1))
    | _ -> failwith "Type Error")

  | Global(x) ->
    (match x with
    | Ide("Creator") -> failwith "GlobalCreator Not implemented"
    | _ -> failwith "GlobalOther Not implemented")

  | Call(x) ->
    (match x with
    | Ide("Sender") -> failwith "CallSender Not implemented"
    | _ -> failwith "CallOther Not implemented")

  | Escrow(x) ->
    (match x with
    | Ide("Total") -> failwith "EscrowTotal Not implemented"
    | Ide("Local") -> failwith "EscrowLocal Not implemented"
    | _ -> failwith "EscrowOther Not implemented")


let rec run_cmds (s:state) (d:env) (ci:callinfo) (cl:cmd list) : state * env =
  let rec run_cmd (s:state) (d:env) (c:cmd) : state * env = 
    (match c with
    | Assign(k, e) -> 
      let v = eval_exp s d ci e in
      (match k with
      | NormVar(x) -> 
        let d' = bind_env d x v in
        (s, d') 

      | GlobVar(x) -> 
        let acontr = (match  apply_state s ci.called with
          | Some(a) -> a 
          | None -> failwith "Called does not exist") in
        let gd = (match acontr with
          | ContractAccount(_,_,_,_,gd) -> gd 
          | _ -> failwith "Called must be a contract") in
        if apply_env gd x = Undefined then failwith "Not in env" 
        else
          let gd' = bind_env gd x v in
          let acontr' = (match acontr with
            | ContractAccount(x,b,ld,p,_) -> ContractAccount(x,b,ld,p,gd')
            | _ -> failwith "Called must be a contract") in
          let s' = bind_state s acontr' in
          (s', d)

      | LocVar(x) -> 
        let a = (match apply_state s ci.caller with
          | Some(a) -> a
          | None -> failwith "Called does not exist") in
        let ld = (match a with
          | UserAccount(_,_,lds) | ContractAccount(_,_,lds,_,_) -> lds ci.called) in
        let ld = (match ld with
          | Some(ld) -> ld
          | None -> failwith "User not opted in") in
        if apply_env ld x = Undefined then failwith "Not in env"
        else
          let ld' = bind_env ld x v in
          let a' = (match a with
          | UserAccount(x,b,lds) -> 
            let lds' = bind_localenvs lds ci.called ld' in
            UserAccount(x,b,lds') 
          | ContractAccount(x,b,lds,p,gd) -> 
            let lds' = bind_localenvs lds ci.called ld' in
            ContractAccount(x,b,lds',p,gd)) in
        let s' = bind_state s a' in
        (s', d))
        
    | AssignOp(op, k, e) ->
      run_cmd s d (Assign(k, IBop(op, Val(k), e)))
    | Ifte(e, cl1, cl2) -> 
      let v = eval_exp s d ci e in
      (match v with 
      | VBool(true) -> 
        run_cmds s d ci cl1
      | VBool(false) -> 
        run_cmds s d ci cl2
      | _ -> failwith "IFTE Type error")
      
    | Nop -> (s,d)) in

  match cl with
  | c::cltl -> 
    let s', d' = run_cmd s d c in
    run_cmds s' d' ci cltl
  | [] -> 
    s, d

let match_pattern ((s:state), (d:env), (ci:callinfo), (p:pattern), (v:eval)) : bool * env = match p with
  | RangePattern(a, b, x) -> 
    let d' = (match x with
    | Some(x) -> bind_env d x v
    | None -> d) in
    let b = (match a, b with
      | Some(a), Some(b) -> 
        let va = eval_exp s d ci a in
        let vb = eval_exp s d ci b in
        (match va, v, vb with
        | VInt(va), VInt(vb), VInt(v) -> va <= v && v <= vb
        | _ -> failwith "Type error") 

      | None, Some(b) -> 
        let vb = eval_exp s d ci b in
        (match v, vb with
        |  VInt(v), VInt(vb) -> v <= vb
        | _ -> failwith "Type error") 

      | Some(a), None -> 
        let va = eval_exp s d ci a in
        (match va, v with
        |  VInt(va), VInt(v) -> va <= v
        | _ -> failwith "Type error") 

      | None, None -> true) in
    b, d'

  | FixedPattern(a, x) -> 
    let d' = (match x with
    | Some(x) -> bind_env d x v
    | None -> d) in
    let a = eval_exp s d ci a in
    let b = (a = v) in
    b, d'

  | AnyPattern(x) ->
    let d' = (match x with
    | Some(x) -> bind_env d x v
    | None -> d) in
    (true, d')


let rec run_aclause (s:state) (d:env) (ao:aclause) (ci:callinfo) (txnl: transaction list) : state option = 
  match ao, txnl with
  | PayClause(amt_p, tkn_p, afr_p, ato_p)::aotl, PayTransaction(amt, tkn, afr, ato)::txntl ->  
    let b1, d1 = match_pattern(s, d, ci, amt_p, VInt(amt)) in
    let b2, d2 = match_pattern(s, d1, ci, tkn_p, VToken(tkn)) in
    let b3, d3 = match_pattern(s, d2, ci, afr_p, VAddress(afr)) in
    let b4, d4 = match_pattern(s, d3, ci, ato_p, VAddress(ato)) in
    if b1 && b2 && b3 && b4 then run_aclause s d4 aotl ci txntl
    else None

  | CloseClause(tkn_p, afr_p, ato_p)::aotl, CloseTransaction(tkn, afr, ato)::txntl ->
    let b1, d1 = match_pattern(s, d, ci, tkn_p, VToken(tkn)) in
    let b2, d2 = match_pattern(s, d1, ci, afr_p, VAddress(afr)) in
    let b3, d3 = match_pattern(s, d2, ci, ato_p, VAddress(ato)) in
    if b1 && b2 && b3 then run_aclause s d3 aotl ci txntl
    else None

  | TimestampClause(timestamp_p)::aotl, _ ->
    let b1, d1 = match_pattern(s, d, ci, timestamp_p, VInt(s.timestamp)) in
    if b1 then run_aclause s d1 aotl ci txnl
    else None

  | RoundClause(round_p)::aotl, _ ->
    let b1, d1 = match_pattern(s, d, ci, round_p, VInt(s.round)) in
    if b1 then run_aclause s d1 aotl ci txnl
    else None

  | FromClause(caller_p)::aotl, _ ->
    let b1, d1 = match_pattern(s, d, ci, caller_p, VAddress(ci.caller)) in
    if b1 then  run_aclause s d1 aotl ci txnl
    else None
  
  | AssertClause(e)::aotl, _ ->
    let b1 = eval_exp s d ci e in
    if b1 = VBool(true) then run_aclause s d aotl ci txnl
    else None

  | FunctionClause(onc, fn, pl, cl)::aotl, _ ->
    if onc <> ci.onc || fn <> ci.fn then None
    else 
      let d' = bind_params d pl ci.params in
      (match d' with 
      | Some(d') ->
        let s', d'' = run_cmds s d' ci cl in
        run_aclause s' d'' aotl ci txnl
      | None -> None)

  | [], _ ->
    Some(s)

  | _ -> failwith "Clause not implemented" 
  
let rec run_aclauses (s:state) (d:env) (aol:aclause list) (ci:callinfo) (txnl:transaction list) : state option =
  (match aol with
  | [] -> None
  | aohd::aotl -> 
    let s' = run_aclause s d aohd ci txnl in
    (match s' with
    | Some(s') -> Some(s')
    | None -> run_aclauses s d aotl ci txnl))

let run_contract (s:state) (p:contract) (cinfo:callinfo) (txnl:transaction list) = 
  let Contract(_, acl) = p in
  run_aclauses s empty_env acl cinfo txnl
  
let run_txns (s:state) (txnl:transaction list) : state =  
  let run_txn s txn = 
    (match txn with
    | PayTransaction(amt, tkn, xfr, xto) ->
      let afr = apply_state s xfr in
      let ato = apply_state s xto in
      (match (afr, ato) with
      | Some(afr), Some(ato) ->
        let afr_amt = apply_balance afr tkn in
        let ato_amt = apply_balance ato tkn in
        (match afr_amt, ato_amt with 
        | Some(afr_amt), Some(ato_amt) when afr_amt - amt >= 0 -> 
          let afr' = bind_balance afr tkn (Some(afr_amt - amt)) in
          let ato' = bind_balance ato tkn (Some(ato_amt + amt)) in
          let s' = bind_state s afr' in
          let s'' = bind_state s' ato' in
          Some(s'')
        | _, _ -> None)
      | _, _ -> None)

    | CloseTransaction(tkn, xfr, xto) ->
      let afr = apply_state s xfr in
      let ato = apply_state s xto in
      (match (afr, ato) with
      | Some(afr), Some(ato) ->
        let afr_amt = apply_balance afr tkn in
        let ato_amt = apply_balance ato tkn in
        (match afr_amt, ato_amt with 
        | Some(afr_amt), Some(ato_amt) -> 
          let afr' = bind_balance afr tkn None in
          let ato' = bind_balance ato tkn (Some(ato_amt + afr_amt)) in
          let s' = bind_state s afr' in
          let s'' = bind_state s' ato' in
          Some(s'')
        | _, _ -> None)
      | _, _ -> None)

    | CreateTransaction(afr, contr, params) -> 
      let acontr = empty_contractaccount contr in
      let xcontr = (match acontr with
        | ContractAccount(x, _, _, _, _) -> x
        | _ -> failwith "Create contract account must return a contract account") in
      let s' = bind_state s acontr  in
      let cinf = {caller=afr; called=xcontr; onc=Create; fn=Ide("create"); params=params} in
      let os'' = run_contract s' contr cinf txnl in
      os''

    | CallTransaction(afr, ato, onc, fn, params) -> 
      let acontr = apply_state s ato in
      (match acontr with 
      | Some(ContractAccount(_, _, _, p, _)) -> 
        let cinf = {caller=afr; called=ato; onc=onc; fn=fn; params=params} in
        let os' = run_contract s p cinf txnl in
        os'
      | _ -> None)) in

  let rec run_txns_aux s' toexectxnl =
    (match toexectxnl with
    | [] -> s'
    | hd::tl -> 
      let s' = run_txn s hd in
      (match s' with
      | None -> s
      | Some(s') -> run_txns_aux s' tl)) in
  run_txns_aux s txnl

let run_op ((s:state), (op:stateop)) : state =
  match op with
  | Wait(r, t) -> {s with round = r; timestamp = t}
  | Transaction(txnl) -> run_txns s txnl