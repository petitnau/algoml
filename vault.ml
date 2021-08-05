open General
open Int
open Amlparser
(* open Amlprinter *)
open Types
open OUnit2

open Comp



let script = parse_file "contracts/vault.aml";;

let _ = test_comp script;;
;;failwith "end";;

let account_a = Account.bind_balance (Account.empty_user()) Algo 100
let address_a = Account.get_address account_a
let account_r = Account.bind_balance (Account.empty_user()) Algo 0
let address_r = Account.get_address account_r
let account_m = Account.bind_balance (Account.empty_user()) Algo 0
let address_m = Account.get_address account_m

let wait_time = 10

let s = State.empty
  >$> account_a
  >$> account_r
  >$> account_m
  >=> [CreateTransaction(address_a, script, [VInt(wait_time); VAddress(address_r)])]

let address_cf = Address.latest()

let s = s
  >=> [PayTransaction(100, Algo, address_a, address_cf)]

let testsuite = "test suite 3" >::: [
  "correct withdraw" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_m)])]
        >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_cf, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 50));

  "double finalize" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_m)])]
        >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_cf, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
        >=> [PayTransaction(50, Algo, address_cf, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 50));

  "withdraw not enough wait" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_m)])]
        >:> (wait_time-1, 10)
        >=> [PayTransaction(50, Algo, address_cf, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 0));

  "canceled withdraw" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_m)])]
        >=> [CallTransaction(address_r, address_cf, NoOp, Ide("cancel"), [])]
        >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_cf, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 0));
    
  "finalize different amt" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(49); VAddress(address_m)])]
        >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_cf, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 0));

  "finalize different addr" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_r)])]
        >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_cf, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 0));

  "finalize no withdraw" >:: (fun _ -> 
    let s = begin
      s >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_cf, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 0));

  "withdraw from not creator" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(address_m, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_m)])]
        >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_cf, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 0));

  "finalize from not creator" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_m)])]
        >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_cf, address_m);
             CallTransaction(address_m, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 0));

  "cancel from not recovery" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_r)])]
        >=> [CallTransaction(address_a, address_cf, NoOp, Ide("cancel"), [])]
        >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_cf, address_r);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_r Algo) (Some 50));
]

let _ = run_test_tt_main testsuite