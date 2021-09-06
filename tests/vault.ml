open General
open Int
open Frontend
(* open Amlprinter *)
open Types
open OUnit2

open! Comp

let script = parse_file "contracts/vaults/vault.aml";;

(* ;;failwith "end";; *)

let account_a = Account.bind_balance (Account.empty_user()) Algo 1000000
let address_a = Account.get_address account_a
let account_r = Account.bind_balance (Account.empty_user()) Algo 0
let address_r = Account.get_address account_r
let account_m = Account.bind_balance (Account.empty_user()) Algo 0
let address_m = Account.get_address account_m
let account_w = Account.bind_balance (Account.empty_user()) Algo 0
let address_w = Account.get_address account_w

let wait_time = 10

let s = State.empty
  >$> account_a
  >$> account_r
  >$> account_m
  >$> account_w
  >=>! [CreateTransaction(address_a, script, Ide("vault"), [VAddress(address_r); VInt(wait_time)])]
let address_cf = Address.latest()

let s = s
  >=>! [PayTransaction(100000, Algo, address_a, address_w);
    CallTransaction(address_a, address_cf, NoOp, Ide("set_escrow"), [VAddress(address_w)])]
  >=>! [PayTransaction(100, Algo, address_a, address_w)]

let testsuite = "test suite 3" >::: [
  "correct withdraw" >:: (fun _ -> 
    let s = begin
      s >=>! [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_m)])]
        >:> (wait_time, 10)
        >=>! [PayTransaction(50, Algo, address_w, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 50));

  "double finalize" >:: (fun _ -> 
    let s = begin
      s >=>! [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_m)])]
        >:> (wait_time, 10)
        >=>! [PayTransaction(50, Algo, address_w, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
        >=> [PayTransaction(50, Algo, address_w, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 50));

  "withdraw not enough wait" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_m)])]
        >:> (wait_time-1, 10)
        >=> [PayTransaction(50, Algo, address_w, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 0));

  "canceled withdraw" >:: (fun _ -> 
    let s = begin
      s >=>! [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_m)])]
        >=>! [CallTransaction(address_r, address_cf, NoOp, Ide("cancel"), [])]
        >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_w, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 0));
    
  "finalize different amt" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(49); VAddress(address_m)])]
        >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_w, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 0));

  "finalize different addr" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_r)])]
        >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_w, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 0));

  "finalize no withdraw" >:: (fun _ -> 
    let s = begin
      s >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_w, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 0));

  "withdraw from not creator" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(address_m, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_m)])]
        >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_w, address_m);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 0));

  "finalize from not creator" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_m)])]
        >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_w, address_m);
             CallTransaction(address_m, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_m Algo) (Some 0));

  "cancel from not recovery" >:: (fun _ -> 
    let s = begin
      s >=> [CallTransaction(address_a, address_cf, NoOp, Ide("withdraw"), [VInt(50); VAddress(address_r)])]
        >=> [CallTransaction(address_a, address_cf, NoOp, Ide("cancel"), [])]
        >:> (wait_time, 10)
        >=> [PayTransaction(50, Algo, address_w, address_r);
             CallTransaction(address_a, address_cf, NoOp, Ide("finalize"), [])]
    end in
    assert_equal (State.apply_balance s address_r Algo) (Some 50));
]

let _ = run_test_tt_main testsuite