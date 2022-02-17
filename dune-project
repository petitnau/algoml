(lang dune 2.8.5)
(name algoml)
(using menhir 2.0)
(generate_opam_files true)

(source (github petitnau/algoml))
(license MIT)
(authors "Roberto Pettinau" "Massimo Bartoletti")
(maintainers "roberto.pettinau99@gmail.com")

(package
 (name algoml)
 (synopsis "An Algorand smart contract modelling language")
 (depends
  (batteries (>= 3.5.0))
  (cmdliner (>= 1.0.4))
  (menhir (>= 20211230))
  (ounit2 (>= 2.2.6))))
