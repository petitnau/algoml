open Types
open Tealtypes
open Utils
open Compenvs
open General
open Postcomp
  
let rec comp_exp (e:exp) (sd:stateenv) (nd:normenv) : tealexp = 
  match e with
  | EInt(n) -> OPInt(n)
  | EString(s) -> OPByte(s)
  | EBool(b) -> if b then OPInt(1) else OPInt(0)
  | EToken(_) -> failwith "todo"
  | EAddress(_) -> failwith "todo"
  | Val(GlobVar(Ide(i))) -> OPGlobalGet(OPByte(i)) 
  | Val(LocVar(Ide(i), None)) -> OPLocalGet(OPTxn(TFSender), OPByte(i))
  | Val(LocVar(Ide(i), Some(e))) -> OPLocalGet(comp_exp e sd nd, OPByte(i))
  | Val(NormVar(i)) -> NormEnv.apply nd i
  | IBop(op,e1,e2) -> OPIbop(op, comp_exp e1 sd nd, comp_exp e2 sd nd)
  | LBop(op,e1,e2) -> OPLbop(op, comp_exp e1 sd nd, comp_exp e2 sd nd)
  | CBop(op,e1,e2) -> OPCbop(op, comp_exp e1 sd nd, comp_exp e2 sd nd)
  | Not(e) -> OPLNot(comp_exp e sd nd)
  | Creator -> OPGlobal(GFCreatorAddress)
  | Caller -> OPTxn(TFSender)
  | Escrow -> OPGlobalGet(OPByte("escrow"))

let comp_pattern ?anydiff:(anydiff=None) (p:pattern) (obj:tealexp) (sd:stateenv) (nd:normenv) : tealcmd =
  match p with
  | AnyPattern(_) -> (match anydiff with
    | None -> OPNoop
    | Some(diff) -> OPAssertSkip(OPCbop(Neq, obj, diff)))
  | FixedPattern(e, _) -> 
    OPAssertSkip(OPCbop(Eq, obj, comp_exp e sd nd))
  | RangePattern(Some e1, Some e2, _) -> 
    OPAssertSkip(OPLbop(And, OPCbop(Geq, obj, comp_exp e1 sd nd), OPCbop(Leq, obj, comp_exp e2 sd nd)))
  | RangePattern(Some e1, None, _) -> 
    OPAssertSkip(OPCbop(Geq, obj, comp_exp e1 sd nd))
  | RangePattern(None, Some e2, _) -> 
    OPAssertSkip(OPCbop(Leq, obj, comp_exp e2 sd nd))
  | RangePattern(None, None, _) -> 
    OPNoop

let rec comp_cmdlist ?mutchecks:((gcheckmut,lcheckmut)=(true,true)) (cl:cmd list) (sd:stateenv) (nd:normenv) : tealcmd list = 
  let rec comp_cmd c = match c with
    | Assign(GlobVar(Ide(i)), e) -> 
      let cassign = OPGlobalPut(OPByte(i), comp_exp e sd nd) in
      let cchecknotin = OPBnz(OPGlobalExists(OPInt(0), OPByte(i)), "fail") in
      let mt = StateEnv.apply sd (Ide i) TGlob in
      if mt = Mutable || not(gcheckmut) then cassign
      else OPSeq([cchecknotin; cassign])
    | Assign(LocVar(Ide(i), None), e) -> 
      let cassign = OPLocalPut(OPTxn(TFSender), OPByte(i), comp_exp e sd nd) in
      let cchecknotin = OPBnz(OPLocalExists(OPTxn(TFSender), OPInt(0), OPByte(i)), "fail") in
      let mt = StateEnv.apply sd (Ide i) TLoc in
      if mt = Mutable || not(lcheckmut) then cassign
      else OPSeq([cchecknotin; cassign])
    | Assign(LocVar(Ide(i), Some(a)), e) -> 
      let cassign = OPLocalPut(comp_exp a sd nd, OPByte(i), comp_exp e sd nd) in
      let cchecknotin = OPBnz(OPLocalExists(comp_exp a sd nd, OPInt(0), OPByte(i)), "fail") in
      let mt = StateEnv.apply sd (Ide i) TGlob in
      if mt = Mutable || not(lcheckmut) then cassign
      else OPSeq([cchecknotin; cassign]) (* todo refactor code  repetition *)
    | Assign(NormVar(Ide(_)), _) -> failwith "can't assign normvars"
    | Ifte(e, c1, c2) -> 
      let cond = comp_exp e sd nd in
      let c1_comp = comp_cmd c1 in
      let c2_comp = (match c2 with Some(c2) -> comp_cmd c2 | None -> OPNoop) in
      OPIfte(cond, c1_comp, c2_comp)
    | Block(cl) ->
      OPSeq(comp_cmdlist cl sd nd ~mutchecks:(gcheckmut,lcheckmut))
  in 
  List.map comp_cmd cl

