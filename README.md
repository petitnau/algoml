# AlgoML

AlgoML (after *Algorand Modelling Language*) is a DSL for specifying Algorand smart contracts, which compiles into TEAL scripts.

Roughly, an AlgoML specification is a sequence of clauses of the form:
```java
@precondition1
...
@preconditionK
foo(x1,...,xn) {
  // state update
  ...
}
```
The intuition is that the function ``foo`` is enabled whenever all the preconditions are respected. Executing ``foo`` results in a state update, specified in the function body. Preconditions may have various forms: for instance, they can be predicates on the contract state, or checks that certain transactions belong to the group wherein the function is called.

On a lower level, an AlgoML program models two contracts: a stateful application, and a stateless contract account. The stateful application is in charge of all of the contract logic, while the stateless contract acts as an escrow, which holds funds and releases them according to the logic of the stateful contract.

Examples of AlgoML preconditions are:
```java
@round (from,to)
```
This precondition holds when the function is called from round `from` (included) to round `to` (excluded). It is also possible, like in many other clauses, to not only check if the round is in a certain range, but also to bind a variable to the current round.
```java
@round (from,to)$curr_round
```
This precondition, for example, both checks that the current round is between the values `from` and `to`, and binds the `curr_round` variable to the current round. 
 
```java 
@assert exp 
```
This precondition holds only when the boolean expression `exp` evaluates to true.

```java
@newtok amt of $tok -> escrow
```
Holds when a new token of amt units is minted, and all its units are stored in the contract. The variable `tok` is bound to the number to the token identifier.

```java
@pay (min,max)$amt of tok : sender -> receiver
``` 
Holds when a number of units of token `tok` in the range `(min,max)` are transferred from `sender` to `receiver`. The variable `amt` is bound to the actual amount of transferred units. The token `tok` can be ALGO or an ASA. The parameters `sender` and `receiver` can be arbitrary accounts, or the special accounts `caller` (the account which is calling the function) and `escrow` (the escrow which is handling the contract funds).

```java
@gstate oldstate -> newstate
```
Holds when the current contract state is `oldstate`. After executing the function, the state takes a transition to `newstate`.

## AlgoML by examples: tinybond

We illustrate some of the AlgoML features by applying it to implement a simple bond.
The contract issues bonds, in the form of ASAs, and allows users to redeem them with interests after a maturity date.
Users can buy bonds in two time periods:
* the standard sale period, where the bond value equals the amount of invested ALGOs (1 bond = 1 ALGO); 
* the presale period, where bonds are sold at a discounted price (1 bond = preSaleRate/100 ALGO).
After the maturity date, users can redeem bonds for ALGOs, at the exchange rate 1 bond = interestRate/100 ALGO.

The global state of the contract consists of the following variables. All of them are fixed at contract creation, with the only exception of `maxDep`, which is made mutable by the modifier `mut`:  
```java
glob token COUPON	// the ASA used to represent the bond
glob int interestRate   // interest rate (e.g., 150 means 1.5 multiplication factor, i.e. 50% interest rate)
glob int preSaleRate    // discount rate for the presale (e.g., 150 means that 100 ALGOs buy 150 bond units)
glob int preSale	// start of the presale period
glob int sale		// start of the sale period
glob int saleEnd	// end of the sale period
glob int maturityDate	// maturity date
glob mut int maxDep	// upper bound to ALGOs that can be deposited to preserve liquidity
```

Each account joining the contract has also a local state, composed by a single mutable variable:
```java
loc mut int preSaleAmt
```

Contract creation is modelled by the following clause:
```java
@newtok $budget of $COUPON -> escrow	// creates a new token
@assert preSale < sale 			// the presale period starts before the sale period
@assert sale < saleEnd 			// the sale period starts before it ends
@assert saleEnd < maturityDate		// the maturity date happens after the sale period has ended
Create create(
    int preSale, int sale, int saleEnd, int maturityDate,
    int interestRate, int preSaleRate
) {
	glob.preSale = preSale
	glob.sale = sale
	glob.saleEnd = saleEnd
	glob.maturityDate = maturityDate
	glob.interestRate = interestRate
	glob.preSaleRate = preSaleRate
	glob.COUPON = COUPON
	glob.maxDep = budget
}
```

