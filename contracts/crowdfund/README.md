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

## Escrow account 

The crowdfunding contract relies on an escrow account (a stateless contract) to release funds whenever:
1. the stateful contract participates in the transaction group
2. the escrow does not pay any transaction fees
3. the escrow does not send a rekey transaction

## Creating the contract

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

## Opting in

Before users can donate, they must opt into the contract. When users opt into a contract, the local variables are allocated in the user account, so that the contract can record the amount of individual donations.

```java
OptIn optin() {
	loc.donated_amount = 0
}
```
The `optin` function takes no parameters, and initializes the amount donated by the caller to 0.

The `OptIn` modifier means that space for the local state variables is allocated on the caller account. 

## Donating funds

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

## Reclaiming donated funds

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

## Claiming the funds

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

## Deleting the contract

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


## Disclaimer

The project is not audited and should not be used in a production environment.