let comp_clause (o:clause) (txnid:int) (_:int) (sd:stateenv) (nd:normenv) : tealcmd list * tealcmd list * tealcmd list = 
  let unfhead, head, body = (match o with
  | PayClause(amt,FixedPattern(EToken(Algo), None),xfr,xto) ->
    let check_txntype =  OPAssertSkip(OPCbop(Eq, OPGtxn(txnid, TFTypeEnum), OPTypeEnum(TEPay))) in
    let check_amount = comp_pattern amt (OPGtxn(txnid, TFAmount)) sd nd in
    let check_sender = if not(StateEnv.contains sd (Ide "escrow") TGlob)  
      then comp_pattern xfr (OPGtxn(txnid, TFSender)) sd nd ~anydiff:None
      else if xto = AnyPattern(Some(Ide "escrow"))  
      then comp_pattern xfr (OPGtxn(txnid, TFSender)) sd nd ~anydiff:(Some (OPGtxn(txnid, TFReceiver)))
      else comp_pattern xfr (OPGtxn(txnid, TFSender)) sd nd ~anydiff:(Some (OPGlobalGet(OPByte("escrow")))) in
    let check_receiver = comp_pattern xto (OPGtxn(txnid, TFReceiver)) sd nd in
    let check_remainder = OPAssertSkip(OPCbop(Eq, OPGtxn(txnid, TFCloseRemainderTo), OPGlobal(GFZeroAddress))) in
    [check_txntype], [check_amount; check_sender; check_receiver; check_remainder], []

  | PayClause(amt,tkn,xfr,xto) ->
    let check_txntype = OPAssertSkip(OPCbop(Eq, OPGtxn(txnid, TFTypeEnum), OPTypeEnum(TEAxfer))) in
    let check_amount = comp_pattern amt (OPGtxn(txnid, TFAssetAmount)) sd nd in
    let check_token = comp_pattern tkn (OPGtxn(txnid, TFXferAsset)) sd nd in
    let check_sender = comp_pattern xfr (OPGtxn(txnid, TFAssetSender)) sd nd ~anydiff:(Some (OPGlobalGet(OPByte("escrow")))) in
    let check_receiver = comp_pattern xto (OPGtxn(txnid, TFAssetReceiver)) sd nd in
    let check_remainder = OPAssertSkip(OPCbop(Eq, OPGtxn(txnid, TFAssetCloseTo), OPGlobal(GFZeroAddress))) in
    [check_txntype], [check_amount; check_token; check_sender; check_receiver; check_remainder], []

  | CloseClause(_,xfr,xto) ->
    let check_txntype = OPAssertSkip(OPCbop(Eq, OPGtxn(txnid, TFTypeEnum), OPTypeEnum(TEPay))) in
    let check_amount = comp_pattern (FixedPattern(EInt(0), None)) (OPGtxn(txnid, TFAmount)) sd nd in
    let check_sender = comp_pattern xfr (OPGtxn(txnid, TFSender)) sd nd ~anydiff:(Some (OPGlobalGet(OPByte("escrow")))) in
    let check_remainder = comp_pattern xto (OPGtxn(txnid, TFCloseRemainderTo)) sd nd in
    [check_txntype], [check_amount; check_sender; check_remainder], []

  | TimestampClause(t) -> 
    let check_timestamp = comp_pattern t (OPGlobal(GFLatestTimestamp)) sd nd in
    [], [check_timestamp], []

  | RoundClause(r) -> 
    let check_round = comp_pattern r (OPGlobal(GFRound)) sd nd in
    [], [check_round], []

  | FromClause(f) ->
    let check_from = comp_pattern f (OPTxn(TFSender)) sd nd in
    [], [check_from], []

  | AssertClause(e) ->
    let check_condition = OPAssertSkip(comp_exp e sd nd) in
    [], [check_condition], []

  | StateClause(stype,sfr,sto) -> 
    let check_state = (match sfr with
      | Some(Ide(s)) -> 
        if stype = TGlob 
        then OPAssertSkip(OPCbop(Eq, OPGlobalGet(OPByte("gstate")), OPByte(s)))
        else OPAssertSkip(OPCbop(Eq, OPLocalGet(OPTxn(TFSender), OPByte("lstate")), OPByte(s)))
      | None -> OPNoop) in
    let set_state = (match sto with
      | Some(Ide(s)) ->
        if stype = TGlob 
        then OPGlobalPut(OPByte("gstate"), OPByte(s))
        else OPLocalPut(OPTxn(TFSender), OPByte("lstate"), OPByte(s))
      | None -> OPNoop) in
    [], [check_state], [set_state]

  | NewtokClause(amt, _, xto) ->
    let check_txntype_fund = OPAssertSkip(OPCbop(Eq, OPGtxn(txnid, TFTypeEnum), OPTypeEnum(TEPay))) in
    let check_amount_fund = comp_pattern (FixedPattern(EInt(100000), None)) (OPGtxn(txnid, TFAmount)) sd nd in
    let check_sender_fund = comp_pattern (AnyPattern(None)) (OPGtxn(txnid, TFSender)) sd nd ~anydiff:(Some (OPGlobalGet(OPByte("escrow")))) in
    let check_receiver_fund = comp_pattern (FixedPattern(Escrow, None)) (OPGtxn(txnid, TFReceiver)) sd nd in
    let check_txntype_create = OPAssertSkip(OPCbop(Eq, OPGtxn(txnid+1, TFTypeEnum), OPTypeEnum(TEAcfg))) in
    let check_amount_create = comp_pattern amt (OPGtxn(txnid+1, TFConfigAssetTotal)) sd nd in
    let check_decimals_create = comp_pattern (FixedPattern(EInt(0), None)) (OPGtxn(txnid+1, TFConfigAssetDecimals)) sd nd in
    let check_manager_create = comp_pattern (FixedPattern(EString(""), None)) (OPGtxn(txnid+1, TFConfigAssetManager)) sd nd in
    let check_reserve_create = comp_pattern (FixedPattern(EString(""), None)) (OPGtxn(txnid+1, TFConfigAssetReserve)) sd nd in
    let check_freeze_create = comp_pattern (FixedPattern(EString(""), None)) (OPGtxn(txnid+1, TFConfigAssetFreeze)) sd nd in
    let check_clawback_create = comp_pattern (FixedPattern(EString(""), None)) (OPGtxn(txnid+1, TFConfigAssetClawback)) sd nd in
    let check_sender_create = comp_pattern xto (OPGtxn(txnid+1, TFSender)) sd nd in
    [check_txntype_fund; check_txntype_create], 
    [check_amount_fund; check_sender_fund; check_receiver_fund; 
      check_amount_create; check_decimals_create; check_manager_create; check_reserve_create; check_freeze_create; check_clawback_create; check_sender_create], []

  | FunctionClause(onc, Ide(fn), pl, cl) ->
    let check_creator = if onc = Create then OPAssertSkip(OPCbop(Eq, OPTxn(TFSender), OPGlobal(GFCreatorAddress))) else OPNoop in
    let check_oncomplete = OPAssertSkip(OPCbop(Eq, OPTxn(TFOnCompletion), OPOnCompletion(if onc = Create then NoOp else onc))) in
    let check_argcount = OPAssertSkip(OPCbop(Eq, OPTxn(TFNumAppArgs), OPInt((List.length pl) + 1))) in
    let check_fn = OPAssertSkip(OPCbop(Eq, OPTxna(TFApplicationArgs, 0), OPByte(fn))) in
    let mutchecks = if onc=Create then (false,false) else if onc=OptIn then (true,false) else (false,false) in
    let body = comp_cmdlist cl sd nd ~mutchecks:mutchecks in
    [check_oncomplete; check_argcount; check_fn], [check_creator], body)
  in
  let keys = get_clause_vars o in
  let check_vars_exist = (match o with 
    | FunctionClause(_,_,_,_) -> []
    | _ -> List.filter_map (function
      | GlobVar(Ide(i)) -> Some(OPAssertSkip(OPGlobalExists(OPInt(0), OPByte(i))))
      | LocVar(Ide(i), Some(e)) -> Some(OPAssertSkip(OPLocalExists(comp_exp e sd nd, OPInt(0), OPByte(i))))
      | LocVar(Ide(i), None) -> Some(OPAssertSkip(OPLocalExists(OPTxn(TFSender), OPInt(0), OPByte(i))))
      | NormVar(_) -> None) 
      keys)
  in
  unfhead, check_vars_exist@head, body

    