The following clause allow investors join the presale. This operation does not require to meet any preconditions. The `OptIn` modifier enables these users to have a local state in the contract. The function body initializes the `preSaleAmt` variable of the local state to zero.
```java
OptIn joinPresale() {
	loc.preSaleAmt = 0
}
```

The following clause allows users to buy bonds in the presale period. The effect of the function is just to set the number of bought units in the 
local state of the investor. The actual transfer of tokens will be finalised in the sale period (see the next clause).
```java
@round (glob.preSale, glob.sale)		// presale period
@pay $amt of ALGO : caller -> escrow		// transfer ALGOs to the contract to reserve bond units
@assert amt * glob.preSaleRate / 100 <= glob.maxDep
deposit() {
	loc.preSaleAmt += amt * glob.preSaleRate / 100
	glob.maxDep -= amt * glob.preSaleRate / 100
}
```

The following clause allows users to buy bonds in the regular sale period. If the user has previously bought some units in the presale, they will receive the bought amount here. 
```java
@round (glob.sale, glob.saleEnd)		// sale period
@pay $inAmt of ALGO : caller -> escrow		// transfer additional ALGOs to the contract to buy bond units
@pay $outAmt of glob.COUPON : escrow -> caller	// transfer bond units from the contract to the caller
@assert inAmt + loc.preSaleAmt == outAmt	// outAmt is the actual number of transferred bond units
deposit() {
	loc.preSaleAmt = 0
}
```

After the maturity date has passed, users that bought bonds in the sale/presale period will be able to sell them at an interest rate of `glob.interestRate`/100. 
```java
@round (glob.maturityDate, )			
@pay $inAmt of glob.COUPON : caller -> escrow	// the caller transfer bond units to the contract...
@pay $outAmt of ALGO : escrow -> caller		// ... and redeems ALGOs with interests
@assert inAmt == outAmt * glob.interestRate / 100
redeem() {}
```

To compile the tinybond contract, follow the instructions in the [Using the AlgoML compiler](#using-the-algoml-compiler) section. 


## AlgoML use cases

We illustrate the usage of AlgoML on some relevant use cases:
- [Automated Market Makers](contracts/amm)
- [Crowdfunding](contracts/crowdfund)
- [2-players lottery](contracts/lottery)
- [King of the Algo Throne](contracts/kotat)
- [Tinybond](contracts/tinybond)
- [Vaults](contracts/vaults)
- [Voting](contracts/voting)

## Building AlgoML

1\. Clone the AlgoML repository
```
git clone https://github.com/petitnau/algoml
```
2\. [Install opam](https://ocaml.org/docs/install.html#OPAM) 

3\. Install dune
```
opam install dune
```
4\. Install AlgoML dependencies
```
opam install algoml --deps-only
```
5\. Build the source
```
dune build
```
6\. Create AlgoML contracts! Syntax highlighting is supported on [vscode](https://marketplace.visualstudio.com/items?itemName=RobertoPettinau.algoml-lang) 


## Using the AlgoML compiler

To compile an AlgoML file into TEAL scripts, the following command can be used:
```console
dune exec ./amlc.exe /path/to/input.aml [-o outprefix]
```
The compiler will output three files in the folder where the command is launched:
* `output_approval.teal`, the TEAL code of the stateful contract;
* `output_escrow.teal`, the TEAL code of the stateless contract used as escrow;
* `output_clear.teal`, the TEAL code run upon a clearstate operation.

For example, to compile the tinybond contract, enter the following command from the algoml folder:
```console
dune exec ./amlc.exe contracts/tinybond/tinybond.aml
```

## Disclaimer

The project is not audited and should not be used in a production environment.

## Credits

AlgoML has been designed by Roberto Pettinau and Massimo Bartoletti from the University of Cagliari, Italy.
