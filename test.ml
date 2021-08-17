
open Amlparser
(* open Amlprinter *)
open! Comp

let script = parse_string
"glob int roundLimit
glob token cafe
loc mut int bought

Create shop(int roundLimit, token cafe) {
	glob.roundLimit = roundLimit
	glob.cafe = cafe
	loc.bought = 0
}

OptIn optin() {
	loc.bought = 0
}

@pay $algoAmount ALGO : caller -> escrow
@pay $cafeAmount glob.cafe : escrow -> caller
@assert algoAmount*2 == cafeAmount*3 
NoOp buy() {
	loc.bought += cafeAmount
}

@round (, glob.roundLimit)
@pay $algoAmount ALGO : escrow -> caller
@pay (, loc.bought)$cafeAmount glob.cafe : caller -> escrow
@assert algoAmount*2 == cafeAmount*3 
NoOp refund() {
	loc.bought -= cafeAmount
}

@round (glob.roundLimit, )
@close ALGO : escrow -> creator
@close glob.cafe: escrow -> creator
@from creator
Delete delete() {}";;
let _ = test_comp script;;
