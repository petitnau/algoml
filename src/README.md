
# How an AlgoML contract is compiled

An AlgoML contract is composed of a series of atomic clauses. Each of these clauses can be thought of as a public method that can be called by submitting a transaction of the correct form.

When compiled into TEAL, the contract is split into blocks, one for each atomic clause.
Each block consists of a dispatching preamble, followed by the code that implements the state update. The preamble is composed of the preconditions that the clauses impose on the contract (for example the presence of a pay transaction, or an assert condition), and the state update is composed of the state update portion of the clause (for example, the new state in a @gstate clause, or the body of the function clause).

In the rest of this document we will consider the tinybond contract, seeing how the various clauses are compiled. For simplicity, we will look at the compiled code as if it was written in a pseudo-code version of TEAL.

# Creation of the contract

The creation of the contract is split into three phases. 

## Deploying the contract

In the first phase, the application must be deployed on the blockchain with an ApplicationCreate transaction. The block that manages this operation is the following: 

```java
aclause_0:

// If the applicationID is not zero (hence the application is not being created), skip this clause
bz(aclause_1, txn.ApplicationID == 0)
// If it is being created, save the string @created into the global state "gstate"
global_state["gstate"] = "@created"
// and approve the transaction
return 1
```

The state @created, indicates that the contract has been created, but has not yet been initialized.

## Connecting the escrow

After the contract has been deployed, the creator of the contract will need to connect the escrow account to the stateful application. This is done by calling the generated function "init_escrow" from the creator of the contract, while also sending 0.1 ALGOs to the escrow account, with a transaction group that follows the form:
```
CREATOR -init_escrow()-> APPLICATION
      * -- 0.1 ALGOs --> ESCROW
```

The block delegated to approving this transaction is
```java
aclause_1:

/************
 * PREAMBLE : Skip the clause if any of the following conditions does not hold
 ************/

bz(aclause_2, global.GroupSize == 2)
// [IMPLICIT] NoOp init_escrow() 
bz(aclause_2, txn.OnCompletion == noop)
bz(aclause_2, txn.NumAppArgs == 1)
bz(aclause_2, txn.application_args[0] == "init_escrow")
// [IMPLICIT] @from creator
bz(aclause_2, txn.Sender == global.CreatorAddress)
// [IMPLICIT] @gstate @created -> @escrowinited
bz(aclause_2, global_state["gstate"] == "@created")
// [IMPLICIT] @pay 100'000 of ALGO : * -> $escrow
bz(aclause_2, txn[0].TypeEnum == pay)
bz(aclause_2, txn[0].Amount == 100000)
bz(aclause_2, txn[0].CloseRemainderTo == global.ZeroAddress)

/****************
 * STATE UPDATE : If all the preconditions hold, run the following state updates:
 ****************/

// [IMPLICIT] @gstate @created -> @escrowinited
global_state["gstate"] = "@escrowinited"
global_state["escrow"] = txn[0].Receiver // set the receiver of the pay transaction as the escrow
return 1
```

When succesfully called, the contract will save the receiver of the 0.1 ALGOs as the escrow account, and will go into state "@escrowinited" (contract created, escrow connected, but contract not fully initialized).

## Initializing the contract

After running the previous two blocks, a third transaction group must be submitted to fully initialize the escrow. This block corresponds to the `Create tinybond` atomic clause. In addition to the indicated clauses, some other checks area added:
* `@from creator`: All Create clauses can only be run by the creator
* `@pay 100'000 of ALGO : $funder -> escrow`: Since escrow is creating a new token, it must be funded of 0.1 ALGOs to maintain a valid minimum balance
* `@assert funder != escrow`: The account that is funding the escrow must not be the escrow itself

