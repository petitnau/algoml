open Types
open Tealtypes
open Utils
open Compenvs
open Postcomp
open Pseudotealify
  
let rec comp_exp (e:exp) (sd:stateenv) (nd:normenv)  : tealexp = match e with
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

let comp_pattern (p:pattern) (obj:tealexp) (sd:stateenv) (nd:normenv) : tealcmd = match p with
  | AnyPattern(_) -> 
    OPNoop
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
  let comp_cmd c = match c with
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
    | Ifte(e, cl1, cl2) -> 
      let cond = comp_exp e sd nd in
      let cl1_comp = comp_cmdlist cl1 sd nd ~mutchecks:(gcheckmut,lcheckmut) in
      let cl2_comp = comp_cmdlist cl2 sd nd ~mutchecks:(gcheckmut,lcheckmut) in
      OPIfte(cond, cl1_comp, cl2_comp)
  in 
  List.map comp_cmd cl

let comp_clause (o:clause) (txnid:int) (_:int) (sd:stateenv) (nd:normenv) : tealcmd list * tealcmd list * tealcmd list = 
  let unfhead, head, body = (match o with
  | PayClause(amt,FixedPattern(EToken(Algo), None),xfr,xto) ->
    let check_txntype =  OPAssertSkip(OPCbop(Eq, OPGtxn(txnid, TFTypeEnum), OPTypeEnum(TEPay))) in
    let check_amount = comp_pattern amt (OPGtxn(txnid, TFAmount)) sd nd in
    let check_sender = comp_pattern xfr (OPGtxn(txnid, TFSender)) sd nd in
    let check_receiver = comp_pattern xto (OPGtxn(txnid, TFReceiver)) sd nd in
    let check_remainder = OPAssertSkip(OPCbop(Eq, OPGtxn(txnid, TFCloseRemainderTo), OPGlobal(GFZeroAddress))) in
    [check_txntype], [check_amount; check_sender; check_receiver; check_remainder], []

  | PayClause(amt,tkn,xfr,xto) ->
    let check_txntype = OPAssertSkip(OPCbop(Eq, OPGtxn(txnid, TFTypeEnum), OPTypeEnum(TEAxfer))) in
    let check_amount = comp_pattern amt (OPGtxn(txnid, TFAssetAmount)) sd nd in
    let check_token = comp_pattern tkn (OPGtxn(txnid, TFXferAsset)) sd nd in
    let check_sender = comp_pattern xfr (OPGtxn(txnid, TFAssetSender)) sd nd in
    let check_receiver = comp_pattern xto (OPGtxn(txnid, TFAssetReceiver)) sd nd in
    let check_remainder = OPAssertSkip(OPCbop(Eq, OPGtxn(txnid, TFAssetCloseTo), OPGlobal(GFZeroAddress))) in
    [check_txntype], [check_amount; check_token; check_sender; check_receiver; check_remainder], []

  | CloseClause(_,xfr,xto) ->
    let check_txntype =  OPAssertSkip(OPCbop(Eq, OPGtxn(txnid, TFTypeEnum), OPTypeEnum(TEPay))) in
    let check_amount = OPAssertSkip(OPCbop(Eq, OPGtxn(txnid, TFAmount), OPInt(0))) in
    let check_sender = comp_pattern xfr (OPGtxn(txnid, TFSender)) sd nd in
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

  | FunctionClause(onc, Ide(fn), pl, cl) ->
    let check_oncomplete =
      if onc = Create
      then OPAssertSkip(OPCbop(Eq, OPTxn(TFApplicationID), OPInt(0)))
      else OPAssertSkip(OPCbop(Eq, OPTxn(TFOnCompletion), OPOnCompletion(onc))) in
    let check_argcount = OPAssertSkip(OPCbop(Eq, OPTxn(TFNumAppArgs), OPInt((List.length pl) + 1))) in
    let check_fn = OPAssertSkip(OPCbop(Eq, OPTxna(TFApplicationArgs, 0), OPByte(fn))) in
    let mutchecks = if onc=Create then (false,false) else if onc=OptIn then (true,false) else (false,false) in
    let body = comp_cmdlist cl sd nd ~mutchecks:mutchecks in
    [check_oncomplete; check_argcount; check_fn], [], body)
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
      let txnid = (match hd with PayClause(_,_,_,_) | CloseClause(_,_,_) | FunctionClause(_,_,_,_) -> txnid+1 | _ -> txnid) in
      comp_aclause_aux tl txnid unfhead' head' body' nd
    | [] -> unfhead, head, body
  in 
  let txn_count = List.length (List.filter (fun t -> match t with PayClause(_,_,_,_) | CloseClause(_,_,_) | FunctionClause(_,_,_,_) -> true  | _ -> false) ao) in
  let pre_checks = [OPAssertSkip(OPCbop(Eq, OPGlobal(GFGroupSize), OPInt(txn_count)))] in
  let nd = NormEnv.bind_aclause ao acid NormEnv.empty in
  let unfhead,head,body = comp_aclause_aux ao 0 [] [] [] nd in
  OPBlock(pre_checks@unfhead@head, body)

