open Types

type tealop =
  | OPSeparate of string * tealop list
  | OPComment of string
  | OPLabel of string

  | OPInt of int
  | OPByte of string

  | OPIbop of ibop * tealop * tealop
  | OPCbop of cbop *  tealop * tealop
  | OPLbop of lbop *  tealop * tealop
  | OPLNot of tealop
  | OPBNot of tealop
  | OPLen of tealop
  | OPItob of tealop
  | OPBtoi of tealop

  | OPTxn of txnfield
  | OPTxna of txnfield * int
  | OPGtxn of int * txnfield
  | OPGtxna of int * txnfield * int
  | OPGlobal of globalfield

  | OPTypeEnum of typeenumfield
  | OPOnCompletion of oncomplete

  | OPBz of tealop * string
  | OPBnz of tealop * string
  | OPB of string
  
  | OPOptedIn of tealop * tealop

  | OPLocalGet of tealop * tealop 
  | OPLocalGetEx of tealop * tealop * tealop 
  | OPLocalPut of tealop * tealop * tealop
  | OPGlobalGet of tealop 
  | OPGlobalGetEx of tealop * tealop 
  | OPGlobalPut of tealop * tealop

  | OPSnd of tealop
  | OPErr 

  | OPNoop

and typeenumfield = 
  | TEPay
  | TEAxfer
  | TEAppl

and globalfield = 
  | GFZeroAddress
  | GFGroupSize
  | GFRound
  | GFLatestTimestamp
  | GFCreatorAddress
  (* | GFCurrentApplicationID *)

and txnfield =
  | TFSender
  | TFFee
  | TFReceiver
  | TFAmount
  | TFCloseRemainderTo
  | TFTypeEnum
  | TFXferAsset
  | TFAssetAmount
  | TFAssetSender
  | TFAssetReceiver
  | TFAssetCloseTo
  (* | TFGroupIndex *)
  | TFApplicationID
  | TFOnCompletion
  | TFApplicationArgs
  | TFNumAppArgs
  | TFAccounts
  | TFNumAccounts
  | TFRekeyTo
  | TFAssets
  | TFNumAssets
  | TFApplications
  | TFNumApplications

let label_count = ref (-1)
let new_label () = label_count := 1 + !label_count; Printf.sprintf "lbl_%d" (!label_count)

let any_contract_check (Contract(_,aol):contract) fe fc fp fo = 
  let rec any_exp_check (e:exp) = 
    (match fe with Some(fe) -> fe e | None -> false) || (match e with
    | Not(e1) -> (any_exp_check e1)
    | IBop(_,e1,e2) | LBop(_,e1,e2) | CBop(_,e1,e2) -> List.exists any_exp_check [e1;e2]
    | _ -> false) 
  in
  let rec any_cmd_check (c:cmd) =
    (match fc with Some(fc) -> fc c | None -> false) || (match c with
    | Assign(LocVar(_,Some(e1)),e2) -> List.exists any_exp_check [e1;e2]
    | Assign(_,e1) -> any_exp_check e1
    | Ifte(e1,cl1,cl2) -> (any_exp_check e1) || (List.exists any_cmd_check cl1) || (List.exists any_cmd_check cl2)) 
  in
  let any_pattern_check (p:pattern) =
    (match fp with Some(fp) -> fp p | None -> false) || (match p with
    | RangePattern(e1,e2,_) ->
       let check1 = (match e1 with Some(e1) -> any_exp_check e1 | None -> false) in
       let check2 = (match e2 with Some(e2) -> any_exp_check e2 | None -> false) in
       check1 || check2
    | FixedPattern(e1,_) -> any_exp_check e1
    | AnyPattern(_) -> false)
  in
  let any_clause_check (o:clause) = 
    (match fo with Some(fo) -> fo o | None -> false) || (match o with
    | PayClause(p1,p2,p3,p4) -> List.exists any_pattern_check [p1;p2;p3;p4] 
    | CloseClause(p1,p2,p3) -> List.exists any_pattern_check [p1;p2;p3] 
    | TimestampClause(p1) | RoundClause(p1) | FromClause(p1) -> any_pattern_check p1
    | AssertClause(e1) -> any_exp_check e1
    | FunctionClause(_,_,_,cl) -> List.exists any_cmd_check cl
    | StateClause(_,_,_) -> false)
  in 
  List.exists (List.exists any_clause_check) aol

