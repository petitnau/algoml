open Frontend
open! Comp

let script = parse_file "contracts/voting.aml";;

let _ = test_comp script;;