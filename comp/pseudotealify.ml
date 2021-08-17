open Types
open Tealtypes

let rec tealbinary (e1:tealexp) (e2:tealexp) (op:string) : string = 
  let s1 = tealexp_to_str e1 in
  let s2 = tealexp_to_str e2 in
  Printf.sprintf "%s %s %s" s1 op s2

and tealunary (e1:tealexp) (op:string) : string = 
  let s1 = tealexp_to_str e1 in
  Printf.sprintf "%s %s" op s1

and tealfun (el:tealexp list) (op:string) : string = 
  let sl = List.map tealexp_to_str el in
  Printf.sprintf "%s(%s)" op (String.concat ", " sl)

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

and tealexpd_to_str (ed:tealexpd) : string = match ed with
  | OPLocalGetEx(e1,e2,e3) ->
    let s1 = tealexp_to_str e1 in
    let s2 = tealexp_to_str e2 in
    let s3 = tealexp_to_str e3 in
    Printf.sprintf "loc[%s][%s][%s]" s1 s2 s3
  | OPGlobalGetEx(e1,e2) -> 
    let s1 = tealexp_to_str e1 in
    let s2 = tealexp_to_str e2 in
    Printf.sprintf "loc[%s][%s]" s1 s2
  | OPSwap(ed1) ->
    let s1 = tealexpd_to_str ed1 in
    Printf.sprintf "swap(%s)" s1

and tealexp_to_str (e:tealexp) : string = match e with
  (* | OPSeparate(s, tl) -> String.concat s (List.filter (fun x -> x <> "") (List.map tealop_to_str (List.filter (fun x -> x <> OPNoop) tl))) *)
  | OPComment(s) -> Printf.sprintf "// %s" s

  | OPELiteral(s) -> s
  | OPInt(n) -> Printf.sprintf "%d" n
  | OPByte(s) -> Printf.sprintf "\"%s\"" s
  
  | OPIbop(op, e1, e2) -> 
    let cop = (match op with Sum -> "+" | Diff -> "-" | Mul -> "*" | Div -> "/" | Mod -> "%" | Bor -> "|" | Band -> "&" | Bxor -> "^") in
    tealbinary e1 e2 cop

  | OPCbop(op, e1, e2) -> 
    let cop = (match op with Gt -> ">" | Geq -> ">=" | Lt -> "<" | Leq -> "<=" | Eq -> "==" | Neq -> "!=") in
    tealbinary e1 e2 cop

  | OPLbop(op, e1, e2) ->
    let cop = (match op with And -> "&&" | Or -> "||") in
    tealbinary e1 e2 cop

  | OPLNot(e1) -> tealunary e1 "!"
  | OPBNot(e1) -> tealunary e1 "~"

  | OPLen(e1) -> tealfun [e1] "len"
  | OPItob(e1) -> tealfun [e1] "itob"
  | OPBtoi(e1) -> tealfun [e1] "btoi"

  | OPTxn(tf) -> 
    let ctf = txnfield_to_str tf in
    Printf.sprintf "txn.%s" ctf
  
  | OPTxna(tf, n) ->
    let ctf = txnfield_to_str tf in
    Printf.sprintf "txn.%s[%n]" ctf n

  | OPGtxn(n, tf) ->
    let ctf = txnfield_to_str tf in
    Printf.sprintf "txn[%n].%s" n ctf
  
  | OPGtxna(n1, tf, n2) ->
    let ctf = txnfield_to_str tf in
    Printf.sprintf "txn[%n].%s[%n]" n1 ctf n2

  | OPGlobal(gf) ->
    let cgf = globalfield_to_str gf in
    Printf.sprintf "global.%s" cgf

  | OPTypeEnum(te) -> Printf.sprintf "%s" (typeenum_to_str te)
  | OPOnCompletion(onc) -> Printf.sprintf "%s" (oncompletion_to_str onc)

  | OPOptedIn(e1, e2) -> tealfun [e1;e2] "app_opted_in"
  | OPLocalGet(e1, e2) ->
    let s1 = tealexp_to_str e1 in 
    let s2 = tealexp_to_str e2 in 
    Printf.sprintf "loc[%s][%s]" s1 s2

  | OPLocalExists(e1,e2,e3) | OPPop(OPSwap(OPLocalGetEx(e1,e2,e3))) -> 
    let s1 = tealexp_to_str e1 in 
    let s2 = tealexp_to_str e2 in 
    let s3 = tealexp_to_str e3 in 
    Printf.sprintf "exists(loc[%s][%s][%s])" s1 s2 s3
  (* | OPLocalGetEx(e1, e2, e3) -> tealexp_concat [e1;e2;e3] "app_local_get_ex" *)
  (* | OPLocalPut(e1, e2, e3) -> tealexp_concat [e1;e2;e3] "app_local_put" *)
  | OPGlobalGet(e1) -> 
    let s1 = tealexp_to_str e1 in 
    Printf.sprintf "glob[%s]" s1

  | OPGlobalExists(e1,e2) | OPPop(OPSwap(OPGlobalGetEx(e1, e2))) -> 
    let s1 = tealexp_to_str e1 in 
    let s2 = tealexp_to_str e2 in 
    Printf.sprintf "exists(glob[%s][%s])" s1 s2
       
  | OPPop(ed1) ->
    let s1 = tealexpd_to_str ed1 in
    Printf.sprintf "pop(%s)" s1
  | OPEBz(ed1,s) -> 
    let s1 = tealexpd_to_str ed1 in
    Printf.sprintf "bz('%s', %s)" s s1

  | OPEBnz(ed1,s) -> 
    let s1 = tealexpd_to_str ed1 in
    Printf.sprintf "bnz('%s', %s)" s s1

  | OPGlobalGetTry(_,_) | OPLocalGetTry(_,_,_) -> failwith "these ops should be translated"

  (* | OPGlobalGetEx(e1, e2) -> tealexp_concat [e1;e2] "app_global_get_ex" *)
  (* | OPGlobalPut(e1, e2) -> tealexp_concat [e1;e2] "app_global_put" *)

  (* | OPSnd(e1) -> tealexp_concat [e1] "swap\npop" *)
  (* | OPAssert(e1) -> tealexp_concat [e1] "assert" *)
  (* | OPErr -> "err" *)
  (* | OPCommand(s) -> s *)

  (* | OPNoop -> "" *)
    
