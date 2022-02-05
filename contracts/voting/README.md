# Voting

This contract is inspired by [this contract](https://developer.algorand.org/solutions/example-permissioned-voting-stateful-smart-contract-application/) by Jason Weathersby. The contract consists of two phases:
- an application phase, where users can apply as a candidate
- a voting phase, in which users that have received (off contract) a voting token, can spend units of those tokens to vote the candidates

## Contract state

The contract state is stored in the following variables:

Global variables:
- `candidate_begin` is the first round in which users can apply
- `candidate_end` is the last round in which users can apply
- `vote_begin` is the first round in which users can vote
- `vote_end` is the last round in which users can vote
- `vote_token` is the token that users spend in order to vote

Local variables:
- `votes` is the number of votes of the user

All the variables but `votes` are immutable throughout the contract lifetime.

## Creating the poll

Any user can crete a poll, by providing the application round period, the voting round period, and the identifier of the token that must be spent to cast vote. 

```java
@assert candidate_begin < candidate_end
@assert candidate_end < vote_begin
@assert vote_begin < vote_end
Create ballot(int candidate_begin, int candidate_end, int vote_begin, int vote_end, token vote_token) {
	glob.candidate_begin = candidate_begin
	glob.candidate_end = candidate_end
	glob.vote_begin = vote_begin
	glob.vote_end = vote_end
	glob.vote_token = vote_token
}
```

When the `ballot` function is called, the contract and all the global state variables are initialized to the corresponding actual parameters.

## Application

To apply, users must opt into the contract, by invoking the `candidate` function.

```java
@round (glob.candidate_begin, glob.candidate_end)
OptIn candidate() {
	loc.votes = 0
}
```

The `@round` clause ensures that the function can only be called in the application round period. When a user calls the function, they opt into the contract, and their local variable `votes` is initialized to 0.

## Voting

After the application phase has ended and the vote phase has started, users that own units of the `vote_token` can cast their vote. To do so, they send one token unit to the contract, specifying the account they want to vote.

```java
@round (glob.vote_begin, glob.vote_end)
@pay 1 of glob.vote_token : caller -> escrow
vote(address candidate) {
	candidate.votes += 1
}
```

The `@round` clause ensures that the `vote` function can be called only in the voting period. The `@pay` clause ensures that, to call the function, users must spend one token, transferring it to the escrow. The voted `candidate` is passed as an argument to the function. When the function is called, the `votes` variable of that `candidate` is incremented.

## Deleting the contract

After the voting phase has ended and the votes are checked, the contract can be deleted by the creator, retrieving the funds used to initialize the contract, and all the tokens that were sent to cast a vote.

```java
@round (glob.vote_end, )
@from creator
@close glob.vote_token : escrow -> creator
@close ALGO : escrow -> creator
Delete delete() {}
```

The `delete` function can be called at any round after `vote_end`, only by the creator of the contract. To call the function, they must send a close transaction of both the `vote_token` and the ALGOs from the escrow account to their account. Once called, the contract is deleted (as indicated by the `Delete` modifier).

# Disclaimer

The project is not audited and should not be used in a production environment.
