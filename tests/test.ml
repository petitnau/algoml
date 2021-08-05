open Types
open General
open Amlparser
open Amlprinter
open Int
open OUnit2

let rec create_accs (s:state) (accnum:int) : state * address list = 
  if accnum > 0 then
    let acc_x = Account.empty_user() in
    let addr_x = Account.get_address acc_x in
    let s' = s >$> acc_x in
    let s'', addresses = create_accs s' (accnum-1) in 
    (s'', addr_x::addresses)
  else
    (s, [])

let setup (accnum:int) (pl:eval list) (code:string)  : state * address * address list = 
  let contract = parse_string code in
  let s = State.empty in
  let s', addrl = create_accs s accnum in
  let s'' = (match addrl with
    | creator::_ -> s' >=> [CreateTransaction(creator, contract, pl)]
    | [] -> failwith "Must create at least one account") in
  let cx = Address.latest() in
  (s'', cx, addrl)

let test_call_raises (name:string) (s:state) (afr:address) (ato:address) (fn:string) (pl:eval list) (ex:exn option) : test = 
  name >:: (fun _ ->
    let f = fun _ ->
      let _ = s >=>! [CallTransaction(afr, ato, NoOp, Ide(fn), pl)] in ()
    in match ex with
    | Some(ex) -> assert_raises ex f
    | None -> f())

let test_calls_raises (name:string) (s:state) (afr:address) (ato:address) (calls:(oncomplete * string * eval list) list) (ex: exn option) : test = 
  let rec do_calls s calls =
    match calls with
    | (onc,fn,pl)::tl ->
      let s' = s >=>! [CallTransaction(afr, ato, onc, Ide(fn), pl)] in
      do_calls s' tl
    | [] -> ()
  in
  name >:: (fun _ ->
    let f = fun _ ->
      let _ = do_calls s calls in ()
    in match ex with
    | Some(ex) -> assert_raises ex f
    | None -> f())

let test_static_error (name:string) (ex:exn option) (code:string) = 
  name >:: (fun _ ->
    let f = fun _ ->
      let _ = parse_string code in ()
    in match ex with
    | Some(ex) -> assert_raises ex f
    | None -> f())

(* TEST SUITE 1
 *
 * ? *)

let s, xc, xl = setup 3 [] "
glob int x
glob int y
glob mut int m
loc int y
loc mut int m

Create create() {}

OptIn opt() {}

NoOp op1(int x) { glob.x = x }

NoOp op2() { glob.y = glob.x }

NoOp op3() { loc.y = 5 }

NoOp op4() { glob.m = 5 }

NoOp op5() { loc.m = 5 }
" 
let x0, x1, x2 = (match xl with [x0;x1;x2] -> x0, x1, x2 | _ -> failwith "3 Users required")
let testsuite1 = "test suite 1" >::: [
  "op1 into op2" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(x0, xc, NoOp, Ide("op1"), [VInt(5)])]
        >=> [CallTransaction(x0, xc, OptIn, Ide("opt"), [])]
        >=> [CallTransaction(x0, xc, NoOp, Ide("op3"), [])]
    end in
    let a0 = State.get_account_ex s x0 in
    let v = Account.get_localv_ex a0 xc (Ide "y") in
    assert_equal v (VInt(5)) ~printer:string_of_eval);

  test_call_raises "Call to non-existent function" s x0 xc
    "op0" [] (Some (CallFail "op0 not found."));
  test_call_raises "Call to existent function but wrong parameters" s x0 xc
    "op1" [] (Some (CallFail "op1 not found."));

  test_call_raises "wrong parameter type" s x0 xc 
    "op1" [VString("ok")] (Some TypeError);
  test_call_raises "get non initialized var" s x0 xc 
    "op2" [] (Some (InitError "Can't get x: ide not initialized"));

  test_call_raises "use local while creator" s x0 xc 
    "op3" [] None;
  test_calls_raises "use local while opted in" s x1 xc 
    [(OptIn,"opt",[]);(NoOp,"op3",[])] None;
  test_call_raises "use local while not opted in" s x2 xc 
    "op3" [] (Some NonOptedError);    

  test_calls_raises "update immutable glob" s x0 xc
    [(NoOp,"op1",[VInt(5)]);(NoOp,"op1",[VInt(5)])] (Some (MutError "Can't update x: immutable variable"));
  test_calls_raises "update mutable glob" s x0 xc
    [(NoOp,"op4",[]);(NoOp,"op4",[])] None;
  test_calls_raises "update immutable loc while creator" s x0 xc
    [(NoOp,"op3",[]);(NoOp,"op3",[])] (Some (MutError "Can't update y: immutable variable"));
  test_calls_raises "update immutable loc while opted" s x1 xc
    [(OptIn,"opt",[]);(NoOp,"op3",[]);(NoOp,"op3",[])] (Some (MutError "Can't update y: immutable variable"));
  test_calls_raises "update mutable loc" s x0 xc
    [(NoOp,"op5",[]);(NoOp,"op5",[])] None;
]

(* TEST SUITE 2
 *
 * MODULES UNIT TESTS *)

