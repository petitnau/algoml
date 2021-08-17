open Types

type tealcmd = 
| OPCLiteral of string
| OPLabel of string
| OPNoop
| OPBz of tealexp * string
| OPBnz of tealexp * string
| OPB of string
| OPLocalPut of tealexp * tealexp * tealexp
| OPGlobalPut of tealexp * tealexp
| OPErr
| OPSeq of tealcmd list
| OPAssert of tealexp
| OPIfte of tealexp * tealcmd list * tealcmd list
| OPAssertSkip of tealexp

| OPReturn of tealexp

and tealexpd = 
| OPLocalGetEx of tealexp * tealexp * tealexp
| OPGlobalGetEx of tealexp * tealexp
| OPSwap of tealexpd

and tealexp =
| OPELiteral of string
(* | OPSeparate of string * tealop list *)
| OPEBz of tealexpd * string
| OPEBnz of tealexpd * string

| OPComment of string
(* | OPLabel of string *)

| OPInt of int
| OPByte of string

| OPIbop of ibop * tealexp * tealexp
| OPCbop of cbop *  tealexp * tealexp
| OPLbop of lbop *  tealexp * tealexp
| OPLNot of tealexp
| OPBNot of tealexp
| OPLen of tealexp
| OPItob of tealexp
| OPBtoi of tealexp

| OPTxn of txnfield
| OPTxna of txnfield * int
| OPGtxn of int * txnfield
| OPGtxna of int * txnfield * int
| OPGlobal of globalfield

| OPTypeEnum of typeenumfield
| OPOnCompletion of oncomplete

| OPOptedIn of tealexp * tealexp

| OPLocalGet of tealexp * tealexp 
| OPLocalExists of tealexp * tealexp * tealexp
| OPLocalGetTry of tealexp * tealexp * tealexp 
| OPGlobalGet of tealexp 
| OPGlobalExists of tealexp * tealexp
| OPGlobalGetTry of tealexp * tealexp
| OPPop of tealexpd

and tealblock = OPBlock of tealcmd list * tealcmd list
and tealprog = OPProgram of tealblock list

and typeenumfield = 
| TEPay
| TEAxfer
| TEAppl

and globalfield = 
| GFZeroAddress
| GFGroupSize
| GFRound
| GFLatestTimestamp
| GFCreatorAddress
(* | GFCurrentApplicationID *)

and txnfield =
| TFSender
| TFFee
| TFReceiver
| TFAmount
| TFCloseRemainderTo
| TFTypeEnum
| TFXferAsset
| TFAssetAmount
| TFAssetSender
| TFAssetReceiver
| TFAssetCloseTo
(* | TFGroupIndex *)
| TFApplicationID
| TFOnCompletion
| TFApplicationArgs
| TFNumAppArgs
| TFAccounts
| TFNumAccounts
| TFRekeyTo
| TFAssets
| TFNumAssets
| TFApplications
| TFNumApplications