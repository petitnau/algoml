# Chain-based Ponzi scheme

We implement a chain-based Ponzi scheme [[BC20]](#references), where users invest ALGOs, and are paid back with interests in order of arrival.

## Contract state
The contract state is stored in the following variables:

Immutable global variables:
* `intR`: interest rate (percent)
* `feeR`: fee rate (percent)
* `mindep`: the minimum amount of ALGOs a user must deposit to join the scheme
* `maxrounds`: maximum number of rounds for a user to withdraw 

Mutable global variables:
* `balance`: contract balance
* `ctrPay`: index of the next investor to be paid
* `ctrTot`: total number of investors
* `wdstart`: starting round of the current withdraw period

Local variables:
* `deposit`: the amount of ALGOs the user can withdraw
* `pos`: user position in the payment queue

## Contract creation

Any user can create a scheme by providing the parameters corresponding to the immutable global variables.
Upon creation, the contract is in state `notpaying`. 
The state will become `paying` when the contract has funds to pay the next user in the queue.
```java
@gstate -> notpaying
Create init(int intR, int feeR, int mindep, int maxrounds) {
    glob.intR = intR
    glob.feeR = feeR
    glob.mindep = mindep
    glob.maxrounds = maxrounds
    glob.balance = 0
    glob.ctrPay = 0
    glob.ctrTot = 0
}
```

## Joining the scheme

Any user can join the payment queue by providing a deposit of at least `mindep` ALGOs.
The contract creator takes a fee on every deposit, determied by the fee rate `feeR`.
After a join clause is executed, the contract has a nonzero balance, 
so its state is set to `paying`.
A withdraw period is started by setting the clock `wdstart` to the current round:
```java
@gstate -> paying
@round $r
@pay $v of ALGO : caller -> escrow
@pay (v * glob.feeR / 100) of ALGO : escrow -> creator
@assert v >= glob.mindep
OptIn join() {
    loc.deposit = v + (v * glob.intR) / 100
    loc.pos = glob.ctrTot
    glob.ctrTot += 1
    glob.balance += v
    glob.wdstart = r
}
```

## Withdrawing funds

If the contract balance is enough and the withdraw period is not expired, the next user in the queue can withdraw her deposit with interests:
```java
@gstate paying -> paying
@round (glob.wdstart,glob.wdstart + glob.maxrounds)$r
@pay caller.deposit of ALGO : escrow -> caller
@assert glob.balance > caller.deposit
@assert caller.pos == glob.ctrPay
withdraw() {
    glob.balance -= caller.deposit
    glob.ctrPay += 1
    caller.deposit = 0
    glob.wdstart = r
}
```

If the contract balance is not enough, the next user in the payment queue can withdraw the whole contract balance.
Once the clause is executed, the contract state is reverted to `notpaying`.
```java
@gstate paying -> notpaying
@round (glob.wdstart,glob.wdstart + glob.maxrounds)
@pay glob.balance of ALGO : escrow -> caller
@assert glob.balance <= caller.deposit
@assert caller.pos == glob.ctrPay
withdraw() {
    if (glob.balance == caller.deposit) glob.ctrPay += 1
    glob.balance = 0
    caller.deposit -= glob.balance
}
```

## Skipping unresponsive users

If unproperly handled, a user who avoids withdrawing funds in her turn could prevent the other users from withdrawing.
To address this issue, we define a period of `maxround` rounds (starting from the round when the contract becomes `paying`)
wherein the next user in the queue can withdraw.
If the user does not redeem within maxrounds, anyone can make the queue advance to the next user:
```java
@gstate paying -> notpaying
@round (glob.wdstart + glob.maxrounds, )
@assert glob.ctrPay < glob.ctrTot
next() { 
    glob.ctrPay += 1
}
```

## References

* **[BC20]** M. Bartoletti, S. Carta, T. Cimoli, R. Saia. Dissecting Ponzi schemes on Ethereum: identification, analysis, and impact. In Future Generation Computer Systems, 102, 2020

## Disclaimer

The project is not audited and should not be used in a production environment.
