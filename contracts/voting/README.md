# Voting

This contract is inspired by [this contract](https://developer.algorand.org/solutions/example-permissioned-voting-stateful-smart-contract-application/) by Jason Weathersby, with however, noticeable differences.

This contract is composed of two phases:
- a candidating phase, in which any user can apply as a candidate
- a voting phase, in which users that have received (off contract) a particular voting token, can spend units of those tokens to vote the previously applied candidates

## Contract state

The contract state is stored in the following variables:

Global variables:
- `candidate_begin` is the first round in which users can candidate
- `candidate_end` is the last users in which users can candidate
- `vote_begin` is the first round in which users can vote candidates
- `vote_end` is the last round in which users can vote candidates
- `vote_token` is the token that users need to vote

Local variables:
- `votes` is the number of votes of the user

All the variables but `votes` do not change throughout the life of the contract.

## Creating the poll

When a user wants to cerate a ballot, they must provide the round window in which users can candidate, the round window in which users can vote, and the id of the token that users must use to cast their vote. 

```algoml
Create ballot(int candidate_begin, int candidate_end, int vote_begin, int vote_end, token vote_token) {
	glob.candidate_begin = candidate_begin
	glob.candidate_end = candidate_end
	glob.vote_begin = vote_begin
	glob.vote_end = vote_end
	glob.vote_token = vote_token
}
```

The `ballot` function has five parameters, one per global variable. When called, the contract and all the global state variables are initialized.

## Candidating

Users that want to candidate can do so within the candidate round window. To apply, they must opt into the contract in order to allocate the space on their account required to save how many users have voted for them. 

```algoml
@round (glob.candidate_begin, glob.candidate_end)
OptIn candidate() {
	loc.votes = 0
}
```

The candidate function can only be called between the round `candidate_begin` and the round `candidate_end`. When a user calls this function, they opt into the contract, and their local variable `votes` is initialized to 0.

## Voting

After the candidate phase has ended and the vote phase has begun, users that own units of the vote_token can cast their vote. To do so, they can send one unit of the vote token to the contract, while also indicating which account their vote is directed to.

```algoml
@round (glob.vote_begin, glob.vote_end)
@pay 1 of glob.vote_token : caller -> escrow
vote(address candidate) {
	candidate.votes += 1
}
```

The vote function can be called in the rounds between `vote_begin` and `vote_end`. To call the function, users must send one `vote_token` to the escrow, and pass as an argument the address of the `candidate` that they are voting for. When called, the `votes` variable of that `candidate` is incremented.

## Deleting the contract

After the voting phase has ended and the votes are checked, the contract can be deleted by the creator, retrieving the funds used to initialize the contract, and all the tokens that were sent to cast a vote.

```algoml
@round (glob.vote_end, )
@from creator
@close glob.vote_token : escrow -> creator
@close ALGO : escrow -> creator
Delete delete() {}
```

The `delete` function can be called at any round after `vote_end`, only by the creator of the contract. To call the function, they must send a close transaction of both the `vote_token` and the ALGOs from the escrow account to their account. Once called, the contract is deleted (as indicated by the `Delete` modifier).

# Disclaimer

The project is not audited and should not be used in a production environment.
