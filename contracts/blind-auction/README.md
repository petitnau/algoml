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

```java
@round (,glob.end_bidding)
@pay $v of ALGO : caller -> escrow
Optin bid(string sealed_bid) {
    loc.sealed_bid = sealed_bid
    loc.deposit = v
    loc.can_redeem = false
}
```

## Disclaimer

The project is not audited and should not be used in a production environment.
