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
      | Div -> VInt(v1 / v2)
      | Mod -> VInt(v1 mod v2)
      | Bor -> VInt(v1 lor v2)
      | Band -> VInt(v1 land v2)
      | Bxor -> VInt(v1 lxor v2))
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

  | Substring(e1, n1, n2) ->
    let v1 = eval_exp s d ci e1 in
    (match v1 with
    | VString(v1) -> VString(String.sub v1 n1 (n2-n1))
    | _ -> raise (ErrDynamic "Substring only works on strings"))

  | Not(e1) ->
    let v1 = eval_exp s d ci e1 in
    (match v1 with
    | VBool(v1) -> VBool(not(v1))
    | _ -> raise (ErrDynamic "Not can only operate on booleans"))

  | Creator ->
    let acalled = State.get_account_ex s ci.called in
    VAddress(Account.get_creator_ex acalled)

  | Caller -> VAddress(ci.caller)

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
        
    | Ifte(e, c1, c2) -> 
      let v = eval_exp s d ci e in
      (match v, c2 with 
      | VBool(true), _ -> 
        run_cmd s d c1
      | VBool(false), Some(c2) -> 
        run_cmd s d c2
      | VBool(false), None ->
        (s, d)
      | _ -> raise (ErrDynamic "If condition must be of type bool"))

    | Block(cl) ->
      run_cmds s d ci cl) in
      
  match cl with
  | c::cltl -> 
    let s', d' = run_cmd s d c in
    run_cmds s' d' ci cltl
  | [] -> 
    s, d

let check_pattern ((s:state), (d:env), (ci:callinfo), (p:pattern), (v:eval)) : bool = 
  try (match p with
    | RangePattern(Some(a), Some(b), _) -> 
      let va = eval_exp s d ci a in
      let vb = eval_exp s d ci b in
      (match va, v, vb with
      | VInt(va), VInt(v), VInt(vb) -> 
        va <= v && v <= vb
      | _ -> raise (ErrDynamic "Range max and min should be of type int"))

    | RangePattern(None, Some(b), _) -> 
      let vb = eval_exp s d ci b in
      (match v, vb with
      |  VInt(v), VInt(vb) -> v <= vb
      | _ -> raise (ErrDynamic "Range max should be of type int"))

    | RangePattern(Some(a), None, _) -> 
      let va = eval_exp s d ci a in
      (match va, v with
      |  VInt(va), VInt(v) -> va <= v
      | _ -> raise (ErrDynamic "Range min should be of type int"))

    | RangePattern(None, None, _) -> true

    | FixedPattern(a, _) -> 
      let a = eval_exp s d ci a in
      a = v

    | AnyPattern(_) -> true)
  with InitError(_) | NonOptedError -> false

let bind_pattern ((d:env), (p:pattern), (v:eval)) : env = 
  match p with
  | RangePattern(_,_, Some x) | FixedPattern(_, Some x) | AnyPattern(Some x) -> Env.init d x Immutable (Eval.get_type v) v
  | RangePattern(_,_, None) | FixedPattern(_, None) | AnyPattern(None) -> d

let rec bind_aclause (s:state) (d:env) (ao:aclause) (ci:callinfo) (txnl:transaction list) : env option = 
  match ao, txnl with
  | PayClause(amt_p, tkn_p, afr_p, ato_p)::aotl, PayTransaction(amt, tkn, afr, ato)::txntl ->  
    let d = bind_pattern(d, amt_p, VInt(amt)) in
    let d = bind_pattern(d, tkn_p, VToken(tkn)) in
    let d = bind_pattern(d, afr_p, VAddress(afr)) in
    let d = bind_pattern(d, ato_p, VAddress(ato)) in
    bind_aclause s d aotl ci txntl

  | PayClause(_,_,_,_)::_, _ -> None

  | CloseClause(tkn_p, afr_p, ato_p)::aotl, CloseTransaction(tkn, afr, ato)::txntl ->
    let d = bind_pattern(d, tkn_p, VToken(tkn)) in 
    let d = bind_pattern(d, afr_p, VAddress(afr)) in
    let d = bind_pattern(d, ato_p, VAddress(ato)) in
    bind_aclause s d aotl ci txntl

  | CloseClause(_,_,_)::_, _ -> None

  | TimestampClause(timestamp_p)::aotl, _ ->
    let d = bind_pattern(d, timestamp_p, VInt(s.timestamp)) in
    bind_aclause s d aotl ci txnl

  | RoundClause(round_p)::aotl, _ ->
    let d = bind_pattern(d, round_p, VInt(s.round)) in
    bind_aclause s d aotl ci txnl

  | FromClause(caller_p)::aotl, _ ->
    let d = bind_pattern(d, caller_p, VAddress(ci.caller)) in
    bind_aclause s d aotl ci txnl
  
  | FunctionClause(_, _, pl, _)::aotl, CallTransaction(_,_,_,_,vl)::txntl 
  | FunctionClause(_, _, pl, _)::aotl, CreateTransaction(_,_,_,vl)::txntl ->
    let* d = Env.init_params d pl vl in
    bind_aclause s d aotl ci txntl

  | FunctionClause(_, _, _, _)::_, _ -> None

  | NewtokClause(amt_p, i, xto_p)::aotl, NewtokTransaction(amt, t, xto)::txntl ->
    let d = bind_pattern(d, amt_p, VInt(amt)) in
    let d = bind_pattern(d, xto_p, VAddress(xto)) in
    let d = Env.init d i Immutable TToken (VToken(t)) in
    bind_aclause s d aotl ci txntl
  
  | NewtokClause(_, _, _)::_, _ -> None

  | AssertClause(_)::aotl, _  | StateClause(_,_,_)::aotl, _->  bind_aclause s d aotl ci txnl
      
  | [], [] -> Some(d)
  | [], _ -> None