let comp_aclause (ao:aclause) (acid:int) (sd:stateenv) = 
  let rec comp_aclause_aux ao txnid unfhead head body nd = match ao with 
    | hd::tl -> 
      let nunfhead,nhead,nbody = comp_clause hd txnid acid sd nd in
      let unfhead' = unfhead@nunfhead in
      let head' = head@nhead in
      let body' = body@nbody in
      let txnid = (match hd with PayClause(_,_,_,_) | CloseClause(_,_,_) | FunctionClause(_,_,_,_) -> txnid+1 | NewtokClause(_,_,_) -> txnid+2 | _ -> txnid) in
      comp_aclause_aux tl txnid unfhead' head' body' nd
    | [] -> unfhead, head, body
  in 
  let txn_count = List.fold_right (+) (List.map (fun t -> match t with PayClause(_,_,_,_) | CloseClause(_,_,_) | FunctionClause(_,_,_,_)  -> 1 | NewtokClause(_,_,_) -> 2  | _ -> 0) ao) 0 in
  let pre_checks = [OPAssertSkip(OPCbop(Eq, OPGlobal(GFGroupSize), OPInt(txn_count)))] in
  let nd = NormEnv.bind_aclause ao acid NormEnv.empty in
  let unfhead,head,body = comp_aclause_aux ao 0 [] [] [] nd in
  OPBlock(pre_checks@unfhead@head, body)


