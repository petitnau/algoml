open Ast
open Parse
open General
open Modules
open Batteries

let crowdfunding_script = parse()

let account_a = Account.bind_balance (Account.empty_user()) Algo (Some(100))
let address_a = Account.get_address account_a
let account_b = Account.bind_balance (Account.empty_user()) Algo (Some(100))
let address_b = Account.get_address account_b
let account_c = Account.bind_balance (Account.empty_user()) Algo (Some(100))
let address_c = Account.get_address account_c

let s' = State.empty
let s'' = State.bind s' account_a
let s''' = State.bind s'' account_b
let s = State.bind s''' account_c

let start_date = 10
let end_date = 20
let fund_close_date = 30
let goal = 100
let receiver = address_c

let s = run_op(s, Transaction([
  CreateTransaction(address_a, crowdfunding_script, [
                    VInt(start_date);
                    VInt(end_date);
                    VInt(fund_close_date);
                    VInt(goal);
                    VAddress(receiver)])]))

let address_cf = Address.latest()

let s = run_op(s, Transaction([
  CallTransaction(address_a, address_cf, OptIn, Ide("optin"), [])
]))
let s = run_op(s, Transaction([
  CallTransaction(address_b, address_cf, OptIn, Ide("optin"), [])
]))
let s = run_op(s, Transaction([
  CallTransaction(address_c, address_cf, OptIn, Ide("optin"), [])
]))

let s = run_op(s, Wait(1, start_date + 5))

let s = run_op(s, Transaction([
  PayTransaction(90, Algo, address_a, address_cf);
  CallTransaction(address_a, address_cf, NoOp, Ide("donate"), []);
]))

let s = run_op(s, Transaction([
  PayTransaction(80, Algo, address_b, address_cf);
  CallTransaction(address_b, address_cf, NoOp, Ide("donate"), []);
]))

let s = run_op(s, Wait(2, end_date + 5))

let s = run_op(s, Transaction([
  PayTransaction(170, Algo, address_cf, address_c);
  CallTransaction(address_c, address_cf, NoOp, Ide("claim"), []);
]))

let s = run_op(s, Wait(3, fund_close_date + 5))

(* let s = run_op(s, Transaction([
  CloseTransaction(Algo, address_b, address_cf);
  CallTransaction(address_b, address_cf, NoOp, Ide("claim"), []);
])) *)
;;

let a1 = (State.get_account_ex s address_a) in
let a2 = (State.get_account_ex s address_b) in
let a3 = (State.get_account_ex s address_c) in
(* let ac = (State.get_account_ex s address_cf) in *)
print_endline (dump (Account.apply_balance a1 Algo));
print_endline (dump (Account.apply_balance a2 Algo));
print_endline (dump (Account.apply_balance a3 Algo));
print_endline (dump (Account.apply_balance (State.get_account_ex s (Address 3)) Algo));