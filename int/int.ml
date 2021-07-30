open Types
open General
open Amlprinter

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
    
  | Val(LocVar(i, e)) -> 
    let laddr = (match e with 
    | Some(e) -> 
      let v = eval_exp s d ci e in
      (match v with
      | VAddress(x) -> x
      | _ -> raise (ErrDynamic "Non address local variables"))
    | None -> ci.caller) in
    let lacc = State.get_account_ex s laddr in
    Account.get_localv_ex lacc ci.called i
    
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
    | _, _ -> raise (ErrDynamic "Integer operators can only operate on integers"))

  | LBop(op, e1, e2) -> 
    let v1 = eval_exp s d ci e1 in
    let v2 = eval_exp s d ci e2 in
    (match v1, v2 with
    | VBool(v1), VBool(v2) ->
      (match op with
      | And -> VBool(v1 && v2)
      | Or -> VBool(v1 || v2))
    | _, _ -> raise (ErrDynamic "Logical operators can only operate on booleans"))

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
    | _, _ -> raise (ErrDynamic "Compare operators can only operate on integers"))

  | Not(e1) ->
    let v1 = eval_exp s d ci e1 in
    (match v1 with
    | VBool(v1) -> VBool(not(v1))
    | _ -> raise (ErrDynamic "Not can only operate on booleans"))

  | Global(i) ->
    let acalled = State.get_account_ex s ci.called in
    (match i with
    | Ide("creator") -> VAddress(Account.get_creator_ex acalled)
    | _ -> raise (TmpDynamic ((Ide.to_str i)^" is not a global field"))) (* TODO: STATIC CHECK*)

  | Call(i) ->
    (match i with
    | Ide("sender") -> VAddress(ci.caller)
    | _ -> raise (TmpDynamic ((Ide.to_str i)^" is not a call field")))

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

      | LocVar(i, e) -> 
        let laddr = (match e with 
        | Some(e) -> 
          let v = eval_exp s d ci e in
          (match v with
          | VAddress(x) -> x
          | _ -> raise (ErrDynamic "Non address local variables"))
        | None -> ci.caller) in
        let lacc = State.get_account_ex s laddr in
        let acaller' = Account.set_localv_ex lacc ci.called i v in
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
      | _ -> raise (ErrDynamic "If condition must be of type bool"))) in
      
  match cl with
  | c::cltl -> 
    let s', d' = run_cmd s d c in
    run_cmds s' d' ci cltl
  | [] -> 
    s, d