let run_aclause (s:state) (d:env) (ao:aclause) (ci:callinfo) (txnl:transaction list) : state option = 
  let rec run_aclause_aux s d ao ci txnl = 
    match ao, txnl with
    | PayClause(amt_p, tkn_p, afr_p, ato_p)::aotl, PayTransaction(amt, tkn, afr, ato)::txntl ->  
      if check_pattern(s, d, ci, amt_p, VInt(amt))
        && check_pattern(s, d, ci, tkn_p, VToken(tkn))
        && check_pattern(s, d, ci, afr_p, VAddress(afr))
        && check_pattern(s, d, ci, ato_p, VAddress(ato))
      then run_aclause_aux s d aotl ci txntl
      else None

    | PayClause(_,_,_,_)::_, _ -> None

    | CloseClause(tkn_p, afr_p, ato_p)::aotl, CloseTransaction(tkn, afr, ato)::txntl ->
      if check_pattern(s, d, ci, tkn_p, VToken(tkn))
        && check_pattern(s, d, ci, afr_p, VAddress(afr))
        && check_pattern(s, d, ci, ato_p, VAddress(ato))
      then run_aclause_aux s d aotl ci txntl
      else None

    | CloseClause(_,_,_)::_, _ -> None

    | TimestampClause(timestamp_p)::aotl, _ ->
      if check_pattern(s, d, ci, timestamp_p, VInt(s.timestamp))
      then run_aclause_aux s d aotl ci txnl
      else None

    | RoundClause(round_p)::aotl, _ ->
      if check_pattern(s, d, ci, round_p, VInt(s.round))
      then run_aclause_aux s d aotl ci txnl
      else None

    | FromClause(caller_p)::aotl, _ ->
      if check_pattern(s, d, ci, caller_p, VAddress(ci.caller))
      then run_aclause_aux s d aotl ci txnl
      else None
    
    | AssertClause(e)::aotl, _ ->
      (try 
        let b1 = eval_exp s d ci e in
        if b1 = VBool(true) 
        then run_aclause_aux s d aotl ci txnl
        else None
      with InitError(_) | NonOptedError -> None)

    | FunctionClause(onc, fn, _, cl)::aotl, CallTransaction(_,_,onc',fn',_)::txntl when onc = onc' && fn = fn' ->
      let s', d' = run_cmds s d ci cl in
      run_aclause_aux s' d' aotl ci txntl

    | FunctionClause(onc, fn, _, cl)::aotl, CreateTransaction(_,_,fn',_)::txntl when onc = Create && fn = fn' ->
      let s', d' = run_cmds s d ci cl in
      run_aclause_aux s' d' aotl ci txntl

    | FunctionClause(_, _, _, _)::_, _ -> None

    | NewtokClause(amt_p, _, xto_p)::aotl, NewtokTransaction(amt, _, xto)::txntl ->
      if check_pattern(s, d, ci, amt_p, VInt(amt))
        && check_pattern(s, d, ci, xto_p, VAddress(xto))
      then run_aclause_aux s d aotl ci txntl
      else None

    | NewtokClause(_, _, _)::_, _ -> None

    | StateClause(stype, fromstate, tostate)::aotl, _ -> 
      let b = (match fromstate with
      | Some(Ide(fromstate)) -> 
        let fromstate' = 
          (if stype = TGlob then State.get_globalv_ex s ci.called (Ide "gstate") 
          else State.get_localv_ex s ci.caller ci.called (Ide "lstate")) in
        (match fromstate' with
        | VString(fromstate') when fromstate = fromstate' -> true
        | VString(_) -> false
        | _ -> raise(ErrDynamic("state should contain strings")))
      | None -> true) in
      if not(b) then None
      else 
        let s' = (match tostate with
          | Some(Ide(tostate)) ->
            if stype = TGlob then State.set_globalv_ex s ci.called (Ide "gstate") (VString tostate)
            else State.set_localv_ex s ci.caller ci.called (Ide "lstate") (VString tostate)
          | None -> s) in
          run_aclause_aux s' d aotl ci txnl
        
    | [], [] -> Some(s)
    | [], _ -> failwith "Err"
  in
  let* d = bind_aclause s d ao ci txnl in
  run_aclause_aux s d ao ci txnl

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

    | CreateTransaction(xfr, contr, fn, params) -> 
      let afr = State.get_account_ex s xfr in
      let acontr = Account.empty_contract contr xfr in
      let xcontr = Account.get_address acontr in
      let s' = State.bind s acontr in
      let s'' = State.bind s' (Account.opt_in afr acontr) in
      let cinf = {caller=xfr; called=xcontr; onc=Create; fn=fn; params=params} in
      run_contract s'' contr cinf txnl

    | CallTransaction(xfr, xto, onc, fn, params) -> 
      let acalled = State.get_account_ex s xto in
      let acaller = State.get_account_ex s xfr in
      let s' = if onc <> OptIn then s
        else State.bind s (Account.opt_in acaller acalled) in
      let p = Account.get_contract_ex acalled in
      let cinf = {caller=xfr; called=xto; onc=onc; fn=fn; params=params} in
      (try 
        let s'' = run_contract s' p cinf txnl in
        if onc = Delete then State.unbind s'' xto
        else if onc = OptOut || onc = ClearState then State.bind s (Account.opt_out acaller xto) 
        else s''
      with CallFail(_) as ex ->
        if onc = ClearState then State.bind s (Account.opt_out acaller xto)
        else raise ex)

    | NewtokTransaction(amt, t, xto) ->
      State.create_token s xto t amt
    )
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