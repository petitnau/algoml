# Tinybond 

The contract issues bonds, in the form of ASAs, and allows users to redeem them with interests after a maturity date.
Users can buy bonds in two time periods:
* the standard sale period, where the bond value equals the amount of invested ALGOs (1 bond = 1 ALGO); 
* the presale period, where bonds are sold at a discounted price (1 bond = preSaleRate/100 ALGO).
After the maturity date, users can redeem bonds for ALGOs, at the exchange rate 1 bond = interestRate/100 ALGO.

## Contract state

The global state of the contract consists of the following variables. All of them are fixed at contract creation, with the only exception of `maxDep`, which is  mutable:  
* `COUPON`: the ASA used to represent the bond
* `interestRate`: the interest rate (e.g., 150 means 1.5 multiplication factor, i.e. 50% interest rate)
* `preSaleRate`: the discount rate for the presale (e.g., 150 means that 100 ALGOs buy 150 bond units)
* `preSale`: start of the presale period
* `sale`: start of the sale period
* `saleEnd`: end of the sale period
* `maturityDate`: maturity date
* `maxDep`: upper bound to ALGOs that can be deposited to preserve liquidity.

Each account joining the contract has also a local state, composed by the mutable variable `preSaleAmt`, that represents the amount of bonds reserved in the presale phase.

## Creating the contract

Contract creation is modelled by the following clause:
```java
@newtok $budget of $COUPON -> escrow	// creates a new token
@assert preSale < sale 			// the presale period starts before the sale period
@assert sale < saleEnd 			// the sale period starts before it ends
@assert saleEnd < maturityDate		// the maturity date happens after the sale period has ended
Create tinybond(int preSale, int sale, int saleEnd, int maturityDate,int interestRate, int preSaleRate) {
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
The function body just initializes the variables in the global state with the actual parameters. The `Create` modifier means that the effect of the clause is to create and initialize the contract.

## Joining the presale

The following clause allow investors join the presale. This operation does not require to meet any preconditions. The `OptIn` modifier enables these users to have a local state in the contract. The function body initializes the `preSaleAmt` variable of the local state to zero.
```java
OptIn joinPresale() {
	loc.preSaleAmt = 0
}
```

## Buying bonds

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

## Redeeming bonds

After the maturity date has passed, users that bought bonds in the sale/presale period will be able to sell them at an interest rate of `glob.interestRate`/100. 
```java
@round (glob.maturityDate, )			
@pay $inAmt of glob.COUPON : caller -> escrow	// the caller transfer bond units to the contract...
@pay $outAmt of ALGO : escrow -> caller		// ... and redeems ALGOs with interests
@assert inAmt == outAmt * glob.interestRate / 100
redeem() {}
```

## Disclaimer

The project is not audited and should not be used in a production environment.