let map_contract (Contract(_,aol):contract) fe fc fp fo = 
  let rec map_exp (e:exp) = 
    let e = (match fe with Some(fe) -> fe e | None -> e) in
    (match e with
    | Not(e1) -> (map_exp e1)
    | IBop(op,e1,e2) -> IBop(op, map_exp e1, map_exp e2)
    | LBop(op,e1,e2) -> LBop(op, map_exp e1, map_exp e2)
    | CBop(op,e1,e2) -> CBop(op, map_exp e1, map_exp e2)
    | _ -> e) 
  in
  let rec map_cmd (c:cmd) =
    let c = (match fc with Some(fc) -> fc c | None -> c) in
    (match c with
    | Assign(LocVar(i,Some(e1)),e2) -> Assign(LocVar(i,Some(map_exp e1)), map_exp e2)
    | Assign(k,e1) -> Assign(k, map_exp e1)
    | Ifte(e1,cl1,cl2) -> Ifte(map_exp e1, List.map map_cmd cl1, List.map map_cmd cl2))
  in
  let map_pattern (p:pattern) =
    let p = (match fp with Some(fp) -> fp p | None -> p) in
    (match p with
    | RangePattern(e1,e2,i) ->
       let e1' = (match e1 with Some(e1) -> Some(map_exp e1) | None -> None) in
       let e2' = (match e2 with Some(e2) -> Some(map_exp e2) | None -> None) in
       RangePattern(e1',e2',i)
    | FixedPattern(e1,i) -> FixedPattern(map_exp e1, i)
    | _ -> p)
  in
  let map_clause (o:clause) = 
    let o = (match fo with Some(fo) -> fo o | None -> o) in
    (match o with
    | PayClause(p1,p2,p3,p4) -> PayClause(map_pattern p1, map_pattern p2, map_pattern p3, map_pattern p4)
    | CloseClause(p1,p2,p3) -> CloseClause(map_pattern p1, map_pattern p2, map_pattern p3)
    | TimestampClause(p1) -> TimestampClause(map_pattern p1)
    | RoundClause(p1) -> RoundClause(map_pattern p1)
    | FromClause(p1) -> FromClause(map_pattern p1)
    | AssertClause(e1) -> AssertClause(map_exp e1)
    | FunctionClause(onc,fn,pl,cl) -> FunctionClause(onc, fn, pl, List.map map_cmd cl)
    | _ -> o)
  in 
  List.map (List.map map_clause) aol

let get_init_state (p:contract) = 
  let get_create_aclause (Contract(_,aol):contract) : aclause = 
    List.find (List.exists (function FunctionClause(Create,_,_,_) -> true | _ -> false)) aol
  in 
  let ao = get_create_aclause p in
  let gs = List.find_opt (function StateClause(TGlob, None, Some(_)) -> true | _ -> false) ao in
  match gs with
  | Some(StateClause(TGlob, None, Some(i))) -> Some i
  | _ -> None

let change_init_state (Contract(dl,aol):contract) (i:ide) : contract =
  let change_aclause (ao:aclause) = 
    if List.exists (function FunctionClause(Create,_,_,_) -> true | _ -> false) ao then
      if List.exists (function StateClause(TGlob, None, Some(_)) -> true | _ -> false) ao
        then List.map (function StateClause(TGlob, None, Some(_)) -> StateClause(TGlob, None, Some(i)) | o -> o) ao
      else if List.exists (function StateClause(TGlob, _, _) -> true | _ -> false) ao
        then failwith "Create can only have init state"
      else ao
    else ao
  in
  Contract(dl, List.map change_aclause aol)

