# Automated Market Makers 

Automated Market Makers (AMMs) are decentralized applications that allow digital assets to be traded in a permissionless way by using liquidity pools rather than traditional market of buyers and sellers. In this use case we specify in AlgoML a constant-product AMM, inspired by [Uniswap2](https://docs.uniswap.org/protocol/v2/introduction). Our specification follows closely the transition system defined in [[BCL22]](#references).

## Contract state

The contract state consists of the following variables:

Global variables:

* `t0` and `t1` are the two tokens traded in the AMM
* `r0` and `r1` are the reserves of `t0` and `t1` stored in the AMM
* `minted_t` is the token minted by the contract
* `minted_supply` is the circulating amount of `minted_t` (the minted units not held by the AMM)

Local variables:

* `t0_reserved` and `t1_reserved` are the amounts of `t0`/`t1` that can be redeemed by the user
* `minted_reserved` is the amount of `minted_t` that can be redeemed by the user

## Creating the AMM

Any user can create an AMM by providing the two tokens types `t0` and `t1` that are going to be traded, while also providing their initial reserves. The creator will receive a certain amount of minted tokens in return.
```java
@pay $v0 of t0 : caller -> escrow
@pay $v1 of t1 : caller -> escrow
@newtok $minted_t -> escrow  
@pay $minted_v of minted_t : escrow -> caller
@assert t0 != t1
Create amm(token t0, token t1) {
    glob.t0 = t0
    glob.t1 = t1
    glob.minted_t = minted_t
    glob.r0 = v0
    glob.r1 = v1
    glob.minted_supply = minted_v
}
```

To call the function, the creator must deposit seme amount of `t0` and `t1` to the contract. 
Further, the creator must create a new token (with the highest possible amount of units), which will be stored in the contract. 
In return, the creator receives some amount of the minted token `minted_t` from the contract. 
The actual amount of `minted_t` units received is irrelevant, so the creator is free to choose any amount.

## Opting in

To be able to interact with the AMM, users must first opt into the contract.
The modifier `Optin` provides joined users with a local state. 
```java
OptIn optin() {
    loc.t0_reserved = 0
    loc.t1_reserved = 0
    loc.minted_reserved = 0
}
```

## Deposit

Users can deposit tokens into the AMM as long as doing so preserves the ratio of the token reserves in the AMM. 
In return, they will receive a certain amount of minted tokens, equal to the ratio between the deposited amount of `r0` and the *redeem rate* (the ratio between `r0` and the `minted_supply`)

Since the ratio between the token reserves can change unpredictably upon swap operations, specifying an exact amount of units of `t0` and `t1` to deposit could make the deposit operation never enabled.
To overcome this issue, the `deposit` clause allows users to specify a *lower bound* on the amount of `t0` and `t1` in the function parameters, 
and to actually deposit an *upper bound* through the `@pay` preconditions.
```java
@pay $v0_highb of glob.t0 : * -> escrow
@pay $v1_highb of glob.t1 : * -> escrow
@assert v1_lowb <= v0_highb * glob.r1 / glob.r0 
@assert v0_highb * glob.r1 / glob.r0 <= v1_highb 
dep(int v0_lowb, int v1_lowb) {
    loc.t0_reserved = v0_highb - (v0_highb * glob.r1 / glob.r0)
    glob.minted_supply += v1_highb / glob.r1 * glob.minted_supply
    loc.minted_reserved += v1_highb / glob.r1 * glob.minted_supply
}
```

```java
@pay $v0_highb of glob.t0 : * -> escrow
@pay $v1_highb of glob.t1 : * -> escrow
@assert v0_lowb <= v1_highb * glob.r0 / glob.r1 
@assert v1_highb * glob.r0 / glob.r1 <= v0_highb 
dep(int v0_lowb, int v1_lowb) {
    loc.t1_reserved = v1_highb - (v1_highb * glob.r0 / glob.r1)
    glob.minted_supply += v0_highb / glob.r0 * glob.minted_supply
    loc.minted_reserved += v0_highb / glob.r0 * glob.minted_supply
}
```

The difference between the paid upper bounds and the actual units that will be deposited in the AMM is recorded in the local state
(in variables `t0_reserved` and `t0_reserved`), and can be redeemed later on through the `get_excess` clauses.
The same holds for the units of minted tokens obtained upon the deposit, which are recorded in the local variable `minted_reserved`.
```java
@pay loc.minted_reserved of glob.minted_t : escrow -> *   
get_excess() {
    loc.minted_reserved = 0
}

@pay loc.t0_reserved of glob.t0 : escrow -> *
get_excess() {
    loc.t0_reserved = 0
}

@pay loc.t1_reserved of glob.t1 : escrow -> *
get_excess() {
    loc.t1_reserved = 0
}
```
Each of those clauses requires that the caller is receiving a payment from the contract of the reserved amount of that chosen token.
When called, the reserved amount of the token is set to 0.

## Swap

The following clause allows users to swap units of `t0` in their wallet for units of `t1` in the AMM.
Our AMM adopts the the constant-product swap rate function implemented by Uniswap2, 
which requires the product of reserves of `t0` and `t1` in the AMM to be preserved by swaps.
The parameter `lowb` is a lower bound on the amount of units of `t1` they aim to receive. 
The `@assert` clause ensures that the amount of output tokens of `t1` exceeds this lower bound.
```java
@pay $v0 of glob.t0 : * -> escrow
@assert (glob.r1 * v0) / (glob.r0 + v0) >= lowb && lowb > 0
swap(int lowb) {
	loc.t1_reserved += (glob.r1 * v0) / (glob.r0 + v0)
	glob.r1 -= (glob.r1 * v0) / (glob.r0 + v0)
	glob.r0 += v0
}
```
The reserved output tokens can be redeemed by executing the clause `get_excess` shown before.

Swaps in the opposite direction are achieved through the following clause: 
```java
@pay $v1 of glob.t1 : * -> escrow
@assert (glob.r0 * v1) / (glob.r1 + v1) >= lowb && lowb > 0
swap(int lowb) {
	loc.t0_reserved += (glob.r0 * v1) / (glob.r1 + v1)
	glob.r0 -= (glob.r0 * v1) / (glob.r1 + v1)
	glob.r1 += v1
}
```

## Redeem

Users can redeem units of the minted token for units of the underlying tokens `t0` and `t1` through the following clause: 
```java
@pay $v of glob.minted_t : * -> escrow
@assert v * glob.r0 / glob.minted_supply >= v0_lowb && v0_lowb > 0
@assert v * glob.r1 / glob.minted_supply >= v1_lowb && v1_lowb > 0
redeem(int v0_lowb, int v1_lowb) {
    glob.r0 -= v * glob.r0 / glob.minted_supply
    glob.r1 -= v * glob.r1 / glob.minted_supply
    loc.t0_reserved += v * glob.r0 / glob.minted_supply
    loc.t1_reserved += v * glob.r1 / glob.minted_supply
    glob.minted_supply -= v
}
```

The `redeem` function is parameterized over the lower bounds of the units of tokens `t0` and `t1` that the user wants to obtain upon the redeem. 
The `@assert` preconditions ensure that these two lower are must be respected. 
The reserved output tokens can be redeemed by executing the clause `get_excess` shown before.
Upon execution, the clause decreases the `minted_supply`, to correctly keep track of the amount units of the minted tokens circulating among users.


## References

- **[BCL21]** Massimo Bartoletti, James Hsin-yu Chiang and Alberto Lluch-Lafuente. [Maximizing Extractable Value from Automated Market Makers](https://arxiv.org/pdf/2106.01870.pdf). Financial Cryptography, 2022
- **[BCL22]** Massimo Bartoletti, James Hsin-yu Chiang and Alberto Lluch-Lafuente. [A theory of Automated Market Makers in DeFi](https://arxiv.org/abs/2102.11350). Submitted, 2022

## Disclaimer

The project is not audited and should not be used in a production environment.
