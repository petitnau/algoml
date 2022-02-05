# AlgoML

AlgoML (after *Algorand Modelling Language*) is a DSL for specifying Algorand smart contracts, which compiles into TEAL scripts.

Roughly, an AlgoML specification is a sequence of clauses of the form:
```java
@precondition1
...
@preconditionK
foo(x1,...,xn) {
  // state update
  ...
}
```
The intuition is that the function ``foo`` is enabled whenever all the preconditions are respected. Executing ``foo`` results in a state update, specified in the function body. Preconditions may have various forms: for instance, they can be predicates on the contract state, or checks that certain transactions belong to the group wherein the function is called.


## Use cases

We illustrate the usage of AlgoML on some relevant use cases:
- [Automated Market Makers](contracts/amm)
- [Crowdfunding](contracts/crowdfund)
- [King of the Algo Throne](contracts/kotat)
- [Vaults](contracts/vaults)
- [Voting](contracts/voting)

## Compiler usage

To compile an AlgoML file into TEAL scripts, the following command can be used:
```console
caml.exe /path/to/input.aml [-o outprefix]
```

## Syntax highlighting

Syntax highlighting is supported on [vscode](https://marketplace.visualstudio.com/items?itemName=RobertoPettinau.algoml-lang) 

# Disclaimer

The project is not audited and should not be used in a production environment.

## Credits

AlgoML has been designed by Roberto Pettinau and Massimo Bartoletti from the University of Cagliari, Italy.