and tealcmd_to_str (c:tealcmd) : string = match c with
  | OPLabel(s) -> s^":"
  | OPNoop -> "" 
  | OPCLiteral(s) -> s

  | OPBz(e1,s) -> 
    let s1 = tealexp_to_str e1 in
    Printf.sprintf "bz('%s', %s)" s s1

  | OPBnz(e1,s) -> 
    let s1 = tealexp_to_str e1 in
    Printf.sprintf "bnz('%s', %s)" s s1

  | OPB(s) -> Printf.sprintf "b('%s')" s

  | OPGlobalPut(e1,OPIbop(op, OPGlobalGet(e2), e3)) when e1 = e2 -> 
    let s1 = tealexp_to_str e1 in
    let s3 = tealexp_to_str e3 in
    let cop = (match op with Sum -> "+" | Diff -> "-" | Mul -> "*" | Div -> "/" | Mod -> "%" | Bor -> "|" | Band -> "&" | Bxor -> "^") in
    Printf.sprintf "glob[%s] %s= %s" s1 cop s3

  | OPGlobalPut(e1,e2) -> 
    let s1 = tealexp_to_str e1 in
    let s2 = tealexp_to_str e2 in
    Printf.sprintf "glob[%s] = %s" s1 s2
    
  | OPLocalPut(e1, e2, OPIbop(op, OPLocalGet(e3,e4), e5)) when e1 = e3 && e2 = e4 -> 
    let s1 = tealexp_to_str e1 in
    let s2 = tealexp_to_str e2 in
    let s5 = tealexp_to_str e5 in
    let cop = (match op with Sum -> "+" | Diff -> "-" | Mul -> "*" | Div -> "/" | Mod -> "%" | Bor -> "|" | Band -> "&" | Bxor -> "^") in
    Printf.sprintf "loc[%s][%s] %s= %s" s1 s2 cop s5

  | OPLocalPut(e1,e2,e3) ->
    let s1 = tealexp_to_str e1 in
    let s2 = tealexp_to_str e2 in
    let s3 = tealexp_to_str e3 in
    Printf.sprintf "loc[%s][%s] = %s" s1 s2 s3

  | OPAssert(e1) -> tealfun [e1] "assert"
  | OPReturn(e1) -> 
    let s1 = tealexp_to_str e1 in
    Printf.sprintf "return %s" s1
  | OPErr -> tealfun [] "err"

  | OPSeq(cl) -> String.concat "\n" (List.map tealcmd_to_str (List.filter (function OPNoop -> false | _ -> true) cl))
  | OPAssertSkip(_) | OPIfte(_) -> failwith "these ops should be translated"

and tealblock_to_str (OPBlock(cl1, cl2)) =
  let comp1 = String.concat "\n" (List.map tealcmd_to_str (List.filter (function OPNoop -> false | _ -> true) cl1)) in 
  let comp2 = String.concat "\n" (List.map tealcmd_to_str (List.filter (function OPNoop -> false | _ -> true) cl2)) in
  comp1^"\n\n//*******\n\n"^comp2

and tealprog_to_str (OPProgram(bl)) = 
  String.concat "\n\n//--------------------------------\n\n" (List.map tealblock_to_str bl)
