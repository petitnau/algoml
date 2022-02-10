
# How an AlgoML contract is compiled

An AlgoML contract is composed of a series of atomic clauses. Each of these clauses can be thought of as a public method that can be called by submitting a transaction of the correct form.

When compiled into TEAL, the contract is split into blocks, one for each atomic clause.
Each block consists of a dispatching preamble, followed by the code that implements the state update. The preamble is composed of the preconditions that the clauses impose on the contract (for example the presence of a pay transaction, or an assert condition), and the state update is composed of the state update portion of the clause (for example, the new state in a @gstate clause, or the body of the function clause).

In the rest of this document we will consider the tinybond contract, seeing how the various clauses are compiled. For simplicity, we will look at the compiled code as if it was written in a mix of TEAL and PyTEAL.

# Creation of the contract

```algoml
@newtok $budget of $COUPON -> escrow
@assert preSale < sale 
@assert sale < saleEnd 
@assert saleEnd < maturityDate
Create tinybond(
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

The creation of the contract is split into three phases. A first one, in which the application is actually created, with an ApplicationCreate transaction:

```java
aclause_0:
// If the applicationID is not zero (hence the application is not being created), skip this clause
bz(aclause_1, Txn.application_id() == 0)
// If it is being created, save the string @created into the global state "gstate"
GlobalState["gstate"] = "@created"
// and approve the transaction
return 1
```

The state @created, indicates that the contract has been created, but has not yet been initialized.

After the contract has been deployed, the creator of the contract will need to connect the escrow account to the stateful application. This is done by calling the generated function "init_escrow" from the creator of the contract, while also sending 0.1 ALGOs to the escrow account.
```
CREATOR -init_escrow()-> APPLICATION
      * -- 0.1 ALGOs --> ESCROW
```

```java

aclause_1:

// Skip the clause if any of the following conditions does not hold

// The transaction group is composed of two transactions
bz(aclause_2, Global.group_size() == 2)
// The first transaction is a pay transaction
bz(aclause_2, Gtxn[0].type_enum() == TransactionType.pay)
// With an amount of 100'000 microALGOs being sent
bz(aclause_2, Gtxn[0].amount() == 100000)
bz(aclause_2, Gtxn[0].close_remainder_to() == Global.zero_address())
// The call to the contract is a noop call
bz(aclause_2, Txn.on_completion() == OnCompletion.noop)
// With a single argument (init_escrow)
bz(aclause_2, Txn.num_app_args() == 1)
bz(aclause_2, Txn.application_args[0] == "init_escrow")
// From the creator of the contract
bz(aclause_2, Txn.sender() == Global.creator_address())
// From the initial global state @created (created but not initialized)
bz(aclause_2, GlobalState["gstate"] == "@created")

// If all the preconditions hold, run the following state updates:

// Update the global state to "@escrowinited"
GlobalState["gstate"] = "@escrowinited"
// Update the global variable escrow to the receiver of the pay transaction
GlobalState["escrow"] = Gtxn[0].receiver()
return 1
```

When succesfully called, the contract will save the receiver of the 0.1 ALGOs as the escrow account, and will go into state "@escrowinited" (contract created, escrow connected).

Lastly

```java
aclause_2:

// Skip the clause if any of the following conditions does not hold

bz(aclause_3, Global.group_size() == 3)
/* implicit @pay 100'000 of ALGO : $funder -> escrow
            @assert funder != escrow */
