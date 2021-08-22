open Types
open Tealtypes

type normenv = (ide*tealexp) list
module NormEnv = struct
  let empty = []
  let bind (nd:normenv) (i:ide) (texp:tealexp) = (i,texp)::nd
  let try_bind (nd:normenv) (i:ide option) (texp:tealexp) = match i with
    | Some(i) -> bind nd i texp
    | None -> nd
  let bind_params (nd:normenv) (pl:parameter list) = 
    let rec bind_params_aux nd pl idx = match pl with 
      | Parameter((TInt|TBool|TToken),i)::tl -> bind_params_aux (bind nd i (OPBtoi(OPTxna(TFApplicationArgs, idx)))) tl (idx+1)
      | Parameter((TString|TAddress),i)::tl -> bind_params_aux (bind nd i (OPTxna(TFApplicationArgs, idx))) tl (idx+1)
      | [] -> nd
    in bind_params_aux nd pl 1
  let rec apply (nd:normenv) (i:ide) = 
    (* print_endline (Batteries.dump nd); *)
    match nd with
    | (i',top)::_ when i=i' -> top
    (* | (i',_)::tl -> print_endline (match i' with Ide(i) -> i);  apply tl i *)
    | _::tl -> apply tl i
    | [] -> failwith( "No norm var: "^(match i with Ide(s) -> s))
  let bind_pattern (p:pattern) (obj:tealexp) (nd:normenv) : normenv =  match p with
    | AnyPattern(Some(i)) | FixedPattern(_,Some(i)) | RangePattern(_,_,Some(i)) -> bind nd i obj
    | AnyPattern(None) | FixedPattern(_,None) | RangePattern(_,_,None) -> nd
  let bind_aclause (ao:aclause) (acid:int) (nd:normenv) : normenv =  
    let rec bind_aclause_aux ao acid txnid nd = match ao with
      | PayClause(amt,_,xfr,xto)::aotl ->
        let nd = bind_pattern amt (OPGtxn(txnid, TFAmount)) nd in
        let nd = bind_pattern xfr (OPGtxn(txnid, TFSender)) nd in
        let nd = bind_pattern xto (OPGtxn(txnid, TFReceiver)) nd in
        bind_aclause_aux aotl acid (txnid+1) nd
  
      | CloseClause(_,xfr,xto)::aotl ->
        let nd = bind_pattern xfr (OPGtxn(txnid, TFSender)) nd in
        let nd = bind_pattern xto (OPGtxn(txnid, TFCloseRemainderTo)) nd in
        bind_aclause_aux aotl acid (txnid+1) nd
  
      | TimestampClause(t)::aotl -> 
        let nd = bind_pattern t (OPGlobal(GFLatestTimestamp)) nd in
        bind_aclause_aux aotl acid txnid nd
  
      | RoundClause(r)::aotl -> 
        let nd = bind_pattern r (OPGlobal(GFRound)) nd in
        bind_aclause_aux aotl acid txnid nd
  
      | FromClause(f)::aotl ->
        let nd = bind_pattern f (OPTxn(TFSender)) nd in
        bind_aclause_aux aotl acid txnid nd
  
      | FunctionClause(_, _, pl, _)::aotl -> 
        let nd = bind_params nd pl in
        bind_aclause_aux aotl acid (txnid+1) nd
        
      | AssertClause(_)::aotl | StateClause(_,_,_)::aotl -> 
        bind_aclause_aux aotl acid txnid nd

      | NewtokClause(amt,i,xto)::aotl ->
        let nd = bind_pattern amt (OPGtxn(txnid+1, TFConfigAssetTotal)) nd in
        let nd = bind nd i (OPGaid(txnid+1)) in
        let nd = bind_pattern xto (OPGtxn(txnid+1, TFSender)) nd in
        bind_aclause_aux aotl acid (txnid+2) nd
    
      | [] -> nd
  
    in bind_aclause_aux ao acid 0 nd
end

type stateenv = (ide*statetype*muttype) list
module StateEnv = struct
  let empty = []
  let bind (sd:stateenv) ((i:ide),(s:statetype)) (m:muttype) = (i,s,m)::sd
  let rec bind_decls (sd:stateenv) (dl:decl list) = match dl with
    | Declaration(s,m,_,i)::tl -> 
      let sd' = bind sd (i,s) m in
      bind_decls sd' tl
    | [] -> sd
  let rec apply (sd:stateenv) (i:ide) (s:statetype) : muttype = match sd with
    | (i',s', m)::_ when i=i' && s=s' -> m
    | _::tl -> apply tl i s
    | [] -> failwith ( "No state var: "^(match i with Ide(s) -> s))
  let rec contains (sd:stateenv) (i:ide) (s:statetype) : bool = match sd with
    | (i',s', _)::_ when i=i' && s=s' -> true
    | _::tl -> contains tl i s
    | [] -> false
end