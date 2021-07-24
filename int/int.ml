open General
(* open Batteries *)

exception TypeError

let get_type (v:eval) : vartype = 
  match v with
  | VInt(_) -> TInt
  | VString(_) -> TString
  | VBool(_) -> TBool
  | VToken(_) -> TToken
  | VAddress(_) -> TAddress

let rec eval_exp (s:state) (d:env) (ci:callinfo) (e:exp) : eval = 
  match e with
  | EInt(i) -> VInt(i)
  | EBool(b) -> VBool(b)
  | EString(s) -> VString(s)
  | EToken(t) -> VToken(t)
  | EAddress(a) -> VAddress(a)

  | Val(NormVar(i)) -> Env.apply_ex d i 

  | Val(GlobVar(i)) ->
    let acalled = State.get_account_ex s ci.called in
    Account.get_globalv_ex acalled i
    
  | Val(LocVar(i)) -> 
    let acaller = State.get_account_ex s ci.caller in
    Account.get_localv_ex acaller ci.called i

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
    | _, _ -> raise TypeError)
      

  | LBop(op, e1, e2) -> 
    let v1 = eval_exp s d ci e1 in
    let v2 = eval_exp s d ci e2 in
    (match v1, v2 with
    | VBool(v1), VBool(v2) ->
      (match op with
      | And -> VBool(v1 && v2)
      | Or -> VBool(v1 || v2))
    | _, _ -> raise TypeError)

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
    | _, _ -> raise TypeError)

  | Not(e1) ->
    let v1 = eval_exp s d ci e1 in
    (match v1 with
    | VBool(v1) -> VBool(not(v1))
    | _ -> raise TypeError)

  | Global(i) ->
    let acalled = State.get_account_ex s ci.called in
    (match i with
    | Ide("creator") -> VAddress(Account.get_creator_ex acalled)
    | _ -> failwith ((Ide.to_str i)^" is not a global field"))

  | Call(i) ->
    (match i with
    | Ide("sender") -> VAddress(ci.caller)
    | _ -> failwith ((Ide.to_str i)^" is not a call field"))

  | Escrow -> VAddress(ci.called)

    