let precomp (p:contract) (sd:stateenv) : contract * stateenv = 
  let rec optin_newtok_pay ao = match ao with
    | (NewtokClause(_, i, xto') as o)::aotl -> 
      let _,_,_, payclauses = filter_aclause None None None (Some (function
        | PayClause(_, tkn, xfr, _) when xfr = xto' && tkn = FixedPattern(Val(NormVar(i)), None) -> true
        | _ -> false
      )) aotl in
      let optins = List.map (function PayClause(_, tkn, _, xto) -> PayClause(FixedPattern(EInt(0), None), tkn, xto, xto) | o -> o) payclauses in
      o::optins@aotl
    | o::aotl -> o::(optin_newtok_pay aotl)
    | [] -> []
  in
  let p' = map_contract None None None None (Some (fun ao ->
    match is_escrow_used p, get_gstate ao, is_create_aclause ao with
    | false, None, false -> [AssertClause(CBop(Neq, Val(GlobVar(Ide("gstate"))), EString("@created")))]@ao
    | true, None, false -> [AssertClause(LBop(And, CBop(Neq, Val(GlobVar(Ide("gstate"))), EString("@created")), CBop(Neq, Val(GlobVar(Ide("gstate"))), EString("@escrowinited"))))]@ao
    | false, None, true -> [StateClause(TGlob, Some(Ide("@created")), Some(Ide("@inited")))]@ao
    | true, None, true -> [StateClause(TGlob, Some(Ide("@escrowinited")), Some(Ide("@inited")))]@ao
    | false, Some(StateClause(TGlob, None, new_state)), true -> [StateClause(TGlob, Some(Ide("@created")), new_state)]@(remove_gstate ao)
    | true, Some(StateClause(TGlob, None, new_state)), true -> [StateClause(TGlob, Some(Ide("@escrowinited")), new_state)]@(remove_gstate ao)
    | _, Some(StateClause(TLoc,_,_)), _ -> failwith "get_gstate returned an lstate"
    | _, _, _ -> ao
  )) p in
  let p'' = if not(is_escrow_used p) then p' else 
    let Contract(dl,aol) = p' in
    let p = Contract(dl,[[
      FromClause(FixedPattern(Creator, None));
      StateClause(TGlob, Some(Ide("@created")), Some(Ide("@escrowinited")));
      PayClause(FixedPattern(EInt(100000), None), FixedPattern(EToken(Algo), None), AnyPattern(None), AnyPattern(Some(Ide "escrow")));
      FunctionClause(NoOp, Ide("init_escrow"), [], [
        Assign(GlobVar(Ide("escrow")), Val(NormVar(Ide("escrow"))))
      ])
    ]]@aol) in
    let Contract(dl,aol) = p in
    let p = if not(has_token_transfers p) then p else Contract(dl,aol@[
      [AssertClause(CBop(Neq, Val(GlobVar(Ide("gstate"))), EString("@created")));
       PayClause(FixedPattern(EInt(100000), None), FixedPattern(EToken(Algo), None), AnyPattern(None), FixedPattern(Escrow, None));
       PayClause(FixedPattern(EInt(0), None), AnyPattern(None), FixedPattern(Escrow, None), FixedPattern(Escrow, None));
       FunctionClause(NoOp, Ide("optin_token"), [], [])]
    ]) in
    p
  in  
  let p''' = map_contract None None None None (Some optin_newtok_pay) p'' in
  let sd' = if is_escrow_used p then StateEnv.bind sd (Ide("escrow"), TGlob) Immutable else sd in
  p''', sd'