let precomp (p:contract) (sd:stateenv) : contract * stateenv = 
  if not(is_escrow_used p) then p, sd
  else
    let sd' = StateEnv.bind sd (Ide("escrow"), TGlob) Immutable in
    let init_state = get_init_state p in
    let init_escrow_base = [
      FromClause(FixedPattern(Creator, None));
      PayClause(FixedPattern(EInt(100000), None), FixedPattern(EToken(Algo), None), AnyPattern(None), AnyPattern(Some(Ide "escrow")));
      FunctionClause(NoOp, Ide("init_escrow"), [], 
        [Assign(GlobVar(Ide("escrow")), Val(NormVar(Ide("escrow"))))])] in
    (* let init_escrow_base = [
      FromClause(FixedPattern(Creator, None));
      PayClause(FixedPattern(EInt(100000), None), FixedPattern(EToken(Algo), None), AnyPattern(None), FixedPattern(Val(NormVar(Ide("escrow"))), None));
      FunctionClause(NoOp, Ide("init_escrow"), [Parameter(TAddress, Ide("escrow"))], 
        [Assign(GlobVar(Ide("escrow")), Val(NormVar(Ide("escrow"))))])] in *)
    let p' = (match init_state with
      | Some(init_state) ->
        let p = change_init_state p (Ide "init_escrow") in
        let Contract(dl,aol) = p in
        Contract(dl, aol@[
          (StateClause(TGlob, Some(Ide "init_escrow"), Some(init_state)))::init_escrow_base])
      | None ->
        let Contract(dl,aol) = p in
        Contract(dl, aol@[init_escrow_base])) in
    p', sd'

let comp_escrow (len:int) : tealcmd = 
  let rec comp_app_checks i = 
    if i > 0 then OPIfte(OPCbop(Eq, OPGtxn(i, TFTypeEnum), OPTypeEnum(TEAppl)), [OPB("app_called")], [comp_app_checks (i-1)])
    else OPErr
  in
  let app_called = comp_app_checks len in
  let check_rekey = OPAssert(OPCbop(Eq, OPTxn(TFRekeyTo), OPGlobal(GFZeroAddress))) in
  let check_call = OPBz(OPCbop(Eq, OPTxn(TFTypeEnum), OPTypeEnum(TEPay)), "not_call") in
  let check_callself = OPAssert(OPCbop(Neq, OPTxn(TFApplicationID), OPELiteral("int <APP-ID>"))) in
  let check_fee = OPAssert(OPCbop(Eq, OPTxn(TFFee), OPInt(0))) in
  let approve = OPReturn(OPInt(1)) in
  OPSeq([app_called; OPLabel("app_called"); check_call; OPLabel("not_call"); check_callself; check_rekey; check_fee; approve])
    
let comp_contract (p:contract) : string * string * string option = 
  let rec comp_aclause_list aol sd appr_idx appr_prog clear_idx clear_prog = 
    match aol with
    | ao::tl -> 
      if is_aclause_clearstate ao then 
        (comp_aclause_list tl sd appr_idx appr_prog (clear_idx+1) (clear_prog@[comp_aclause ao clear_idx sd]))
      else (comp_aclause_list tl sd (appr_idx+1) (appr_prog@[comp_aclause ao appr_idx sd]) clear_idx clear_prog)
    | [] ->
      post_comp (OPProgram(appr_prog)), post_comp (OPProgram(clear_prog))
  in      
  let Contract(dl,cl), sd = precomp p StateEnv.empty in
  let sd = StateEnv.bind_decls sd dl in
  let appr_prog, clear_prog = comp_aclause_list cl sd 0 [] 0 [] in
  let escrow_prog_str = 
    if not(is_escrow_used p) then None 
    else Some(tealcmd_to_str (post_comp_escrow (comp_escrow (longest_aclause p)))) in
  (tealprog_to_str appr_prog), (tealprog_to_str clear_prog), escrow_prog_str

let test_comp ast = 
  let appr_prog, clear_prog, escrow_prog = comp_contract ast in
  (* let s = comp_aclause ([PayClause(RangePattern(Some(EInt(3)), Some(EInt(5)), None), FixedPattern(EToken(Algo), None), FixedPattern(Val(GlobVar(Ide("receiver"))),None), AnyPattern(None))]) in *)
  print_endline appr_prog;
  print_endline "\n\n/-/-/-/-/-/-/-/-/-/-/-/-/-/-/\n\n";
  print_endline clear_prog;
  print_endline "\n\n/-/-/-/-/-/-/-/-/-/-/-/-/-/-/\n\n";
  match escrow_prog with
  | Some(escrow_prog) -> print_endline escrow_prog
  | None -> ()