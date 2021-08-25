# Automatic Market Maker 

This contract is an AlgoML version of the AMMs described in [this whitepaper](https://arxiv.org/pdf/2106.01870.pdf) by Massimo Bartoletti, James Hsin-yu Chiang and Alberto Lluch-Lafuente.

Automated Market Makers are decentralized applications that allow digital assets to be traded in a permissionless way by using liquidity pools rather than traditional market of buyers and sellers.

## Contract state

The contract state is stored in the following variables:

Global variables:

* `t0` and `t1` are the two tokens traded in the AMM
* `ro` and `r1` are the amount of `t0` and `t1` stored in the AMM
* `minted_t` is the token minted by the contract
* `minted_supply` is the circulating amount of `minted_t` (the minted units not held by the AMM)

Local variables:

* `t0_reserved` and `t1_reserved` are the amount of `t0`/`t1` that can be redeemed by the user
* `minted_reserved` is the amount of `minted_t` that can be redeemed by the user

## Escrow account 

The escrow account used by the AMM is a stateless contract that releases assets provided that:
1. the stateful contract participates in the transaction group
2. the escrow does not pay any transaction fees
3. the escrow does not send a rekey transaction

## Creating the AMM

Any user can create an AMM by providing the two tokens (namely t0 and t1) that are going to be traded, while also sending some amount of both. The creator in return, will receive a certain amount of minted tokens.

```java
@pay $v0 of t0 : caller -> escrow
@pay $v1 of t1 : caller -> escrow
@newtok 1000000 of $minted_t -> escrow  
@pay $minted_v of minted_t : escrow -> caller
Create amm(token t0, token t1) {
    glob.t0 = t0
    glob.t1 = t1
    glob.minted_t = minted_t
    glob.r0 = v0
    glob.r1 = v1
    glob.minted_supply = minted_v
}
```

The function has two parameters, the two tokens that will be traded: `t0` and `t1`.

To call the function, the creator must send two pay transactions of the assets `t0` and `t1` from them to the escrow. 

The creator must also create a new token with 1'000'000 units (ideally we would want to create an infinite number of tokens, but since this is not possible, we have to choose a big enough value), which will be stored in the escrow account. They must also receive some amount of `minted_t` from the escrow. The amount of `minted_t` units received is irrelevant, so the creator is free to choose any amount.

## Opting in

Since the local state is needed to complete any operation, before any user can interact with the AMM, they must first opt into the contract.

```java
OptIn optin() {
    loc.t0_reserved = 0
    loc.t1_reserved = 0
    loc.minted_reserved = 0
}
```

This function gives the users the opportunity to opt in, and initializes all the local variables to zero.

## Depositing assets

Users can deposit tokens into the AMM as long as doing so preserves the ratio of the token holdings in the AMM. In return, they will receive a certain amount of minted tokens, equal to the ratio between the deposited amount and the *redeem rate* (the ratio between `r0` and the `minted_supply`)

Users must also be able to set a lower bound on how many minted tokens they can receive, so as to mitigate problems in case that the amount of minted tokens they would receive varies widely from round to round.

This function can be written as:
```java
@pay $v0 of glob.t0 : * -> escrow
@pay $v1 of glob.t1 : * -> escrow
@assert v0 / glob.r0 * glob.minted_supply >= lowb && lowb > 0
@assert glob.r1 * v0 == glob.r0 * v1    
dep(int lowb) {
    glob.minted_supply += v0 / glob.r0 * glob.minted_supply
    loc.minted_reserved += v0 / glob.r0 * glob.minted_supply
}
```

The `dep` function has a single parameter: the lower bound on how many minted_token they can receive.
To call this function, the user must send two payments to the escrow: one of the token `t0`, and one of the token `t1` (much alike the create function). When these tokens are added to the escrow account, the ratio between the tokens `t0` and `t1` must not change, and therefore, the ratio between the amount of tokens `t0` sent, and the amount of tokens `t1` sent, must be the same as the ratio between `r0` and `r1`. 
The function, also checks that the lower bound of received minted tokens tokens is respected (`v0 / glob.r0 * glob.minted_supply >= lowb`). If this check fails, the function is not called.

When the function is called succesfully, the `minted_supply` gets increased by the amount of `minted_tokens` that the AMM will reserve for the user (even though the AMM still hasn't sent those tokens), and the `minted_reserved` gets increased by the same amount.

It is up to the caller to actually redeem the reserved tokens with a later call to `get_minted_t`.

## Swapping assets

If a user is in possess of some amount of `t0` but wants to trade them with some amount of `t1`, they can do so by using the swap operation. The same holds in the opposite direction, and its implementation is dual. 

Here, we will cover `swap0`: the operation that swaps units of `t0` on the caller account, for units of `t1` in the AMM.

```java
@pay $v0 of glob.t0 : * -> escrow
@assert (glob.r1 * v0) / (glob.r0 + v0) >= lowb && lowb > 0
swap0 (int lowb) {
	loc.t1_reserved += (glob.r1 * v0) / (glob.r0 + v0)
	glob.r1 -= (glob.r1 * v0) / (glob.r0 + v0)
	glob.r0 += v0
}
```

The function has a single parameter: the lower bound on how many units of `t1` they can receive. To call this function the caller must send a payment to the escrow of the token `t0`. The contract checks if the amount of tokens that they would reserve (equal to `(glob.r1 * v0) / (glob.r0 + v0)`) is higher than the lower bound `lowb`. If this check fails, the function won't be called.

When called succesfully, `r0` is increased by `v0` (since the user sent `v0` tokens to the AMM), `t1_reserved` is increased by the reserved amount (giving the user the ability to redeem the reserved units of `t1`), and `r1` is decreased by the same amount (since the AMM no longer owns those units).

## Redeeming assets

Users can exchange the minted token with units of `t0` and `t1`. 

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

```

To call the redeem function, the user must send some amount of `minted_t` tokens to the escrow account. The user must also pass two parameters: the lower bound of the token `t0`, and the lower bound of the token `t1`. When called, those two lower bounds must be respected: the amount of units of `t0` reserved must be at least `v0_lowb`, and the amount of units of `t1` must be at least `v1_owb`. 

When all these preconditions are met, the function body updates `r0` and `r1` (removing the reserved tokens from the AMM balance), `t0_reserved` and `t1_reserved` (adding the reserved tokens), and `minted_supply` (removing those minted tokens that do not circulate anymore).

## Redeeming the reserved tokens

After calling `dep`, `swap` and `redeem`, the caller will have some amount of `t0`, `t1`, or `minted_t` reserved (or some combination of those). To redeem these tokens, users can call the functions:

```java
@pay loc.minted_reserved of glob.minted_t : escrow -> *   
get_minted_t() {
    loc.minted_reserved = 0
}

@pay loc.t0_reserved of glob.t0 : escrow -> *
get_t0() {
    loc.t0_reserved = 0
}

@pay loc.t1_reserved of glob.t1 : escrow -> *
get_t1() {
    loc.t1_reserved = 0
}
```

Each of those functions checks if the caller is receiving a payment from the escrow of the reserved amount of that particular token.
When called, the reserved amount of the chosen token is set to 0.

# Disclaimer

The project is not audited and should not be used in a production environment.