let rec run_cmds (s:state) (d:env) (ci:callinfo) (cl:cmd list) : state * env =
  let rec run_cmd (s:state) (d:env) (c:cmd) : state * env = 
    (match c with
    | Assign(k, e) -> 
      let v = eval_exp s d ci e in
      (match k with
      | NormVar(i) -> 
        let d' = Env.update d i v in
        (s, d') 

      | GlobVar(i) -> 
        let acalled = State.get_account_ex s ci.called in
        let acalled' = Account.set_globalv_ex acalled i v in
        let s' = State.bind s acalled' in
        (s', d)

      | LocVar(i) -> 
        let acaller = State.get_account_ex s ci.caller in
        let acaller' = Account.set_localv_ex acaller ci.called i v in
        let s' = State.bind s acaller' in
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
      | _ -> raise TypeError)
      
    | Nop -> (s,d)) in

  match cl with
  | c::cltl -> 
    let s', d' = run_cmd s d c in
    run_cmds s' d' ci cltl
  | [] -> 
    s, d

let match_pattern ((s:state), (d:env), (ci:callinfo), (p:pattern), (v:eval)) : bool * env = match p with
  | RangePattern(a, b, x) -> 
    let b = (match a, b with
      | Some(a), Some(b) -> 
        let va = eval_exp s d ci a in
        let vb = eval_exp s d ci b in
        (match va, v, vb with
        | VInt(va), VInt(v), VInt(vb) -> 
          va <= v && v <= vb
        | _ -> raise TypeError) 

      | None, Some(b) -> 
        let vb = eval_exp s d ci b in
        (match v, vb with
        |  VInt(v), VInt(vb) -> v <= vb
        | _ -> raise TypeError)

      | Some(a), None -> 
        let va = eval_exp s d ci a in
        (match va, v with
        |  VInt(va), VInt(v) -> va <= v
        | _ -> raise TypeError)

      | None, None -> true) 
    in
    let d' = (match x with
      | Some(x) -> Env.init d x Mutable (get_type v) v 
      | None -> d) in
    b, d'

  | FixedPattern(a, x) -> 
    let a = eval_exp s d ci a in
    let b = (a = v) in
    let d' = (match x with
      | Some(x) -> Env.init d x Mutable (get_type v) v 
      | None -> d) in
    b, d'

  | AnyPattern(x) ->
    let d' = (match x with
      | Some(x) -> Env.init d x Mutable (get_type v) v 
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
      let d' = Env.init_params d pl ci.params in
      (match d' with 
      | Some(d') ->
        let s', d'' = run_cmds s d' ci cl in
        run_aclause s' d'' aotl ci txnl
      | None -> None)

  | [], _ ->
    Some(s)

  | _ -> None
  
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
  run_aclauses s Env.empty acl cinfo txnl
  
let run_txns (s:state) (txnl:transaction list) : state =  
  let run_txn s txn = 
    (match txn with
    | PayTransaction(amt, tkn, xfr, xto) ->
      let afr = State.get_account s xfr in
      let ato = State.get_account s xto in
      (match (afr, ato) with
      | Some(afr), Some(ato) ->
        let afr_amt = Account.apply_balance afr tkn in
        let ato_amt = Account.apply_balance ato tkn in
        (match afr_amt, ato_amt with 
        | Some(afr_amt), Some(ato_amt) when afr_amt - amt >= 0 -> 
          let afr' = Account.bind_balance afr tkn (Some(afr_amt - amt)) in
          let ato' = Account.bind_balance ato tkn (Some(ato_amt + amt)) in
          let s' = State.bind s afr' in
          let s'' = State.bind s' ato' in
          Some(s'')
          | _, _ -> None)
        | _, _ -> None)

    | CloseTransaction(tkn, xfr, xto) ->
      let afr = State.get_account s xfr in
      let ato = State.get_account s xto in
      (match (afr, ato) with
      | Some(afr), Some(ato) ->
        let afr_amt = Account.apply_balance afr tkn in
        let ato_amt = Account.apply_balance ato tkn in
        (match afr_amt, ato_amt with 
        | Some(afr_amt), Some(ato_amt) -> 
          let afr' = Account.bind_balance afr tkn None in
          let ato' = Account.bind_balance ato tkn (Some(ato_amt + afr_amt)) in
          let s' = State.bind s afr' in
          let s'' = State.bind s' ato' in
          Some(s'')
        | _, _ -> None)
      | _, _ -> None)

    | CreateTransaction(afr, contr, params) -> 
      let acontr = Account.empty_contract contr afr in
      let xcontr = Account.get_address acontr in
      let s' = State.bind s acontr in
      let cinf = {caller=afr; called=xcontr; onc=Create; fn=Ide("create"); params=params} in
      let os'' = run_contract s' contr cinf txnl in
      os''

    | CallTransaction(xfr, xto, onc, fn, params) -> 
      let acalled = State.get_account_ex s xto in
      let acaller = State.get_account_ex s xfr in
      let s' = if onc <> OptIn then s
        else State.bind s (Account.opt_in acaller acalled) in
      let p = Account.get_contract_ex acalled in
      let cinf = {caller=xfr; called=xto; onc=onc; fn=fn; params=params} in
      run_contract s' p cinf txnl) in

  let rec run_txns_aux s' toexectxnl =
    (match toexectxnl with
    | [] -> print_endline "OK"; s'
    | hd::tl -> 
      let s'' = run_txn s' hd in
      (match s'' with
      | None -> print_endline "FAIL"; s
      | Some(s'') ->  run_txns_aux s'' tl)) in
  run_txns_aux s txnl

let run_op ((s:state), (op:stateop)) : state =
  match op with
  | Wait(r, t) -> {s with round = r; timestamp = t}
  | Transaction(txnl) -> run_txns s txnl