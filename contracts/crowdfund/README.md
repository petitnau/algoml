# Crowdfunding

This contract is an AlgoML version of the [crowdfunding contract](https://developer.algorand.org/solutions/example-crowdfunding-stateful-smart-contract-application/) by Jason Weathersby, with slight modifications.

Crowdfunding applications are a great way to gain some money for a project.
A typical crowdfunding application is based on three actors: 

- the *project creator*, which defines the project, the amount of funds needed and a time window
- the *donators*, who donate money to the project
- a *middle man*, which holds the donated funds until the time window defined by the project creator ends.
  
Often, crowdfunding applications work with a model called all-or-nothing, which means that if the goal is not reached in time, the project creator does not receive the donated funds, and instead the donators can claim their money back.

With the aid of smart contracts, the need of a trusted middleman is eliminated, as the contract itself can keep the funds secure until the end of the donation phase.

Popular examples of crowdfunding applications are [Kickstarter](https://www.kickstarter.com/), [Indiegogo](https://www.indiegogo.com/), and [GoFundMe](https://www.gofundme.com/).

## Contract state

The contract state is stored in the following variables:

Global variables:

* `start_date` is the first round in which users can donate
* `end_date` is the last round in which users can donate, after which donors can reclaim their donations, or the receiver can claim all the donations
* `fund_close_date` is the first round in which the creator can delete the contract
* `goal` is the amount of ALGOs that must be donated for the crowdfunding to be succesful. If the goal is reached, the receiver can claim the funds, otherwise the donors can reclaim their donations
* `receiver` is the receiver of the donated funds. If the goal is reached, then `receiver` get all the donations
* `total_funds` is the amount of funds currently in the escrow (those that have been donated but have not been claimed/reclaimed).

Local variables:

* `donated_amount` is the amount that has been donated by the user

The variables `total_funds` and `donated_amount` change during the contract lifetime, while the others are parameters of the contract and are immutable.

## AlgoML implementation

### Escrow account 

The crowdfunding contract relies on an escrow account (a stateless contract) to release funds whenever:
1. the stateful contract participates in the transaction group
2. the escrow does not pay any transaction fees
3. the escrow does not send a rekey transaction

### Creating the contract

Any user can create the crowdfunding contract, providing as parameters the `receiver`, the `goal`, the round window in which users can donate funds (`start_date`  and `end_date`), and the round after which the contract can be deleted (`fund_close_date`).

```java
Create crowdfund(int start_date, int end_date, int fund_close_date, int goal, address receiver) {
	glob.start_date = start_date
	glob.end_date = end_date
	glob.fund_close_date = fund_close_date
	glob.goal = goal
	glob.receiver = receiver 
	glob.total_funds = 0
}
```

The constructor initializes `total_funds` to 0, and the rest of the global variables to the corresponding actual parameters.

The `Create` modifier means that the function constructs the contract, and thus can be called only from the contract creator.

### Opting in

Before users can donate, they must opt into the contract. When users opt into a contract, the local variables are allocated in the user account, so that the contract can record the amount of individual donations.

```java
OptIn optin() {
	loc.donated_amount = 0
}
```
The `optin` function takes no parameters, and initializes the amount donated by the caller to 0.

The `OptIn` modifier means that space for the local state variables is allocated on the caller account. 

### Donating funds

Users that have opted into the contract must be able to donate funds during the donate round window, while being sure that, if the goal is not reached, they will be able to get their funds back.

```java
@round (glob.start_date, glob.end_date)
@pay $donated of ALGO : * -> escrow
donate() {
	glob.total_funds += donated
	loc.donated_amount += donated
}
```

The `donate` function can be called by anyone who has opted into the contract, as long as the other clauses are satisfied.

In particular, the clause
```java
@round (glob.start_date, glob.end_date)
```
ensures that the function can be called only in a round between `start_date` and `end_date`;

```java
@pay $donated of ALGO : * -> escrow
```
checks that the user is sending a pay transaction to the escrow, and records the paid amount of ALGOs in the variable `donated`.

The body of the function increases the amount donated by the caller and the `total_funds`, by `donated` ALGOs.

### Reclaiming donated funds

If the crowdfunding ends without hitting the goal, any user can reclaim the amount of funds that they have donated (or a part of it).

```java
@assert glob.total_funds < glob.goal
@round (glob.end_date, )
@pay (, loc.donated_amount)$reclaimed of ALGO : escrow -> caller
reclaim() {
	loc.donated_amount -= reclaimed
	glob.total_funds -= reclaimed
}
```

The `reclaim` function can be called by anyone who has opted into the contract, as long as the donation period is closed, and the donation goal has not been reached (and thus, as long as the funds do not belong to the `receiver`). 

The function body decreases the amount donated by the user and the `total_funds` by the reclaimed amount. As a consequence, the user cannot reclaim more funds than donated.

### Claiming the funds

If the crowdfunding is successful, the receiver can claim all the funds that were donated.

```java
@gstate -> claimed
@assert glob.total_funds >= glob.goal
@round (glob.end_date, )
@pay glob.total_funds of ALGO : escrow -> glob.receiver
claim() {
	glob.total_funds = 0
}
```

The claim function can be called by anyone after the donate round window has ended, by submitting a pay transaction with all the donated funds from the `escrow` to the `receiver`.

Since all the funds have been claimed, the body of the function sets the total funds to 0.

### Deleting the contract

After the fund close date, the creator can delete the contract and close the escrow account, as long as the funds have been claimed by the receiver (if the goal is met).

```java
@assert glob.total_funds < glob.goal
@round (glob.fund_close_date, )
@close ALGO : escrow -> creator
@from creator
Delete delete() {}
```

The `Delete` modifier, deletes the contract after the function is called. 

For the function to be called, `total_funds` must be less than `goal`, and therefore, either the receiver has claimed the funds, or the goal was never met.

The clause
```java
@close ALGO : escrow -> creator
```
checks that the caller is closing the escrow account, sending all its ALGOs to the creator.

## Compiled contract

Let us now look at how the contract, and more specifically the various atomic clauses, are compiled.

The TEAL code of the contract is split into blocks, one per each AlgoML atomic clause. 
Each block consists of a dispatching preamble, followed by the code that implements the state update. Each atomic clause corresponds to a block. The preamble is composed of the preconditions that the clauses impose on the contract (for example the presence of a pay transaction, or an assert condition), and the state update is composed of the state update portion of the clause (for example, the new state in a @gstate clause, or the body of the function clause).

Before looking at how the clauses we wrote are compiled, let us look at some code generated by the compiler:
```java
aclause_0:

txn ApplicationID
int 0
==
bz aclause_1

//*******

byte "gstate"
byte "@created"
app_global_put

int 1
return
```
This block, checks if the contract is currently being created, and if so, saves the string "@created" in the `gstate` global variable, and accepts the transaction. The "@created" state, means that the contract has been created (it is callable), but it has yet to be initialized (with a Create function). 

The compiler also generates a special AlgoML clause to initialize the escrow account:
```java
@gstate @created->@escrowinited
@pay 100000 of ALGO : * -> $escrw
@from creator
NoOp init_escrow() {
	glob.escrow = escrw
}
```
which checks if the creator of the contract is sending a pay transaction to an account, which will be saved as the escrow. It compiles into the following block:
```java
aclause_1:

// check if the contract was called in a group transaction with 2 elements
global GroupSize
int 2
==
bz aclause_2

// check if the first of the two transactions is a pay transaction
gtxn 0 TypeEnum
int pay
==
bz aclause_2

// check if the applicationcall does not update/delete/optin/ecc.
txn OnCompletion
int NoOp
==
bz aclause_2

// check if the application was called with a single argument: "init_escrow"
txn NumAppArgs
int 1
==
bz aclause_2

txna ApplicationArgs 0
byte "init_escrow"
==
bz aclause_2

// check if the application was called by the creator of the contract
txn Sender
global CreatorAddress
==
bz aclause_2

// check if the application has only been created, but not yet initialized
byte "gstate"
app_global_get
byte "@created"
==
bz aclause_2

// check if the first transaction is sending 100'000 ALGOs 
gtxn 0 Amount
int 100000
==
bz aclause_2

// chek if the first transaction is not closing the account
gtxn 0 CloseRemainderTo
global ZeroAddress
==
bz aclause_2

//*******

// set the contract state to @escrowinited, a special state which tells the contract that the escrow was initializated, and therefore, it is ready to initialize its global variables
byte "gstate"
byte "@escrowinited"
app_global_put

// save the escrow into the global state variable "escrow"
byte "escrow"
gtxn 0 Receiver
app_global_put

int 1
return
```

Next, we'll look at how the atomic clauses we previously defined are compiled.
### Creating the fundraiser

```java
aclause_2:

// check if there is only one transaction (the application call)
global GroupSize
int 1
==
bz aclause_3

// check if the applicationcall does not update/delete/optin/ecc.
txn OnCompletion
int NoOp
==
bz aclause_3

// check if the application was called with 6 arguments, of which the first is "crowdfund"
txn NumAppArgs
int 6
==
bz aclause_3

txna ApplicationArgs 0
byte "crowdfund"
==
bz aclause_3

// check if the current state is @escrowinited, which means that the contract's escrow was initializated, but no Create function was executed yet.
byte "gstate"
app_global_get
byte "@escrowinited"
==
bz aclause_3

// check if the current call has been made by the creator
txn Sender
global CreatorAddress
==
bz aclause_3

//*******

// update the global state to #inited, which means that the contract has been fully initialized
byte "gstate"
byte "#inited"
app_global_put

// initialize the global state variables
byte "start_date"
txna ApplicationArgs 1
btoi
app_global_put

byte "end_date"
txna ApplicationArgs 2
btoi
app_global_put

byte "fund_close_date"
txna ApplicationArgs 3
btoi
app_global_put

byte "goal"
txna ApplicationArgs 4
btoi
app_global_put

byte "receiver"
txna ApplicationArgs 5
app_global_put

byte "total_funds"
int 0
app_global_put

int 1
return
```

### Opting in

```java
aclause_3:

// check if there is only one transaction (the application call)
global GroupSize
int 1
==
bz aclause_4

// check if the user is opting in with the current transaction
txn OnCompletion
int OptIn
==
bz aclause_4

// check if the application was call with 1 argument: "optin"
txn NumAppArgs
int 1
==
bz aclause_4

txna ApplicationArgs 0
byte "optin"
==
bz aclause_4

// check if the state doesn't start with @: this is only false for the clauses @created and @escrowinited. This checks that the contract has been initialized
byte "gstate"
app_global_get
substring 0 1
byte "@"
!=
bz aclause_4

//*******

// initialize the local donated amount of the caller to 0
txn Sender
byte "donated_amount"
int 0
app_local_put

int 1
return
```

### Donating funds

```java
aclause_4:

// check if the contract was called in a group transaction with 2 elements
global GroupSize
int 2
==
bz aclause_5

// check if the first of the two transactions is a pay transaction (the donation)
gtxn 0 TypeEnum
int pay
==
bz aclause_5

// check if the application call does not update/delete/optin/ecc.
txn OnCompletion
int NoOp
==
bz aclause_5

// check if the application was called with a single argument "donate"
txn NumAppArgs
int 1
==
bz aclause_5

txna ApplicationArgs 0
byte "donate"
==
bz aclause_5

// check if the state doesn't start with @: this is only false for the clauses @created and @escrowinited. This essentially checks if the contract has been initialized.
byte "gstate"
app_global_get
substring 0 1
byte "@"
!=
bz aclause_5

// check if the current round is between start_date and end_date (mid donation phase)
global Round
byte "start_date"
app_global_get
>=
global Round
byte "end_date"
app_global_get
<=
&&
bz aclause_5

// check that the account sending the pay transaction is not the escrow (but can be any other user)
gtxn 0 Sender
byte "escrow"
app_global_get
!=
bz aclause_5

// check that the receiver of the pay transaction is the escrow
gtxn 0 Receiver
byte "escrow"
app_global_get
==
bz aclause_5

// check that the pay transaction is not closing the account
gtxn 0 CloseRemainderTo
global ZeroAddress
==
bz aclause_5

//*******

// increment the total funds by the amount donated
byte "total_funds"
byte "total_funds"
app_global_get
gtxn 0 Amount
+
app_global_put

// increment the local donated amount of the caller by the amount donated
txn Sender
byte "donated_amount"
txn Sender
byte "donated_amount"
app_local_get
gtxn 0 Amount
+
app_local_put

int 1
return
```
### Reclaiming donated funds

```java
aclause_5:

// check if the contract was called in a group transaction with 2 elements
global GroupSize
int 2
==
bz aclause_6

// check if the first of the two transactions is a pay transaction (which will transfer the reclaimed funds)
gtxn 0 TypeEnum
int pay
==
bz aclause_6

// check if the application cal does not update/delete/optin/ecc.
txn OnCompletion
int NoOp
==
bz aclause_6

// check if the application was called with a single argument "reclaim"
txn NumAppArgs
int 1
==
bz aclause_6

txna ApplicationArgs 0
byte "reclaim"
==
bz aclause_6

// check if the state doesn't start with @: this is only false for the clauses @created and @escrowinited. This essentially checks if the contract has been initialized.
byte "gstate"
app_global_get
substring 0 1
byte "@"
!=
bz aclause_6

// check if the goal has not yet been reached (total_funds < goal)
byte "total_funds"
app_global_get
byte "goal"
app_global_get
<
bz aclause_6

// check if end_date has been reached (current_round >= end_date)
global Round
byte "end_date"
app_global_get
>=
bz aclause_6

// check if the amount that is getting transfered is less or equal to the donated amount (as a user cannot reclaim more than they have donated)
gtxn 0 Amount
txn Sender
byte "donated_amount"
app_local_get
<=
bz aclause_6

// check if the sender of the pay transaction is the escrow (as the donated funds are stored in the escrow)
gtxn 0 Sender
byte "escrow"
app_global_get
==
bz aclause_6

// check if the receiver of the pay transaction is the caller 
gtxn 0 Receiver
txn Sender
==
bz aclause_6

// check if the pay transaction does not close the escrow account
gtxn 0 CloseRemainderTo
global ZeroAddress
==
bz aclause_6

//*******

// remove the amount reclaimed from the global total_funds donated
byte "total_funds"
byte "total_funds"
app_global_get
gtxn 0 Amount
-
app_global_put

// remove the amount reclaimed from the local donated_amount
txn Sender
byte "donated_amount"
txn Sender
byte "donated_amount"
app_local_get
gtxn 0 Amount
-
app_local_put

int 1
return
```

### Claiming the funds

```java
aclause_6:

// check if the contract was called in a group transaction with 2 elements
global GroupSize
int 2
==
bz aclause_7

// check if the first of the two transactions is a pay transaction (which will transfer the claimed funds)
gtxn 0 TypeEnum
int pay
==
bz aclause_7

// check if the application call does not update/delete/optin/ecc.
txn OnCompletion
int NoOp
==
bz aclause_7

// check if the application was called with a single argument "claim"
txn NumAppArgs
int 1
==
bz aclause_7

txna ApplicationArgs 0
byte "claim"
==
bz aclause_7

// check if the state doesn't start with @: this is only false for the clauses @created and @escrowinited. This essentially checks if the contract has been initialized.
byte "gstate"
app_global_get
substring 0 1
byte "@"
!=
bz aclause_7

// check if the goal has been reached (total_funds >= goal)
byte "total_funds"
app_global_get
byte "goal"
app_global_get
>=
bz aclause_7

// check if the end date has been reached (current round >= end_date)
global Round
byte "end_date"
app_global_get
>=
bz aclause_7

// check if the pay transaction is transfering an amount equal to total_funds (claiming all the funds)
gtxn 0 Amount
byte "total_funds"
app_global_get
==
bz aclause_7

// check if the pay transaction is transfering funds from the escrow (which holds the donations)
gtxn 0 Sender
byte "escrow"
app_global_get
==
bz aclause_7

// check if the pay transaction is transfering funds to the receiver of the crowdfunding
gtxn 0 Receiver
byte "receiver"
app_global_get
==
bz aclause_7

// check if the pay transaction is not closing the escrow account
gtxn 0 CloseRemainderTo
global ZeroAddress
==
bz aclause_7

//*******

// set the total funds to zero (all funds were claimed)
byte "total_funds"
int 0
app_global_put

int 1
return
```

### Deleting the contract

```java
aclause_7:

// check if the contract was called in a group transaction with 2 elements
global GroupSize
int 2
==
bz aclause_8

// check if the first of the two transactions is a pay transaction
gtxn 0 TypeEnum
int pay
==
bz aclause_8

// check if the user is deleting the contract
txn OnCompletion
int DeleteApplication
==
bz aclause_8

// check if the application was called with a single argument "delete"
txn NumAppArgs
int 1
==
bz aclause_8

txna ApplicationArgs 0
byte "delete"
==
bz aclause_8

// check if the state doesn't start with @: this is only false for the clauses @created and @escrowinited. This essentially checks if the contract has been initialized.
byte "gstate"
app_global_get
substring 0 1
byte "@"
!=
bz aclause_8

// check if the the goal was not reached (total_funds < goal)
byte "total_funds"
app_global_get
byte "goal"
app_global_get
<
bz aclause_8

// check if the fund_close_date round has been reached (current round >= fund_close_date)
global Round
byte "fund_close_date"
app_global_get
>=
bz aclause_8

// check if the amount being trasferred is zero ALGOs (all the funds will be transfered on closure)
gtxn 0 Amount
int 0
==
bz aclause_8

// check if the escrow is sending the funds
gtxn 0 Sender
byte "escrow"
app_global_get
==
bz aclause_8

// check if the transaction is closing the escrow account sending all its funds to the creator
gtxn 0 CloseRemainderTo
global CreatorAddress
==
bz aclause_8

// check if the contract was called by the creator
txn Sender
global CreatorAddress
==
bz aclause_8

//*******

int 1
return
```

### Invalid call

If no valid block was found until this point, the call is not valid, and the transaction is rejected

```java
aclause_8:

err
```

### Escrow account

```java
#pragma version 3

// assert that either the first or the second transaction in the group is an application  call to the ctateful contract
call_0:
gtxn 0 TypeEnum
int appl
==
bz call_1
gtxn 0 ApplicationID
int <APP-ID>
==
bnz app_called

call_1:
gtxn 1 TypeEnum
int appl
==
bz call_2
gtxn 1 ApplicationID
int <APP-ID>
==
bnz app_called

call_2:
err

// if ok, assert that this is not a call to its corresponding stateful contract
app_called:
txn TypeEnum
int appl
==
bnz not_call
txn ApplicationID
int <APP-ID>
!=
assert

// assert that the transaction is not rekeying
not_call:
txn RekeyTo
global ZeroAddress
==
assert

// assert that the escrow is not paying any fee
txn Fee
int 0
==
assert

int 1
return
```

# Disclaimer

The project is not audited and should not be used in a production environment.