```java
aclause_2:

/************
 * PREAMBLE : Skip the clause if any of the following conditions does not hold
 ************/

bz(aclause_3, global.GroupSize == 3)
// Create tinybond(int preSale, int sale, int saleEnd, int maturityDate, int interestRate, int preSaleRate)
bz(aclause_3, txn.OnCompletion == noop)
bz(aclause_3, txn.NumAppArgs == 7)
bz(aclause_3, txn.application_args[0] == "tinybond")
// [IMPLICIT] @gstate @escrowinited -> #inited
bz(aclause_3, global_state["gstate"] == "@escrowinited")
// [IMPLICIT] @from creator
bz(aclause_3, txn.Sender == global.CreatorAddress)
// [IMPLICIT] @pay 100'000 of ALGO : $funder -> escrow
// [IMPLICIT] @assert funder != escrow
bz(aclause_3, txn[0].TypeEnum == pay)
bz(aclause_3, txn[0].Amount == 100000)
bz(aclause_3, txn[0].Sender != global_state["escrow"])
bz(aclause_3, txn[0].Receiver == global_state["escrow"])
// @newtok $budget of COUPON -> escrow
bz(aclause_3, txn[1].TypeEnum == acfg)
bz(aclause_3, txn[1].configAssetDecimals == 0)
bz(aclause_3, txn[1].configAssetManager == "")
bz(aclause_3, txn[1].configAssetReserve == "")
bz(aclause_3, txn[1].configAssetFreeze == "")
bz(aclause_3, txn[1].configAssetClawback == "")
bz(aclause_3, txn[1].Sender == global_state["escrow"])
// @assert preSale < sale
bz(aclause_3, btoi(txn.application_args[1]) < btoi(txn.application_args[2]))
// @assert sale < saleEnd
bz(aclause_3, btoi(txn.application_args[2]) < btoi(txn.application_args[3]))
// @assert saleEnd < maturityDate
bz(aclause_3, btoi(txn.application_args[3]) < btoi(txn.application_args[4]))

/****************
 * STATE UPDATE : If all the preconditions hold, run the following state updates:
 ****************/

// [IMPLICIT] @gstate @escrowinited -> #inited
global_state["gstate"] = "#inited"

global_state["preSale"] = btoi(txn.application_args[1])
global_state["sale"] = btoi(txn.application_args[2])
global_state["saleEnd"] = btoi(txn.application_args[3])
global_state["maturityDate"] = btoi(txn.application_args[4])
global_state["interestRate"] = btoi(txn.application_args[5])
global_state["preSaleRate"] = btoi(txn.application_args[6])
global_state["COUPON"] = Gaid[1]
global_state["maxDep"] = txn[1],config_asset_total()

return 1
```

# Opting into the pre-sale

After being created, users that want to buy bonds will need to opt into the contract. This action is managed by the following block:

```java
aclause_3:

/************
 * PREAMBLE : Skip the clause if any of the following conditions does not hold
 ************/

bz(aclause_4, global.GroupSize == 1)
// OptIn joinSale()
bz(aclause_4, txn.OnCompletion == optin)
bz(aclause_4, txn.NumAppArgs == 1)
bz(aclause_4, txn.application_args[0] == "joinSale")
// Must only be called from an initialized state (after the Create clause has been run)
bz(aclause_4, substring(global_state["gstate"], 0, 1) != "@")

/****************
 * STATE UPDATE : If all the preconditions hold, run the following state updates:
 ****************/

local_state["preSaleAmt"] = 0

return 1
```

# Deposit

## On presale

After opting into the contract, users that want to join the presale will be able to do so by calling the deposit function during the preSale period.

```java
aclause_4:

/************
 * PREAMBLE : Skip the clause if any of the following conditions does not hold
 ************/

bz(aclause_5, global.GroupSize == 2)
// deposit()
bz(aclause_5, txn.OnCompletion == noop)
bz(aclause_5, txn.NumAppArgs == 1)
bz(aclause_5, txn.application_args[0] == "deposit")
// Must only be called from an initialized state (after the Create clause has been run)
bz(aclause_5, substring(global_state["gstate"], 0, 1) != "@")
// @round (glob.preSale, glob.sale)
bz(aclause_5, global.Round >= global_state["preSale"])
bz(aclause_5, global.Round < global_state["sale"])
// pay $amt of ALGO : caller -> escrow
bz(aclause_5, txn[0].TypeEnum == pay)
bz(aclause_5, txn[0].Sender == txn.Sender)
bz(aclause_5, txn[0].Receiver == global_state["escrow"])
bz(aclause_5, txn[0].CloseRemainderTo == global.ZeroAddress)
// @assert amt * glob.preSaleRate / 100 <= glob.maxDep
bz(aclause_5, txn[0].Amount * global_state["preSaleRate"] / 100 <= global_state["maxDep"])

/****************
 * STATE UPDATE : If all the preconditions hold, run the following state updates:
 ****************/

local_state["preSaleAmt"] = local_state["preSaleAmt"] + txn[0].Amount * global_state["preSaleRate"] / 100
local_state["maxDep"] = local_state["maxDep"] - txn[0].Amount *  global_state["preSaleRate"] / 100

return 1
```