let match_pattern ((s:state), (d:env), (ci:callinfo), (p:pattern), (v:eval)) : bool * env = 
  try (match p with
    | RangePattern(a, b, x) -> 
      let b = (match a, b with
        | Some(a), Some(b) -> 
          let va = eval_exp s d ci a in
          let vb = eval_exp s d ci b in
          (match va, v, vb with
          | VInt(va), VInt(v), VInt(vb) -> 
            va <= v && v <= vb
          | _ -> raise (ErrDynamic "Range max and min should be of type int"))

        | None, Some(b) -> 
          let vb = eval_exp s d ci b in
          (match v, vb with
          |  VInt(v), VInt(vb) -> v <= vb
          | _ -> raise (ErrDynamic "Range max should be of type int"))

        | Some(a), None -> 
          let va = eval_exp s d ci a in
          (match va, v with
          |  VInt(va), VInt(v) -> va <= v
          | _ -> raise (ErrDynamic "Range min should be of type int"))

        | None, None -> true) 
      in
      let d' = (match x with
        | Some(x) -> Env.init d x Mutable (Eval.get_type v) v 
        | None -> d) in
      b, d'

    | FixedPattern(a, x) -> 
      let a = eval_exp s d ci a in
      let b = (a = v) in
      let d' = (match x with
        | Some(x) -> Env.init d x Mutable (Eval.get_type v) v 
        | None -> d) in
      b, d'

    | AnyPattern(x) ->
      let d' = (match x with
        | Some(x) -> Env.init d x Mutable (Eval.get_type v) v 
        | None -> d) in
      (true, d'))
  with InitError(_) | NonOptedError -> false, d

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
    if b1 then run_aclause s d1 aotl ci txnl
    else None
  
  | AssertClause(e)::aotl, _ ->
    (try 
      let b1 = eval_exp s d ci e in
      if b1 = VBool(true) then run_aclause s d aotl ci txnl
      else None
    with InitError(_) | NonOptedError -> None)

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

let run_contract (s:state) (p:contract) (cinfo:callinfo) (txnl:transaction list) : state = 
  let Contract(_, acl) = p in
  let os' = run_aclauses s Env.empty acl cinfo txnl in
  match os' with
  | Some(s') -> s'
  | None -> raise (CallFail ((string_of_ide cinfo.fn)^" not found."))
  
let run_txns (s:state) (txnl:transaction list) : state =  
  let run_txn s txn = 
    (match txn with
    | PayTransaction(amt, tkn, xfr, xto) ->
      let afr = State.get_account_ex s xfr in
      let ato = State.get_account_ex s xto in
      let afr_amt = Account.apply_balance_ex afr tkn in
      let ato_amt = Account.apply_balance_ex ato tkn in
      if afr_amt - amt < 0 then raise (NotEnoughFundsError "Not enough funds for pay transaction.")
      else (
        let afr' = Account.bind_balance afr tkn (afr_amt - amt) in
        let ato' = Account.bind_balance ato tkn (ato_amt + amt) in
        let s' = State.bind s afr' in
        State.bind s' ato')

    | CloseTransaction(tkn, xfr, xto) ->
      let afr = State.get_account_ex s xfr in
      let ato = State.get_account_ex s xto in
      let afr_amt = Account.apply_balance_ex afr tkn in
      let ato_amt = Account.apply_balance_ex ato tkn in
      let afr' = Account.unbind_balance afr tkn in
      let ato' = Account.bind_balance ato tkn (ato_amt + afr_amt) in
      let s' = State.bind s afr' in
      State.bind s' ato'

    | CreateTransaction(xfr, contr, params) -> 
      let afr = State.get_account_ex s xfr in
      let acontr = Account.empty_contract contr xfr in
      let xcontr = Account.get_address acontr in
      let s' = State.bind s acontr in
      let s'' = State.bind s' (Account.opt_in afr acontr) in
      let cinf = {caller=xfr; called=xcontr; onc=Create; fn=Ide("create"); params=params} in
      run_contract s'' contr cinf txnl

    | CallTransaction(xfr, xto, onc, fn, params) -> 
      let acalled = State.get_account_ex s xto in
      let acaller = State.get_account_ex s xfr in
      let s' = if onc <> OptIn then s
        else State.bind s (Account.opt_in acaller acalled) in
      let p = Account.get_contract_ex acalled in
      let cinf = {caller=xfr; called=xto; onc=onc; fn=fn; params=params} in
      run_contract s' p cinf txnl) 
  in
  let rec run_txns_aux s' toexectxnl =
    match toexectxnl with
    | [] -> s'
    | hd::tl -> 
      let s'' = run_txn s' hd in
      run_txns_aux s'' tl
  in
  run_txns_aux s txnl

let run_op ?catch:(catch=true) (s:state) (op:stateop) : state =
  match op with
  | Wait(r, t) -> {s with round = r; timestamp = t}
  | Transaction(txnl) ->
    if catch then (try run_txns s txnl with CallFail(_) -> s)
    else run_txns s txnl

let (>:>) (s:state) ((r:int), (t:int)) : state = run_op s (Wait(r,t))
let (>=>) (s:state) (tl:transaction list) : state = run_op s (Transaction(tl))
let (>=>!) (s:state) (tl:transaction list) : state = run_op s (Transaction(tl)) ~catch:false
let (>$>) (s:state) (a:account) : state = State.bind s a