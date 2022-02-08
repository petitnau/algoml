# 2-players lottery

We speficy a lottery where 2-players bet 1 ALGO each, and the winner redeems the whole pot. To achieve fairness, the lottery is structured in commit-reveal phases as follows:
1. player1 joins the lottery by paying 1 ALGO and committing to a secret
2. player2 joins the lottery by payin 1 ALGO committing to another secret
3. player1 reveals the secret, or otherwise her bet can be redeemed by player2
4. player2 reveals the secret, or otherwise her bet can be redeemed by player1
5. the winner, who is determined as a function of the two revealed secrets, can redeem the whole pot.

This specification follows the protocol for zero-collateral lotteries defined in [[BZ17]](#references), thereby achieving fairness.

## Contract state

The contract state consists of the following global variables:
* `end_commit`: last round to join
* `end_reveal`: last round to reveal
* `player1`,`player2`: the players' addresses
* `commitment1`,`commitment2`: the players' commitments
* `secret1`, `secret2`: the players' secrets

## Creating the lottery

Any user can create a lottery by providing the deadlines. The initial state of the contract is set to `joined0`:
```java
@gstate -> joined0	            // in state joined0, no player has joined yet
@assert end_commit < end_reveal
Create lottery(int end_commit, int end_reveal) {
    glob.end_commit = end_commit
    glob.end_reveal = end_reveal
}
```

## Joining the lottery

The following clause allows the first player to join the lottery. To do so, the player must pay 1 ALGO as a bet, and provide a commitment. 
The clause must be executed from state `joined0`, and once it is finalised the state takes a transition to `joined1`. 
In this way we ensure that at most 2 players will join the lottery.
```java
@gstate joined0 -> joined1 
@round (,glob.end_commit)
@pay 1 of ALGO : caller -> escrow
join(string commitment) {
    glob.player1 = caller
    glob.commitment1 = commitment
}
```

Similarly, the following clause allows the second player to join the lottery.
The `@assert` precondition ensures that the commitments of the two players (and so, their secrets) are different. This is needed to thwart attacks where an adversary replays the commitment of the other player in order to win.
```java
@gstate joined1 -> joined2
@round (,glob.end_commit)
@pay 1 of ALGO : caller -> escrow
@assert glob.commitment1 != commitment 
join(string commitment) {
    glob.player2 = caller
    glob.commitment2 = commitment
}
```

If, after the commit deadline, the second player has not joined, then player1 can redeem the bet:
```java
@gstate joined1 -> joined0
@round (glob.end_commit,)
@close ALGO : escrow -> glob.player1
redeem() {}
```

The following clause allows the creator to delete the contract if no one has joined within the commit deadline:
```java
@gstate joined0 -> end
@round (glob.end_commit,)
@from creator
Delete delete() {}
```

## Revealing the secrets

Once both players have joined the lottery, they must reveal their secrets one after the other. Revealing a secrets amounts to providing a value whose hash equals to the committed value. Player1 must reveal first.
```java
@gstate joined2 -> revealed1
@round (glob.end_commit,glob.end_reveal)
@assert sha256(secret) == glob.commitment1
reveal(string secret) {
    glob.secret1 = secret
}
```

Player2 must reveal after player1. The deadline extension of 100 rounds is needed to avoid attacks where player1 reveals very close to the deadline, so preventing player2 to reveal by the deadline.
```java
@gstate revealed1 -> revealed2
@round (glob.end_commit,glob.end_reveal+100)
@assert sha256(secret) == glob.commitment2
reveal(string secret) {
    glob.secret2 = secret
}
```

If player1 has not revealed by the deadline, player2 can redeem the whole pot:
```java
@gstate joined2 -> end
@round (glob.end_reveal,)
@close ALGO : escrow -> glob.player2
redeem() {}
```

If player2 has not revealed by the (extended) deadline, player1 can redeem the whole pot:
```java
@gstate revealed1 -> end
@round (glob.end_reveal+100,)
@close ALGO : escrow -> glob.player1
redeem() {}
```

## Winning the lottery

Player1 wins the lottery when the sum of the secrets' lengths is even:
```java
@gstate revealed2 -> end
@assert (len(glob.secret1) + len(glob.secret2)) % 2 == 0
@close ALGO : escrow -> glob.player1 
redeem() {}
```

Dually, player2 wins the lottery when the sum of the secrets' lengths is odd:
```java
@gstate revealed2 -> end
@assert (len(glob.secret1) + len(glob.secret2)) % 2 == 1
@close ALGO : escrow -> glob.player2
redeem() {}
```

If no one reveals, then 2 ALGOs are frozen in the contract. This is not a problem, since we assume that a rational player will always reveal.  
If desired, we can unfreeze the 2 ALGOs by allowing both players to redeem 1 ALGO after some time


## References

- **[BZ17]** Massimo Bartoletti, Roberto Zunino. [Constant-Deposit Multiparty Lotteries on Bitcoin](https://eprint.iacr.org/2016/955). Financial Cryptography Workshops, 2017

## Disclaimer

The project is not audited and should not be used in a production environment.