let is_escrow_used (p:contract) = any_contract_check p (Some(fun e -> e = Escrow)) None None None

type normenv = (ide*tealop) list
module NormEnv = struct
  let empty = []
  let bind (nd:normenv) (i:ide) (top:tealop) = (i,top)::nd
  let try_bind (nd:normenv) (i:ide option) (top:tealop) = match i with
    | Some(i) -> bind nd i top
    | None -> nd
  let bind_params (nd:normenv) (pl:parameter list) = 
    let rec bind_params_aux nd pl idx = match pl with 
      | Parameter((TInt|TBool|TToken),i)::tl -> bind_params_aux (bind nd i (OPBtoi(OPTxna(TFApplicationArgs, idx)))) tl (idx+1)
      | Parameter((TString|TAddress),i)::tl -> bind_params_aux (bind nd i (OPTxna(TFApplicationArgs, idx))) tl (idx+1)
      | [] -> nd
    in bind_params_aux nd pl 1
  let rec apply (nd:normenv) (i:ide) = match nd with
    | (i',top)::_ when i=i' -> top
    | _::tl -> apply tl i
    | [] -> failwith( "No var: "^(match i with Ide(s) -> s))
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
    | [] -> failwith ( "No var: "^(match i with Ide(s) -> s))
end

let rec tealop_concat (tl:tealop list) (op:string) : string = 
  let cl = List.map tealop_to_str tl in
  String.concat "\n" (cl@[op])

and txnfield_to_str (tf:txnfield) : string = match tf with TFSender -> "Sender" | TFFee -> "Fee" | TFReceiver -> "Receiver" | TFAmount -> "Amount" | TFCloseRemainderTo -> "CloseRemainderTo"
  | TFTypeEnum -> "TypeEnum" | TFXferAsset -> "XferAsset" | TFAssetAmount -> "AssetAmount" | TFAssetSender -> "AssetSender" | TFAssetReceiver -> "AssetReceiver"
  | TFAssetCloseTo -> "AssetCloseTo" | TFApplicationID -> "ApplicationID" | TFOnCompletion -> "OnCompletion" | TFApplicationArgs -> "ApplicationArgs"
  | TFNumAppArgs -> "NumAppArgs" | TFAccounts -> "Accounts" | TFNumAccounts -> "NumAccounts" | TFRekeyTo -> "RekeyTo" | TFAssets -> "Assets" 
  | TFNumAssets -> "NumAssets" | TFApplications -> "Applications" | TFNumApplications -> "NumApplications"

and globalfield_to_str (gf:globalfield) : string = match gf with GFZeroAddress -> "ZeroAddress" | GFGroupSize -> "GroupSize" | GFRound -> "Round" | GFLatestTimestamp -> "LatestTimestamp"
  | GFCreatorAddress -> "CreatorAddress"

and typeenum_to_str (te:typeenumfield) : string = match te with TEPay -> "pay" | TEAxfer -> "axfer" | TEAppl -> "appl"

and oncompletion_to_str (onc:oncomplete) : string = match onc with NoOp -> "NoOp" | Update -> "UpdateApplication" | Delete -> "DeleteApplication" | OptIn -> "OptIn"
 | OptOut -> "CloseOut" | ClearState -> "ClearState" |  Create -> failwith "No str"

and tealop_to_str (t:tealop) : string = match t with
  | OPSeparate(s, tl) -> String.concat s (List.filter (fun x -> x <> "") (List.map tealop_to_str (List.filter (fun x -> x <> OPNoop) tl)))
  | OPComment(s) -> Printf.sprintf "// %s" s
  | OPLabel(s) -> Printf.sprintf "%s:" s

  | OPInt(n) -> Printf.sprintf "int %d" n
  | OPByte(s) -> Printf.sprintf "byte \"%s\"" s
  
  | OPIbop(op, t1, t2) -> 
    let cop = (match op with Sum -> "+" | Diff -> "-" | Mul -> "*" | Div -> "/" | Mod -> "%" | Bor -> "|" | Band -> "&" | Bxor -> "^") in
    tealop_concat [t1;t2] cop

  | OPCbop(op, t1, t2) -> 
    let cop = (match op with Gt -> ">" | Geq -> ">=" | Lt -> "<" | Leq -> "<=" | Eq -> "==" | Neq -> "!=") in
    tealop_concat [t1;t2] cop

  | OPLbop(op, t1, t2) ->
    let cop = (match op with And -> "&&" | Or -> "||") in
    tealop_concat [t1;t2] cop

  | OPLNot(t1) -> tealop_concat [t1] "!"
  | OPBNot(t1) -> tealop_concat [t1] "~"

  | OPLen(t1) -> tealop_concat [t1] "len"
  | OPItob(t1) -> tealop_concat [t1] "itob"
  | OPBtoi(t1) -> tealop_concat [t1] "btoi"

  | OPTxn(tf) -> 
    let ctf = txnfield_to_str tf in
    Printf.sprintf "txn %s" ctf
  
  | OPTxna(tf, n) ->
    let ctf = txnfield_to_str tf in
    Printf.sprintf "txna %s %n" ctf n

  | OPGtxn(n, tf) ->
    let ctf = txnfield_to_str tf in
    Printf.sprintf "gtxn %n %s" n ctf
  
  | OPGtxna(n1, tf, n2) ->
    let ctf = txnfield_to_str tf in
    Printf.sprintf "gtxn %n %s %n" n1 ctf n2

  | OPGlobal(gf) ->
    let cgf = globalfield_to_str gf in
    Printf.sprintf "global %s" cgf

  | OPTypeEnum(te) -> Printf.sprintf "int %s" (typeenum_to_str te)
  | OPOnCompletion(onc) -> Printf.sprintf "int %s" (oncompletion_to_str onc)

  | OPBz(t1, s) -> tealop_concat [t1] (Printf.sprintf "bz %s" s)
  | OPBnz(t1, s) -> tealop_concat [t1] (Printf.sprintf "bnz %s" s)
  | OPB(s) -> Printf.sprintf "b %s" s

  | OPOptedIn(t1, t2) -> tealop_concat [t1;t2] "app_opted_in"
  | OPLocalGet(t1, t2) -> tealop_concat [t1;t2] "app_local_get"
  | OPLocalGetEx(t1, t2, t3) -> tealop_concat [t1;t2;t3] "app_local_get_ex"
  | OPLocalPut(t1, t2, t3) -> tealop_concat [t1;t2;t3] "app_local_put"
  | OPGlobalGet(t1) -> tealop_concat [t1] "app_global_get"
  | OPGlobalGetEx(t1, t2) -> tealop_concat [t1;t2] "app_global_get_ex"
  | OPGlobalPut(t1, t2) -> tealop_concat [t1;t2] "app_global_put"

  | OPSnd(t1) -> tealop_concat [t1] "swap\npop"

  | OPErr -> "err"

  | OPNoop -> ""

let rec apply_declarations (dl:decl list) ((s,i):statetype * ide) = match dl with
  | (Declaration(s',_,_,i') as d)::_ when s' = s && i' = i -> d
  | _::tl -> apply_declarations tl (s,i)
  | [] -> failwith "Not found"

let rec comp_exp ?exvars:(exvars=false) (e:exp) (sd:stateenv) (nd:normenv)  : tealop = match e with
  | EInt(n) -> OPInt(n)
  | EString(s) -> OPByte(s)
  | EBool(b) -> if b then OPInt(1) else OPInt(0)
  | EToken(_) -> failwith "todo"
  | EAddress(_) -> failwith "todo"
  | Val(GlobVar(Ide(i))) -> if not exvars then OPGlobalGet(OPByte(i)) else OPGlobalGetEx(OPInt(0), OPByte(i))
  | Val(LocVar(Ide(i), None)) -> if not exvars then OPLocalGet(OPTxn(TFSender), OPByte(i)) else OPLocalGetEx(OPTxn(TFSender), OPInt(0), OPByte(i))
  | Val(LocVar(Ide(i), Some(e))) -> if not exvars then OPLocalGet(comp_exp e sd nd ~exvars, OPByte(i)) else OPLocalGetEx(comp_exp e sd nd ~exvars, OPInt(0), OPByte(i))
  | Val(NormVar(i)) -> NormEnv.apply nd i
  | IBop(op,e1,e2) -> OPIbop(op, comp_exp e1 sd nd ~exvars, comp_exp e2 sd nd ~exvars)
  | LBop(op,e1,e2) -> OPLbop(op, comp_exp e1 sd nd ~exvars, comp_exp e2 sd nd ~exvars)
  | CBop(op,e1,e2) -> OPCbop(op, comp_exp e1 sd nd ~exvars, comp_exp e2 sd nd ~exvars)
  | Not(e) -> OPLNot(comp_exp e sd nd ~exvars)
  | Creator -> OPGlobal(GFCreatorAddress)
  | Caller -> OPTxn(TFSender)
  | Escrow -> if not exvars then OPGlobalGet(OPByte("escrow")) else OPGlobalGetEx(OPInt(0), OPByte("escrow"))

let comp_pattern (p:pattern) (objs:tealop) (sd:stateenv) (nd:normenv) : tealop * normenv =
  let i = (match p with AnyPattern(i) | FixedPattern(_,i) | RangePattern(_,_,i) -> i) in 
  let nd' = NormEnv.try_bind nd i objs in
  let cp = (match p with
    | AnyPattern(_) -> OPNoop
    | FixedPattern(e, _) -> OPCbop(Eq, objs, comp_exp e sd nd ~exvars:true)
    | RangePattern(Some e1, Some e2, _) ->  OPLbop(And, OPCbop(Geq, objs, comp_exp e1 sd nd ~exvars:true), OPCbop(Leq, objs, comp_exp e2 sd nd ~exvars:true))
    | RangePattern(Some e1, None, _) -> OPCbop(Geq, objs, comp_exp e1 sd nd ~exvars:true)
    | RangePattern(None, Some e2, _) -> OPCbop(Leq, objs, comp_exp e2 sd nd ~exvars:true)
    | RangePattern(None, None, _) -> OPNoop) in
  cp, nd'

let rec comp_cmdlist (cl:cmd list) (sd:stateenv) (nd:normenv) : tealop = 
  let comp_cmd c = match c with
    | Assign(GlobVar(Ide(i)), e) -> 
      let cassign = OPGlobalPut(OPByte(i), comp_exp e sd nd) in
      let cchecknotin = OPBnz(OPSnd(OPGlobalGetEx(OPInt(0), OPByte(i))), "fail") in
      let mt = StateEnv.apply sd (Ide i) TGlob in
      if mt = Mutable then cassign
      else OPSeparate("\n", [cchecknotin; cassign])
    | Assign(LocVar(Ide(i), None), e) -> 
      let cassign = OPLocalPut(OPTxn(TFSender), OPByte(i), comp_exp e sd nd) in
      let cchecknotin = OPBnz(OPSnd(OPLocalGetEx(OPTxn(TFSender), OPInt(0), OPByte(i))), "fail") in
      let mt = StateEnv.apply sd (Ide i) TLoc in
      if mt = Mutable then cassign
      else OPSeparate("\n", [cchecknotin; cassign])
    | Assign(LocVar(Ide(i), Some(a)), e) -> 
      let cassign = OPLocalPut(comp_exp a sd nd, OPByte(i), comp_exp e sd nd) in
      let cchecknotin = OPBnz(OPSnd(OPLocalGetEx(comp_exp a sd nd, OPInt(0), OPByte(i))), "fail") in
      let mt = StateEnv.apply sd (Ide i) TGlob in
      if mt = Mutable then cassign
      else OPSeparate("\n", [cchecknotin; cassign]) (* todo refactor code repetition *)
    | Assign(NormVar(Ide(_)), _) -> failwith "can't assign normvars"
    | Ifte(e, cl1, cl2) -> 
      let lblelse = new_label() in
      let lblend = new_label() in
      let cond = comp_exp e sd nd in
      OPSeparate("\n", [OPBz(cond, lblelse); comp_cmdlist cl1 sd nd; OPB(lblend); OPLabel(lblelse); comp_cmdlist cl2 sd nd; OPLabel(lblend)])
  in 
  OPSeparate("\n\n", List.map comp_cmd cl)

let comp_clause (o:clause) (txnid:int) (acid:int) (sd:stateenv) (nd:normenv) : tealop option * tealop option * normenv = 
  let comp_clause_aux o = match o with
    | PayClause(amt,_,xfr,xto) ->
      let check_txntype =  OPCbop(Eq, OPGtxn(txnid, TFTypeEnum), OPTypeEnum(TEPay)) in
      let check_amount, nd = comp_pattern amt (OPGtxn(txnid, TFAmount)) sd nd in
      let check_sender, nd = comp_pattern xfr (OPGtxn(txnid, TFSender)) sd nd in
      let check_receiver, nd = comp_pattern xto (OPGtxn(txnid, TFReceiver)) sd nd in
      let check_remainder = OPCbop(Eq, OPGtxn(txnid, TFCloseRemainderTo), OPGlobal(GFZeroAddress)) in
      [check_txntype; check_amount; check_sender; check_receiver; check_remainder], [], nd

    | CloseClause(_,xfr,xto) ->
      let check_txntype =  OPCbop(Eq, OPGtxn(txnid, TFTypeEnum), OPTypeEnum(TEPay)) in
      let check_amount = OPCbop(Eq, OPGtxn(txnid, TFAmount), OPInt(0)) in
      let check_sender, nd = comp_pattern xfr (OPGtxn(txnid, TFSender)) sd nd in
      let check_remainder, nd = comp_pattern xto (OPGtxn(txnid, TFCloseRemainderTo)) sd nd in
      [check_txntype; check_amount; check_sender; check_remainder], [], nd

    | TimestampClause(t) -> 
      let check_timestamp, nd = comp_pattern t (OPGlobal(GFLatestTimestamp)) sd nd in
      [check_timestamp], [], nd

    | RoundClause(r) -> 
      let check_round, nd = comp_pattern r (OPGlobal(GFRound)) sd nd in
      [check_round], [], nd

    | FromClause(f) ->
      let check_from, nd = comp_pattern f (OPTxn(TFSender)) sd nd in
      [check_from], [], nd

    | AssertClause(e) ->
      [comp_exp e sd nd ~exvars:true], [], nd

    | StateClause(stype,sfr,sto) -> 
      let check_state = (match sfr with
        | Some(Ide(s)) -> 
          if stype = TGlob then OPCbop(Eq, OPGlobalGet(OPByte("gstate")), OPByte(s))
          else OPCbop(Eq, OPLocalGet(OPTxn(TFSender), OPByte("lstate")), OPByte(s))
        | None -> OPNoop) in
      let set_state = (match sto with
        | Some(Ide(s)) ->
          if stype = TGlob then OPGlobalPut(OPByte("gstate"), OPByte(s))  
          else OPLocalPut(OPTxn(TFSender), OPByte("lstate"), OPByte(s))
        | None -> OPNoop) in
      [check_state], [set_state], nd

    | FunctionClause(onc, Ide(fn), pl, cl) ->
      let check_oncomplete =
        if onc = Create then OPCbop(Eq, OPTxn(TFApplicationID), OPInt(0))
        else OPCbop(Eq, OPTxn(TFOnCompletion), OPOnCompletion(onc)) in
        let check_argcount = OPCbop(Eq, OPTxn(TFNumAppArgs), OPInt((List.length pl) + 1)) in
        let check_fn = OPCbop(Eq, OPTxna(TFApplicationArgs, 0), OPByte(fn)) in
      let nd = NormEnv.bind_params nd pl in
      let body = comp_cmdlist cl sd nd in
      [check_oncomplete; check_argcount; check_fn], [body], nd
  in 
  let not_label = Printf.sprintf "aclause_%d" (acid+1) in
  let checks, body, nd = comp_clause_aux o in
  let checks_bz = List.filter_map (fun c -> if c <> OPNoop then Some(OPBz(c, not_label)) else None) checks in
  let head_opt = if checks_bz <> [] then Some(OPSeparate("\n\n", checks_bz)) else None in
  let body_opt = if body <> [] then Some(OPSeparate("\n\n", body)) else None in
  head_opt, body_opt, nd
  
let rec top_to_str top = match top with
  | OPSeparate(sep, topl) -> Printf.sprintf "OPSeparate(%s, %s)" (String.escaped sep) (String.concat ", " (List.map top_to_str topl))
  | _ -> (Batteries.dump top)

let comp_aclause (ao:aclause) (acid:int) (sd:stateenv) = 
  let rec comp_aclause_aux ao txnid head body nd = match ao with 
    | hd::tl -> 
      let nhead,nbody,nd' = (comp_clause hd txnid acid sd nd) in
      let head' = (match nhead with None -> head | Some(nhead) -> head@[nhead]) in
      let body' = (match nbody with None -> body | Some(nbody) -> body@[nbody]) in
      comp_aclause_aux tl txnid head' body' nd'
    | [] -> head, body, nd
  in 
  let txn_count = List.length (List.filter (fun t -> match t with PayClause(_,_,_,_) | CloseClause(_,_,_) | FunctionClause(_,_,_,_) -> true  | _ -> false) ao) in
  let pre_checks = [OPCbop(Eq, OPGlobal(GFGroupSize), OPInt(txn_count))] in
  let pre_label = Printf.sprintf "aclause_%d" acid in
  let skip_label = Printf.sprintf "aclause_%d" (acid+1) in
  let pre_checks_bz = List.filter_map (fun c -> if c <> OPNoop then Some(OPBz(c, skip_label)) else None) pre_checks in
  let head,body,_ = comp_aclause_aux ao 0 [] [] NormEnv.empty in
  let head = [OPLabel(pre_label)]@pre_checks_bz@head in
  let body = body@[OPB("approve")] in
  OPSeparate("\n\n//****************\n\n", [OPSeparate("\n\n", head); OPSeparate("\n\n", body)])

let precomp (p:contract) (sd:stateenv) : contract * stateenv = 
  if not(is_escrow_used p) then p, sd
  else
    let sd' = StateEnv.bind sd (Ide("escrow"), TGlob) Immutable in
    let init_state = get_init_state p in
    let init_escrow_base = [
        FromClause(FixedPattern(Creator, None));
        FunctionClause(NoOp, Ide("init_escrow"), [Parameter(TAddress, Ide("escrow"))], 
          [Assign(GlobVar(Ide("escrow")), Val(NormVar(Ide("escrow"))))])] in
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
    

let comp_contract (p:contract) : string = 
  let rec comp_aclause_list aol idx sd = (match aol with
    | ao::tl -> (comp_aclause ao idx sd)::(comp_aclause_list tl (idx+1) sd)
    | [] -> [OPSeparate("\n\n",[OPLabel(Printf.sprintf "aclause_%d" idx); OPErr; OPLabel("approve"); OPInt(1)])]) in
  let Contract(dl,cl), sd = precomp p StateEnv.empty in
  let sd = StateEnv.bind_decls sd dl in
  let ss = comp_aclause_list cl 0 sd in
  let ss' = OPSeparate("\n\n//////////////////\n\n", ss) in
  tealop_to_str ss'

let test_comp ast = 
  let s = comp_contract ast in
  (* let s = comp_aclause ([PayClause(RangePattern(Some(EInt(3)), Some(EInt(5)), None), FixedPattern(EToken(Algo), None), FixedPattern(Val(GlobVar(Ide("receiver"))),None), AnyPattern(None))]) in *)
  print_endline s;