bz(aclause_3, Gtxn[0].type_enum() == TransactionType.pay)
bz(aclause_3, Gtxn[0].amount() == 100000)
bz(aclause_3, Gtxn[0].sender() != GlobalState["escrow"])
bz(aclause_3, Gtxn[0].receiver() == GlobalState["escrow"])
/* @newtok $budget of COUPON -> escrow */
bz(aclause_3, Gtxn[1].type_enum() == TransactionType.acfg)
bz(aclause_3, Gtxn[1].config_asset_decimals() == 0)
bz(aclause_3, Gtxn[1].config_asset_manager() == "")
bz(aclause_3, Gtxn[1].config_asset_reserve() == "")
bz(aclause_3, Gtxn[1].config_asset_freeze() == "")
bz(aclause_3, Gtxn[1].config_asset_clawback() == "")
bz(aclause_3, Gtxn[1].sender() == GlobalState["escrow"])
/* implicit @from creator */
bz(aclause_3, Txn.sender() == Global.creator_address())
// The transaction call is a noop transaction
bz(aclause_3, Txn.on_completion() == OnCompletion.noop)
// With 7 arguments
bz(aclause_3, Txn.num_app_args() == 7)
// Of which the first equal to tinybond
bz(aclause_3, Txn.application_args[0] == "tinybond")
// With global state "@escrowinited" (escrow initialized)
bz(aclause_3, GlobalState["gstate"] == "@escrowinited")
// @assert preSale < sale
bz(aclause_3, Btoi(Txn.application_args[1]) < Btoi(Txn.application_args[2]))
// @assert sale < saleEnd
bz(aclause_3, Btoi(Txn.application_args[2]) < Btoi(Txn.application_args[3]))
// @assert saleEnd < maturityDate
bz(aclause_3, Btoi(Txn.application_args[3]) < Btoi(Txn.application_args[4]))

// If all the preconditions hold, run the following state updates:

GlobalState["gstate"] = "@inited"
GlobalState["preSale"] = Btoi(Txn.application_args[1])
GlobalState["sale"] = Btoi(Txn.application_args[2])
GlobalState["saleEnd"] = Btoi(Txn.application_args[3])
GlobalState["maturityDate"] = Btoi(Txn.application_args[4])
GlobalState["interestRate"] = Btoi(Txn.application_args[5])
GlobalState["preSaleRate"] = Btoi(Txn.application_args[6])
GlobalState["COUPON"] = Gaid[1]
GlobalState["maxDep"] = Gtxn[1],config_asset_total()

return 1
```
 
run the tinybond clause, which corresponds to the following block.


# Opting into the pre-sale

```java
aclause_3:

bz(aclause_4, Global.group_size() == 1)
bz(aclause_4, Global.group_size() == 1)
bz(aclause_4, Txn.on_completion() == OnCompletion.optin)
bz(aclause_4, Txn.num_app_args() == 1)
bz(aclause_4, Txn.application_args[0] == "joinPresale")
bz(aclause_4, Substr(GlobalState["gstate"], 0, 1) != "@")
bz(aclause_4, )
bz(aclause_4, )

LocalState["preSaleAmt"] = 0
return 1
```

# Deposit

## On presale

```java
aclause_4:

bz(aclause_5, Global.group_size() == 2)
bz(aclause_5, Gtxn[0].type_enum == TransactionType.pay)
bz(aclause_5, Txn.on_completion() == OnCompletion.noop)
bz(aclause_5, Txn.num_app_args() == 1)
bz(aclause_5, Txn.application_args[0] == "deposit")
bz(aclause_5, Substr(GlobalState["gstate"], 0, 1) != "@")
bz(aclause_5, Exists(GlobalState["preSale"]))
bz(aclause_5, Exists(GlobalState["sale"]))
bz(aclause_5, Global.round() >= GlobalState["preSale"])
bz(aclause_5, Global.round() < GlobalState["sale"])
bz(aclause_5, Gtxn[0].sender() == Txn.sender())
bz(aclause_5, Gtxn[0].receiver() == GlobalState["escrow"])
bz(aclause_5, Gtxn[0].close_remainder_to() == Global.zero_address())
bz(aclause_5, Exists(GlobalState["preSaleRate"]))
bz(aclause_5, Exists(GlobalState["maxDep"]))
bz(aclause_5, Gtxn[0].amount() * GlobalState["preSaleRate"] / 100 <= GlobalState["maxDep"])

LocalState["preSaleAmt"] =  LocalState["preSaleAmt"] + Gtxn[0].amount() * GlobalState["preSaleRate"] / 100
LocalState["maxDep"] = LocalState["maxDep"] - Gtxn[0].amount() *  GlobalState["preSaleRate"] / 100

return 1
```
