open Types
open General
open Amlparser
open Amlprinter
open Int
open Static
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
      let _ = s >=> [CallTransaction(afr, ato, NoOp, Ide(fn), pl)] in ()
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

let s, xc, xl = setup 1 [] "
glob int x
glob int y
loc int y

Create create() {}

OptIn opt() {}

NoOp op1(int x) { glob.x = x }

NoOp op2() { glob.y = glob.x }

NoOp op3() { loc.y = 5 }
" 
let xa = List.hd xl 
let testsuite1 = "contract 1 test suite" >::: [
  "op1 into op2" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(xa, xc, NoOp, Ide("op1"), [VInt(5)])]
        >=> [CallTransaction(xa, xc, OptIn, Ide("opt"), [])]
        >=> [CallTransaction(xa, xc, NoOp, Ide("op3"), [])]
    end in
    let aa = State.get_account_ex s xa in
    let v = Account.get_localv_ex aa xc (Ide "y") in
    assert_equal v (VInt(5)) ~printer:string_of_eval);

  test_call_raises "wrong parameter type" s xa xc 
    "op1" [VString("ok")] (Some (Failure "Can't update x: wrong type"));
  test_call_raises "get non initialized var" s xa xc 
    "op2" [] (Some (Failure "Can't get x: ide not initialized"));
  test_call_raises "use local while not opted in" s xa xc 
    "op3" [] (Some (Failure "User not opted in"));
]

(* TEST SUITE 2
 *
 * NON BOUND VARS *)
(* 
let s, xc, xl = setup 1 [] "
glob int x
loc int z

Create create() {}

NoOp op1(int x) { glob.x = loc.z }

NoOp op2(int x) { loc.z = glob.x }

NoOp op3() { loc.z = 15 }
" 
let xa = List.hd xl
let testsuite2 = "contract 2 test suite" >::: [
  test_call_raises "non bound get" s xa xc 
    "op1" [VInt(11)] (Some (Failure "Can't get y: ide not bound"));
  test_call_raises "non bound set" s xa xc 
    "op2" [VInt(22)] (Some (Failure "Can't update y: ide not bound"));
  test_call_raises "use local while not opted" s xa xc 
    "op3" [] (Some (Failure "User not opted in"));
] *)

(* TEST SUITE 3
 *
 * MODULES UNIT TESTS *)

let s, _, xl = setup 2 [] "";;
let xa, xb = (match xl with [xa;xb] -> xa, xb | _ -> failwith "2 Users required")
let aa, ab = State.get_account_ex s xa, State.get_account_ex s xb
let testsuite3 = "3 test suite" >::: [
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

(* TEST SUITE 4
 *
 * TYPE CHECKS *)

let testsuite4 = "r test suite" >::: [
  test_static_error "sum int string" None 
    "glob int x\n Create fn(string y) { glob.x = glob.x + y }" ;
  test_static_error "sum int int" (Some TypeError) 
    "glob int x\n Create fn(int y) { glob.x = glob.x + y }";

  test_static_error "negate string" None 
    "loc bool x\n Create fn(string y) { glob.x = !y }" ;
  test_static_error "negate bool" (Some TypeError) 
    "loc bool x\n Create fn(bool y) { glob.x = !y }";

  test_static_error "and bool string" None 
    "loc bool x\n Create fn(string y) { glob.x = glob.x && y }" ;
  test_static_error "and bool bool" (Some TypeError) 
    "loc bool x\n Create fn(bool y) { glob.x = glob.x && y }";

  test_static_error "leq int string" None 
    "loc bool x\n Create fn(int y, string z) { glob.x = y <= z }" ;
  test_static_error "leq int int" (Some TypeError) 
    "loc bool x\n Create fn(int y, int z) { glob.x = y <= z }";

  test_static_error "if condition int" (Some TypeError)
    "loc bool x\n Create fn(int z) { if (z) {} }";
  test_static_error "if condition int" (None)
    "loc bool x\n Create fn(bool z) { if (z) {} }";
]

let _ = run_test_tt_main testsuite1
(* let _ = run_test_tt_main testsuite2 *)
let _ = run_test_tt_main testsuite3
(* let _ = run_test_tt_main testsuite4 *)