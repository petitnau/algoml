# Escrow 

We specify an escrow contract which regulates a payment between a buyer and a seller. The contract is split in the following phases:
* in the **join** phase, the buyer and the seller join the contract. The buyer must provide a deposit in ALGOs;
* in the **choice** phase, the users try to find an agreement about the recipient of the deposit;
* in the **redeem** phase, if the users have found an agreement, then the chosen recipient can redeem the deposit;
* after the redeem phase has passed, an escrow oracle is used to resolve the dispute. Upon the payment of a fee, the oracle chooses the recipient, who can then redeem the remaining part of the deposit.

## Contract state

The contract state consists of the following global variables:
* `end_join`: last round of the join phase
* `end_choice`: last round of the choice phase
* `end_redeem`: last round of the redeem phase
* `feeRate`: percentage of the deposit taken for arbitrage
* `a`: buyer's address
* `b`: seller's address
* `e`: escrow's address
* `deposit`: buyer's deposit
* `first`: address of the first user who makes a choice
* `eChoice`: choice of the escrow

Further, the users who join the contract have the following local variable:
* `choice`: the recipient of the deposit chosen by the user

## Creating the escrow

Any user can create the contract by providing the escrow address, the deadlines, and the fee rate. The initial state of the contract is set to `init`:
```java
@gstate -> init
@assert end_join < end_choice
@assert end_join < end_redeem
Create escrow_contract(address e, int end_join, int end_choice, int end_redeem, int feeRate) {
    glob.e = e
    glob.end_join = end_join
    glob.end_choice = end_choice
    glob.end_redeem = end_redeem
    glob.feeRate = feeRate
}
```

## Joining the escrow

The following two clauses allow users to join the contract.
The buyer must join first and provide the seller's address and a deposit in ALGO, while the seller just needs to join before the join phase ends.
```java
@gstate init -> join1
@round (,glob.end_join)
@pay $amt of ALGO : caller -> escrow
@assert caller != b  // no schizophrenia
OptIn join(address b) { 
    glob.a = caller
    glob.b = b
    glob.deposit = amt
}
```

The `@gstate` clause allows the seller to join after the buyer. 
Even though we already know the seller's address from the previous `join`, this `OptIn` clause is needed to provide the seller with a local state:
```java
@gstate join1 -> join2
@round (,glob.end_join)
@from glob.b
OptIn join() { }
```

## Making the choice

In the choice phase, both the buyer and the seller can choose the recipient of the deposit.
The following two clauses allow these users to make their choice, in any order.
The choice in recorded in the users' local variables.
Since local variables only exist for the users who joined the contract, this guarantees that external users cannot execute these clauses.
```java
@gstate join2 -> choice1
@round (,glob.end_choice)
choose(address choice) { 
    caller.choice = choice
    glob.first = caller        // record the first user to make a choice
}
```

The `@assert` precondition in the second clause ensures that the two users who make the choice are different:
```java
@gstate choice1 -> choice2
@round (,glob.end_choice)
@assert caller != glob.first   // the two choosers must be different
choose(address choice) { 
    caller.choice = choice
}
```

## Redeeming the deposit

If the seller has not joined the contract, the buyer can redeem the deposit after the redeem phase.
```java
@gstate join1 -> end
@round (glob.end_join, glob.end_redeem)
@close ALGO : escrow -> glob.a
redeem() { }
```

If the buyer and the seller's choices agree, then the recipient can redeem the deposit:
```java
@gstate choice2 -> end
@round (,glob.end_redeem)
@assert glob.a.choice == glob.b.choice
@close ALGO : escrow -> glob.a.choice
redeem() { }
```

## Arbitrating a dispute
 
If the buyer and the seller have not reached an agreement within the end of the choice period, the escrow can intervene to resolve the dispute.
The following clause allows the escrow to choose the recipient, and to take part of the deposit as a fee.
```java
@gstate -> arbitrated
@round (glob.end_redeem,)
@from glob.e 
@pay (glob.deposit * glob.feeRate / 100) of ALGO : escrow -> glob.e
arbitrate(address choice) {
    glob.eChoice = choice    
}
```

After the escrow has arbitrated the dispute (and taken the fee), the chosen user can redeem all the ALGOs remaining in the contract:
```java
@gstate arbitrated -> end
@close ALGO : escrow -> glob.eChoice
redeem() { }
```

## Deleting the contract

The following clause allows the creator to delete a terminated contract:
```java
@gstate end -> 
@from creator
Delete delete() { }
```

## Disclaimer

The project is not audited and should not be used in a production environment.