## On regular sale

During the sale period, users that have opted into the contract will be able to call the deposit function, which is managed by the following block: 

```java
aclause_5:

/************
 * PREAMBLE : Skip the clause if any of the following conditions does not hold
 ************/

bz(aclause_6, global.GroupSize == 3)
// deposit()
bz(aclause_6, txn.OnCompletion == noop)
bz(aclause_6, txn.NumAppArgs == 1)
bz(aclause_6, txn.application_args[0] == 'deposit')
// Must only be called from an initialized state (after the Create clause has been run)
bz(aclause_5, substring(global_state["gstate"], 0, 1) != "@")
// @round (glob.sale, glob.saleEnd)
bz(aclause_6, global.Round >= global_state["sale"])
bz(aclause_6, global.Round < global_state["saleEnd"])
// @pay $inAmt of ALGO : caller -> escrow
bz(aclause_6, txn[0].TypeEnum == pay)
bz(aclause_6, txn[0].Sender == txn.Sender)
bz(aclause_6, txn[0].Receiver == global_state["escrow"])
bz(aclause_6, txn[0].CloseRemainderTo == global.ZeroAddress)
// @pay $outAmt of COUPON : escrow  -> caller
bz(aclause_6, txn[1].TypeEnum == axfer) 
bz(aclause_6, txn[1].XferAsset == global_state["COUPON"])
bz(aclause_6, txn[1].Sender == global_state["escrow"])
bz(aclause_6, txn[1].AssetReceiver == txn.Sender)
bz(aclause_6, txn[1].AssetCloseTo == global.ZeroAddress)
// @assert inAmt + loc.preSaleAmt == outAmt
bz(aclause_6, txn[0].Amount + local_state["preSaleAmt"] == txn[1].Amount)

/****************
 * STATE UPDATE : If all the preconditions hold, run the following state updates:
 ****************/

local_state["preSaleAmt"] = 0

return 1
```

## Redeem

After the maturity date has passed, users will be able to call the redeem function, managed by the following block:

```java
aclause_6

/************
 * PREAMBLE : Skip the clause if any of the following conditions does not hold
 ************/

bz(aclause_7, global.GroupSize == 3)
// redeem()
bz(aclause_7, txn.OnCompletion == NoOp)
bz(aclause_7, txn.NumAppArgs == 1)
bz(aclause_7, txn.ApplicationArgs[0] == "redeem")
// Must only be called from an initialized state (after the Create clause has been run)
bz(aclause_7, substring(global_state["gstate"], 0, 1) != "@")
// @round (glob.maturityDate, )
bz(aclause_7, global.Round >= global_state["maturityDate"])
// @pay $inAmt of glob.COUPON : caller -> escrow
bz(aclause_7, txn[0].TypeEnum == axfer)
bz(aclause_7, txn[0].XferAsset == global_state["COUPON"])
bz(aclause_7, txn[0].Sender == txn.Sender)
bz(aclause_7, txn[0].AssetReceiver == global_state["escrow"])
bz(aclause_7, txn[0].AssetCloseTo == global.ZeroAddress)
// @pay $outAmt of ALGO : escrow -> caller
bz(aclause_7, txn[1].TypeEnum == pay)
bz(aclause_7, txn[1].Sender == global_state["escrow"])
bz(aclause_7, txn[1].Receiver == txn.Sender)
bz(aclause_7, txn[1].CloseRemainderTo == global.ZeroAddress)
// @assert inAmt == outAmt * glob.interestRate / 100
bz(aclause_7, txn[0].Amount == txn[1].Amount * global_state["interestRate"] / 100)

/****************
 * STATE UPDATE : If all the preconditions hold, run the following state updates:
 ****************/

return 1
```

## No clause to run

If none of the previous preambles meet all of their conditions, the call to the contract will fail.

```
aclause_7

err()
```
