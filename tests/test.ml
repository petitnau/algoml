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
let testsuite1 = "test suite 1" >::: [
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
 * MODULES UNIT TESTS *)

let s, _, xl = setup 2 [] "";;
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
]

let _ = run_test_tt_main testsuite1
let _ = run_test_tt_main testsuite2
let _ = run_test_tt_main testsuite3