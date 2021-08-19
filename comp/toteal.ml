open Types
open Tealtypes
open Togeneric

let rec tealexp_concat (el:tealexp list) (op:string) : string = 
  let cl = List.map tealexp_to_str el in
  String.concat "\n" (cl@[op])

and tealexpd_to_str (ed:tealexpd) : string = match ed with
  | OPLocalGetEx(e1,e2,e3) -> tealexp_concat [e1;e2;e3] "app_local_get_ex"
  | OPGlobalGetEx(e1,e2) -> tealexp_concat [e1;e2] "app_global_get_ex"
  | OPSwap(ed1) -> (tealexpd_to_str ed1)^"\n"^"swap"

and tealexp_to_str (e:tealexp) : string = match e with
  (* | OPSeparate(s, tl) -> String.concat s (List.filter (fun x -> x <> "") (List.map tealop_to_str (List.filter (fun x -> x <> OPNoop) tl))) *)
  | OPComment(s) -> Printf.sprintf "// %s" s

  | OPELiteral(s) -> s
  | OPInt(n) -> Printf.sprintf "int %d" n
  | OPByte(s) -> Printf.sprintf "byte \"%s\"" s
  
  | OPIbop(op, e1, e2) -> 
    let cop = (match op with Sum -> "+" | Diff -> "-" | Mul -> "*" | Div -> "/" | Mod -> "%" | Bor -> "|" | Band -> "&" | Bxor -> "^") in
    tealexp_concat [e1;e2] cop

  | OPCbop(op, e1, e2) -> 
    let cop = (match op with Gt -> ">" | Geq -> ">=" | Lt -> "<" | Leq -> "<=" | Eq -> "==" | Neq -> "!=") in
    tealexp_concat [e1;e2] cop

  | OPLbop(op, e1, e2) ->
    let cop = (match op with And -> "&&" | Or -> "||") in
    tealexp_concat [e1;e2] cop

  | OPLNot(e1) -> tealexp_concat [e1] "!"
  | OPBNot(e1) -> tealexp_concat [e1] "~"

  | OPLen(e1) -> tealexp_concat [e1] "len"
  | OPItob(e1) -> tealexp_concat [e1] "itob"
  | OPBtoi(e1) -> tealexp_concat [e1] "btoi"

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

  | OPGaid(n1) ->
    Printf.sprintf "gaid %d" n1

  | OPGlobal(gf) ->
    let cgf = globalfield_to_str gf in
    Printf.sprintf "global %s" cgf

  | OPTypeEnum(te) -> Printf.sprintf "int %s" (typeenum_to_str te)
  | OPOnCompletion(onc) -> Printf.sprintf "int %s" (oncompletion_to_str onc)

  | OPOptedIn(e1, e2) -> tealexp_concat [e1;e2] "app_opted_in"
  | OPLocalGet(e1, e2) -> tealexp_concat [e1;e2] "app_local_get"
  | OPLocalExists(e1,e2,e3) -> tealexp_concat [e1;e2;e3] "app_local_get_ex\nswap\npop"
  (* | OPLocalGetEx(e1, e2, e3) -> tealexp_concat [e1;e2;e3] "app_local_get_ex" *)
  (* | OPLocalPut(e1, e2, e3) -> tealexp_concat [e1;e2;e3] "app_local_put" *)
  | OPGlobalGet(e1) -> tealexp_concat [e1] "app_global_get"
  | OPGlobalExists(e1,e2) -> tealexp_concat [e1;e2] "app_global_get_ex\nswap\npop"

  | OPGlobalGetTry(_,_) | OPLocalGetTry(_,_,_) -> failwith "these ops should be translated"

  | OPPop(ed1) -> (tealexpd_to_str ed1)^"\n"^"pop"
  | OPEBz(ed1,s) -> (tealexpd_to_str ed1)^"\n"^("bz "^s)
  | OPEBnz(ed1,s) -> (tealexpd_to_str ed1)^"\n"^("bnz "^s)
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

  | OPBz(e1,s) -> tealexp_concat [e1] ("bz "^s)
  | OPBnz(e1,s) -> tealexp_concat [e1] ("bnz "^s)
  | OPB(s) -> ("b "^s)

  | OPGlobalPut(e1,e2) -> tealexp_concat [e1;e2] "app_global_put"
  | OPLocalPut(e1,e2,e3) -> tealexp_concat [e1;e2;e3] "app_local_put"

  | OPAssert(e1) -> tealexp_concat [e1] "assert"
  | OPReturn(e1) -> tealexp_concat [e1] "return"
  | OPErr -> "err"

  | OPSeq(cl) -> String.concat "\n\n" (List.map tealcmd_to_str (List.filter (function OPNoop -> false | _ -> true) cl))
  | OPAssertSkip(_) | OPIfte(_) -> failwith "these ops should be translated"

and tealblock_to_str (OPBlock(cl1, cl2)) =
  let comp1 = String.concat "\n\n" (List.map tealcmd_to_str (List.filter (function OPNoop -> false | _ -> true) cl1)) in 
  let comp2 = String.concat "\n\n" (List.map tealcmd_to_str (List.filter (function OPNoop -> false | _ -> true) cl2)) in
  comp1^"\n\n//*******\n\n"^comp2

and tealprog_to_str (OPProgram(bl)) = 
  String.concat "\n\n//--------------------------------\n\n" (List.map tealblock_to_str bl)
