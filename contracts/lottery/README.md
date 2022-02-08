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
* `player1`: player1's address
* `player2`: player2's address
* `commitment1`: player1's commitment
* `commitment2`: player2's commitment
* `secret1`: player1's secret
* `secret2`: player2's secret

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

## References

- **[BZ17]** Massimo Bartoletti, Roberto Zunino. [Constant-Deposit Multiparty Lotteries on Bitcoin](https://eprint.iacr.org/2016/955). Financial Cryptography Workshops, 2017

## Disclaimer

The project is not audited and should not be used in a production environment.

