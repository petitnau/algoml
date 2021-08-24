# Crowdfunding

This contract is an AlgoML version of the [crowdfunding contract](https://developer.algorand.org/solutions/example-crowdfunding-stateful-smart-contract-application/) by Jason Weathersby, with slight modifications.

## Contract state

The contract state is stored in the following variables:

Global variables:

* `startDate` is the first round in which users can donate
* `endDate` is the last round in which users can donate, after which donators can reclaim their donations, or the receiver can claim all the donations
* `fundCloseDate` is the first round in which the creator can delete the contract (as long as the receiver has claimed the donations, if the goal was met)
* `goal` is the amount of ALGOs that must be donated for the crowdfunding to be succesful. If it is reached, the receiver can claim the funds, otherwise the donators can reclaim their donations. 
* `receiver` is the receiver of the crowdfunding. If the goal is reached, they will get all the donations
* `total_funds` is the amount of funds currently in the escrow (those that have been donated but have not been claimed/reclaimed)

Local variables:

* `donated_amount` is the amount that has been donated by the user

The variables `total_funds` and `donated_amount` change during the life of the contract, while the others are parameters of the contract and do not change.

## Escrow account 

The escrow account used by the crowdfunding contract is a stateless contract that releases funds provided that:
1. the stateful contract participates in the transaction group
2. the escrow does not pay any transaction fees
3. the escrow does not send a rekey transaction

## Creating the fundraiser

Any user can create the crowdfunding contract, providing the receiver, the goal of the crowdfunding, the donate round window in which users can donate funds, and the round after which the contract can be deleted.

```java
Create crowdfund(int startDate, int endDate, int fundCloseDate, int goal, address receiver) {
	glob.startDate = startDate
	glob.endDate = endDate
	glob.fundCloseDate = fundCloseDate
	glob.goal = goal
	glob.receiver = receiver 
	glob.total_funds = 0
}
```

The function has five parameters:

* `startDate`: the first round in which users can donate
* `endDate`: the last round in which users can donate, after which users can claim / reclaim the funds
* `fundCloseDate`: the first round in which the creator can close the contract and collect all the non-reclaimed funds if the goal was not reached
* `goal`: the goal that must be reached for the `receiver` to collect the donated funds
* `receiver`: the receiver of the donated funds (if the goal is reached)

The function initializes `total_funds` to 0 and the rest of the global state with its parameters.

The `Create` modifier implies that this function constructs the contract, and thus, can be called only from the creator of the contract.

## Opting in

Before users can donate, they must first opt into the contract. When users opt into a contract the local variables are allocated in the user account, so that the contract can maintain how much every single user donates.

```java
OptIn optin() {
	loc.donated_amount = 0
}
```
The optin function takes no parameters and initializes the amount donated by the caller to 0.

The `OptIn` modifier allocates space on the caller account for the local state variables. 

## Donating funds

Users that have opted into the contract must be able to donate funds during the donate round window, while being sure that, if the goal is not reached, they will be able to get their donated funds back.

```java
@round (glob.startDate, glob.endDate)
@pay $donated of ALGO : * -> escrow
donate() {
	glob.total_funds += donated
	loc.donated_amount += donated
}
```
The donate function can be called by anyone that has opted into the contract, as long as the other preconditions are satisfied.

In particular, the clause
```java
@round (glob.startDate, glob.endDate)
```
asserts that the contract is called while in a round between `startDate` and `endDate`;

```java
@pay $donated of ALGO : * -> escrow
```
checks that the user is sending a pay transaction to the escrow, and binds the amount of ALGOs sent to the variable `donated`.

The body of the function increases the amount donated by the caller and the `total_funds`, by `donated` ALGOs.

## Reclaiming donated funds

If the crowdfunding ends without hitting the goal, any user can reclaim the amount of funds that they have donated (or a part of it).

```java
@assert glob.total_funds < glob.goal
@round (glob.endDate, )
@pay (, loc.donated_amount)$reclaimed of ALGO : escrow -> caller
reclaim() {
	loc.donated_amount -= reclaimed
	glob.total_funds -= reclaimed
}
```

The reclaim function can be called by anyone that has opted into the contract, as long as the donate round window is closed and the donation goal has not been reached (and thus, as long as the funds do not belong to the `receiver`). 

The body of the function decreases the amount donated by the user and the `total_funds` by the reclaimed amount (so that the user cannot reclaim more funds than donated).

## Claiming the funds

If the crowdfunding is succesful, the receiver can claim all the funds that were donated.

```java
@gstate -> claimed
@assert glob.total_funds >= glob.goal
@round (glob.endDate, )
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
@round (glob.fundCloseDate, )
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

# Disclaimer

The project is not audited and should not be used in a production environment.