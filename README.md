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

On a lower level, an AlgoML program models two contracts: a stateful application, and a stateless contract account. The stateful application is in charge of all of the high level logic of the contract, while the stateless contract's only duty is holding funds, delegating all spending logic to the stateful application.

## Use cases

We illustrate the usage of AlgoML on some relevant use cases:
- [Automated Market Makers](contracts/amm)
- [Crowdfunding](contracts/crowdfund)
- [King of the Algo Throne](contracts/kotat)
- [Vaults](contracts/vaults)
- [Voting](contracts/voting)

## Building AlgoML

1\. Clone the AlgoML repository
```
git clone https://github.com/petitnau/algoml
```
2\. [Install opam](https://ocaml.org/docs/install.html#OPAM) 

3\. Install dune
```
opam install dune
```
4\. Install AlgoML dependencies
```
opam install algoml --deps-only
```
5\. Build the source
```
dune build
```

## Compiler usage

To compile an AlgoML file into TEAL scripts, the following command can be used:
```console
dune exec ./amlc.exe /path/to/input.aml [-o outprefix]
```
The compiler will output three files: `output_approval.teal`, `output_clear.teal`, and `output_escrow.teal`.

## Syntax highlighting

Syntax highlighting is supported on [vscode](https://marketplace.visualstudio.com/items?itemName=RobertoPettinau.algoml-lang) 

## Disclaimer

The project is not audited and should not be used in a production environment.

## Credits

AlgoML has been designed by Roberto Pettinau and Massimo Bartoletti from the University of Cagliari, Italy.
