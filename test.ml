
open Amlparser
(* open Amlprinter *)
open! Comp

let script = parse_file "contracts/amm.aml";;
let _ = test_comp script;;
