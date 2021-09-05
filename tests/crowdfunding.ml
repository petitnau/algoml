open General
open Int
open Frontend
open Amlprinter
open Batteries
open! Comp

let script = parse_file "contracts/crowdfunding.aml";;

(* ;;failwith "end";; *)

let account_a = Account.bind_balance (Account.empty_user()) Algo 100
let address_a = Account.get_address account_a
let account_b = Account.bind_balance (Account.empty_user()) Algo 100
let address_b = Account.get_address account_b
let account_c = Account.bind_balance (Account.empty_user()) Algo 100
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

let s = 
s >=>! [CreateTransaction(address_a, script, Ide("crowdfund"), [
         VInt(start_date);
         VInt(end_date);
         VInt(fund_close_date);
         VInt(goal);
         VAddress(receiver)])]

let address_cf = Address.latest()

let s = 
s >=>! [CallTransaction(address_a, address_cf, OptIn, Ide("optin"), [])]
  >=>! [CallTransaction(address_b, address_cf, OptIn, Ide("optin"), [])]
  >=>! [CallTransaction(address_c, address_cf, OptIn, Ide("optin"), [])]
  >:> (1, start_date + 5)
  (* >?> "Address(0).balance[algo] = 0" *)
  >=>! [PayTransaction(90, Algo, address_a, address_cf);
        CallTransaction(address_a, address_cf, NoOp, Ide("donate"), []);]
  >=>! [PayTransaction(80, Algo, address_b, address_cf);
        CallTransaction(address_b, address_cf, NoOp, Ide("donate"), []);]
  >:> (2, end_date + 5)
  >=>! [PayTransaction(170, Algo, address_cf, address_c);
        CallTransaction(address_c, address_cf, NoOp, Ide("claim"), []);]
  >:> (3, fund_close_date + 5)
;;

print_endline (string_of_state s);