let s, _, xl = setup 2 [] "Create create() {}";;
let xa, xb = (match xl with [xa;xb] -> xa, xb | _ -> failwith "2 Users required")
let aa, ab = State.get_account_ex s xa, State.get_account_ex s xb
let testsuite2 = "test suite 2" >::: [
  "get non-existent account" >:: (fun _ ->
    assert_raises (Failure "Account does not exist") (fun _ ->
      State.get_account_ex s (Address 1337)));

  "opt into user account" >:: (fun _ ->
    assert_raises (Failure "Cannot opt into user account") (fun _ ->
      Account.opt_in aa ab));

  "get user account contract" >:: (fun _ ->
    assert_raises (Failure "User accounts do not have a contract") (fun _ ->
      Account.get_contract_ex aa));

  "get user account creator" >:: (fun _ ->
    assert_raises (Failure "User accounts do not have a creator") (fun _ ->
      Account.get_creator_ex aa));

  "get user account globalenv" >:: (fun _ ->
    assert_raises (Failure "User accounts do not have a global env") (fun _ ->
      Account.get_globalenv_ex aa));
    
  "bind user account globalenv" >:: (fun _ ->
    assert_raises (Failure "User accounts do not have a global env") (fun _ ->
      Account.bind_globalenv_ex aa Env.empty));
]

(* TEST SUITE 3
 *
 * TYPE CHECKS *)

let testsuite3 = "test suite 3" >::: [
  test_static_error "sum int string" (Some TypeError)  
    "glob int x\n Create fn(string y) { glob.x = glob.x + y }" ;
  test_static_error "sum int int" None
    "glob int x\n Create fn(int y) { glob.x = glob.x + y }";

  test_static_error "negate string" (Some TypeError)  
    "glob bool x\n Create fn(string y) { glob.x = !y }" ;
  test_static_error "negate bool" None
    "glob bool x\n Create fn(bool y) { glob.x = !y }";

  test_static_error "and bool string" (Some TypeError)  
    "loc bool x\n Create fn(string y) { loc.x = loc.x && y }" ;
  test_static_error "and bool bool" None
    "loc bool x\n Create fn(bool y) { loc.x = loc.x && y }";

  test_static_error "leq int string" (Some TypeError) 
    "loc bool x\n Create fn(int y, string z) { loc.x = y <= z }" ;
  test_static_error "leq int int" None 
    "loc bool x\n Create fn(int y, int z) { loc.x = y <= z }";

  test_static_error "if condition int" (Some TypeError)
    "loc bool x\n Create fn(int z) { if (z) {} }";
  test_static_error "if condition int" (None)
    "loc bool x\n Create fn(bool z) { if (z) {} }";

  test_static_error "glob non-existent" (Some TypeError)
    "loc int x\n Create fn() { glob.x = 7 }";
  test_static_error "glob existent" (None)
    "glob int x\n Create fn() { glob.x = 7 }";

  test_static_error "loc non-existent" (Some TypeError)
    "glob int x\n Create fn() { loc.x = 7 }";
  test_static_error "loc existent" (None)
    "loc int x\n Create fn() { loc.x = 7 }";

  test_static_error "norm non-existent" (Some TypeError)
    "glob int x\n Create fn() { x = 7 }";
  test_static_error "norm existent" (None)
    "Create fn(int x) { x = 7 }";

  test_static_error "no create fun" (Some (Failure "Incorrect amount of create clauses"))
    "NoOp fn() { }";
  test_static_error "no fun in aclause" (Some (Failure "Not all atomic clauses have a function clause"))
    "@close * -> *\n\n Create create() {}";
  test_static_error "duplicate glob ide" (Some (Failure "Duplicate glob ides or loc ides"))
    "glob int x\n glob string x\n Create create() {}";
  test_static_error "duplicate loc ide" (Some (Failure "Duplicate glob ides or loc ides"))
    "loc int z\n loc int z\n Create create() {}";

  test_static_error "reachable states" None
    "@gstate -> a\nCreate create() {}\n\n@gstate a -> b\nNoOp noop() {}";
  test_static_error "unreachable gstate" (Some (Failure "Not all states are reachable"))
    "@gstate a -> b\nCreate create() {}";
  test_static_error "unreachable lstate" (Some (Failure "Not all states are reachable"))
    "@lstate a -> b\nCreate create() {}";
  test_static_error "mixed gstate lstate unerachable" (Some (Failure "Not all states are reachable"))
    "@gstate -> a\nCreate create() {}\n\n@lstate a -> b\nNoOp noop() {}";
  test_static_error "mixed lstate gstate unerachable" (Some (Failure "Not all states are reachable"))
    "@lstate -> a\nCreate create() {}\n\n@gstate a -> b\nNoOp noop() {}";

  test_static_error "double immut static create2" (Some (Failure "doppione glob"))
    "glob int x
        
    Create create() { if (true) {glob.x = 7} else {glob.x = 15} }

    NoOp op2() { glob.x = 8 }";
  test_static_error "double immut static create1" None
    "glob int x
    glob int y
        
    Create create() { if (true) {glob.y = 7} else {glob.x = 15} }

    NoOp op2() { glob.x = 8 }";
  test_static_error "double immut static create" (Some (Failure "doppione glob"))
    "glob int x

    Create create() { glob.x = 7 }

    NoOp op2() { glob.x = 8 }";
]

let _ = run_test_tt_main testsuite1
let _ = run_test_tt_main testsuite2
let _ = run_test_tt_main testsuite3