let comp_escrow (len:int) : tealcmd = 
  let check_txnappl i = OPSeq([OPLabel(Printf.sprintf "call_%d" i); OPBz(OPCbop(Eq, OPGtxn(i, TFTypeEnum), OPTypeEnum(TEAppl)), Printf.sprintf "call_%d" (i+1)); OPBnz(OPCbop(Eq, OPGtxn(i, TFApplicationID), OPELiteral("int <APP-ID>")), "app_called")]) in
  let app_called = OPSeq((List.map check_txnappl (0--len))@[OPLabel(Printf.sprintf "call_%d" len); OPErr]) in
  let check_rekey = OPAssert(OPCbop(Eq, OPTxn(TFRekeyTo), OPGlobal(GFZeroAddress))) in
  let check_call = OPBz(OPCbop(Eq, OPTxn(TFTypeEnum), OPTypeEnum(TEPay)), "not_call") in
  let check_callself = OPAssert(OPCbop(Neq, OPTxn(TFApplicationID), OPELiteral("int <APP-ID>"))) in
  let check_fee = OPAssert(OPCbop(Eq, OPTxn(TFFee), OPInt(0))) in
  let approve = OPReturn(OPInt(1)) in
  OPSeq([app_called; OPLabel("app_called"); check_call; OPLabel("not_call"); check_callself; check_rekey; check_fee; approve])
    
type comptype = CompToTeal | CompToPseudo

let comp_contract (mode:comptype) (p:contract) : string * string * string option = 
  let rec comp_aclause_list aol sd appr_idx appr_prog clear_idx clear_prog = 
    match aol with
    | ao::tl -> 
      if is_aclause_clearstate ao then 
        (comp_aclause_list tl sd appr_idx appr_prog (clear_idx+1) (clear_prog@[comp_aclause ao clear_idx sd]))
      else (comp_aclause_list tl sd (appr_idx+1) (appr_prog@[comp_aclause ao appr_idx sd]) clear_idx clear_prog)
    | [] ->
      post_comp false (OPProgram(appr_prog)), post_comp true (OPProgram(clear_prog))
  in      
  let Contract(dl,cl), sd = precomp p StateEnv.empty in
  let sd = StateEnv.bind_decls sd dl in
  let appr_prog, clear_prog = comp_aclause_list cl sd 0 [] 0 [] in
  let prog_to_str, cmd_to_str = match mode with
    | CompToTeal -> Toteal.tealprog_to_str, Toteal.tealescrow_to_str
    | CompToPseudo -> Topseudoteal.tealprog_to_str, Topseudoteal.tealescrow_to_str
  in
  let escrow_prog_str = 
    if not(is_escrow_used p) then None 
    else Some(cmd_to_str (post_comp_escrow (comp_escrow (longest_aclause p)))) in
  (prog_to_str appr_prog), (prog_to_str clear_prog), escrow_prog_str