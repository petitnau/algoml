# Blind auction

## Contract state
The contract state is stored in the following variables:

Global variables:
* `end_bidding`: last round of the bidding period
* `end_reveal`: last round of the reveal period
* `end_redeem`: last round of the redeem period
* `highest_bid`: value of the highest bid
* `winner`: address of the auction winner

Local variables:
* `sealed_bid`: hash of the bid (32 bytes nonce + 8 bytes bid value)
* `deposit`: value deposited by the bidder
* `bid`: actual bid value
* `can_redeem`: boolean flag, true when the bidder reveals the bid, and deposit covers the bid

## Contract creation

Any user can create an auction by providing the deadlines. Upon creation, a new token is created. The token will be transferred to the winner in the redeem phase.
```java
@assert end_bidding < end_reveal
@assert end_reveal < end_redeem
@newtok 1 of NFT -> escrow
Create auction(int end_bidding, int end_reveal, int end_redeem) {
    glob.highest_bid = 0
    glob.end_bidding = end_bidding
    glob.end_reveal = end_reveal
    glob.end_redeem = end_redeem
}
```

## Bidding

Users can place a (sealed) bid before the end of the bidding period.
This requires to put a deposit to the contract. 
The deposit can be withdrawn in the redeem phase, provided that the user reveals the bid, and the deposit covers it.
```java
@round (,glob.end_bidding)
@pay $v of ALGO : caller -> escrow
Optin bid(string sealed_bid) {
    loc.sealed_bid = sealed_bid
    loc.deposit = v
    loc.can_redeem = false
}
```

## Revealing the bids

The following two clauses allow users to reveal their bids. 
A bid consists in a 32-bytes nonce, followed by 2 bytes that encode the bidded amount in ALGOs.
A bid can be revealed only if the bid amount is covered by the provided deposit.
The highest bid and the corresponding bidder are recorded in the global state.
```java
@round (glob.end_bidding,glob.end_reveal)
@assert sha256(bid) == caller.sealed_bid
@assert len(bid) = 32 + 2
@assert get_int(substring(bid,32,34)) > glob.highest_bid
@assert get_int(substring(bid,32,34)) <= caller.deposit
reveal(string bid) {
    glob.highest_bid = get_int(substring(bid,32,34))
    glob.winner = caller
}
```

A non-winner bidder can still reveal, to be able to withdraw her deposit in the redeem phase.
```java
@round (glob.end_bidding,glob.end_reveal)
@assert sha256(bid) == caller.sealed_bid
@assert len(bid) = 32 + 2
@assert get_int(substring(bid,32,34)) < glob.highest_bid
@assert get_int(substring(bid,32,34)) <= caller.deposit
reveal(string bid) {
    loc.can_redeem = true
}
```

## Disclaimer

The project is not audited and should not be used in a production environment.
