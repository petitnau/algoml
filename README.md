# AlgoML

AlgoML (after *Algorand Modelling Language*) is a DSL for specifying Algorand smart contracts, which compiles into TEAL scripts.

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

## Credits

AlgoML has been designed by Roberto Pettinau and Massimo Bartoletti from the University of Cagliari, Italy.
