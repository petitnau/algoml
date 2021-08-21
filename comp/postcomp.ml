open Tealtypes

let label_count = ref (-1)
let new_label () = label_count := 1 + !label_count; Printf.sprintf "lbl_%d" (!label_count)

let rec post_comp_exp (bout:string) (checkex:bool) (e:tealexp)  = 
  let post_comp_exp = post_comp_exp bout checkex in
  match e with  
  | OPIbop(op, e1, e2) -> OPIbop(op, post_comp_exp e1, post_comp_exp e2)
  | OPCbop(op, e1, e2) -> OPCbop(op, post_comp_exp e1, post_comp_exp e2)
  | OPLbop(op, e1, e2) -> OPLbop(op, post_comp_exp e1, post_comp_exp e2)
  | OPLNot(e1) -> OPLNot(post_comp_exp e1)
  | OPBNot(e1) -> OPBNot(post_comp_exp e1)
  | OPLen(e1) -> OPLen(post_comp_exp e1)
  | OPItob(e1) -> OPItob(post_comp_exp e1)
  | OPBtoi(e1) -> OPBtoi(post_comp_exp e1)
  | OPOptedIn(e1,e2) -> OPOptedIn(post_comp_exp e1, post_comp_exp e2)
  | OPLocalGet(e1,e2) -> OPLocalGet(post_comp_exp e1, post_comp_exp e2)
    (* if not(checkex) then OPLocalGet(post_comp_exp e1, post_comp_exp e2) *)
    (* (* Not exp -> *) else OPSeq([OPBnz(OPLocalGetEx(OPInt(0), post_comp_exp e1, post_comp_exp e2), "LAB")]@(pops)@[OPB(bout); OPLabel("LAB")]) *)
  | OPLocalExists(e1,e2,e3) -> OPPop(OPSwap(OPLocalGetEx(post_comp_exp e1, post_comp_exp e2, post_comp_exp e3)))
  | OPLocalGetTry(e1,e2,e3) -> OPEBz(OPLocalGetEx(post_comp_exp e1, post_comp_exp e2, post_comp_exp e3), bout)
  | OPGlobalGet(e1) -> OPGlobalGet(post_comp_exp e1)
  | OPGlobalExists(e1,e2) -> OPPop(OPSwap(OPGlobalGetEx(post_comp_exp e1, post_comp_exp e2)))
  | OPGlobalGetTry(e1,e2) -> OPEBz(OPGlobalGetEx(post_comp_exp e1, post_comp_exp e2), bout)
  | e -> e

let rec post_comp_cmd (bout:string) (checkex:bool) (c:tealcmd) = 
  let post_comp_exp = post_comp_exp bout checkex in
  let post_comp_cmd = post_comp_cmd bout checkex in
  (* let rec exps = (match c with
    | OPBz(e1,_) | OPBnz(e1,_) | OPAssert(e1) | OPAssertSkip(e1) | OPReturn(e1) -> [e1]
    | OPGlobalPut(e1,e2) -> [e1;e2]
    | OPLocalPut(e1,e2,e3) -> [e1;e2;e3]
    | OPIfte(e1,cl1,cl2) -> [e1]@() *)
  match c with 
  | OPIfte(e1,c1,c2) -> 
    let lblelse = new_label() in
    let lblout = new_label() in
    OPSeq([OPBz(post_comp_exp e1, lblelse); post_comp_cmd c1; OPB(lblout); OPLabel(lblelse); post_comp_cmd c2; OPLabel(lblout)])
  | OPAssertSkip(e1) -> OPBz(post_comp_exp e1, bout)
  | OPBz(e1,s) -> OPBz(post_comp_exp e1, s)
  | OPBnz(e1,s) -> OPBnz(post_comp_exp e1, s)
  | OPLocalPut(e1,e2,e3) -> OPLocalPut(post_comp_exp e1, post_comp_exp e2, post_comp_exp e3)
  | OPGlobalPut(e1,e2) -> OPGlobalPut(post_comp_exp e1, post_comp_exp e2)
  | OPSeq(cl) -> OPSeq(List.map post_comp_cmd cl)
  | OPAssert(e1) -> OPAssert(post_comp_exp e1)
  | OPReturn(e1) -> OPReturn(post_comp_exp e1)
  | c -> c

let post_comp_cmdl (bout:string) (checkex:bool) (cl:tealcmd list) = List.map (post_comp_cmd bout checkex) cl
let post_comp_block (bnum:int) (OPBlock(cl1, cl2):tealblock) =
  let cl1 = post_comp_cmdl (Printf.sprintf "aclause_%d" (bnum+1)) true cl1 in
  let cl2 = post_comp_cmdl "fail" false cl2 in
  OPBlock((OPLabel(Printf.sprintf "aclause_%d" bnum))::cl1, cl2@[OPReturn(OPInt(1))])

let post_comp (clearprog:bool) (OPProgram(bl):tealprog) = 
  let rec post_comp_aux idx bl acc = match bl with
    | hd::tl -> post_comp_aux (idx+1) tl (acc@[post_comp_block idx hd])
    | [] -> OPProgram(acc)
  in
  let bl = if clearprog then bl else   
  [OPBlock([OPAssertSkip(OPCbop(Eq, OPTxn(TFApplicationID), OPInt(0)))],[
    OPGlobalPut(OPByte("gstate"), OPByte("@created"))
  ])]@bl
  in
  post_comp_aux 0 (bl@[OPBlock([], [OPLabel("fail"); OPErr])]) []

let post_comp_escrow cl = post_comp_cmd "" false cl