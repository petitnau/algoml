open Tealtypes
open Types

let txnfield_to_str (tf:txnfield) : string = match tf with TFSender -> "Sender" | TFFee -> "Fee" | TFReceiver -> "Receiver" | TFAmount -> "Amount" | TFCloseRemainderTo -> "CloseRemainderTo"
| TFTypeEnum -> "TypeEnum" | TFXferAsset -> "XferAsset" | TFAssetAmount -> "AssetAmount" | TFAssetSender -> "AssetSender" | TFAssetReceiver -> "AssetReceiver"
| TFAssetCloseTo -> "AssetCloseTo" | TFApplicationID -> "ApplicationID" | TFOnCompletion -> "OnCompletion" | TFApplicationArgs -> "ApplicationArgs"
| TFNumAppArgs -> "NumAppArgs" | TFAccounts -> "Accounts" | TFNumAccounts -> "NumAccounts" | TFRekeyTo -> "RekeyTo" | TFAssets -> "Assets" 
| TFNumAssets -> "NumAssets" | TFApplications -> "Applications" | TFNumApplications -> "NumApplications" | TFConfigAssetTotal -> "ConfigAssetTotal" 
| TFConfigAssetDecimals -> "ConfigAssetDecimals" | TFConfigAssetManager -> "ConfigAssetManager" | TFConfigAssetReserve -> "ConfigAssetReserve"
| TFConfigAssetFreeze -> "ConfigAssetFreeze"| TFConfigAssetClawback -> "ConfigAssetClawback"

let globalfield_to_str (gf:globalfield) : string = match gf with GFZeroAddress -> "ZeroAddress" | GFGroupSize -> "GroupSize" | GFRound -> "Round" | GFLatestTimestamp -> "LatestTimestamp"
| GFCreatorAddress -> "CreatorAddress"

let typeenum_to_str (te:typeenumfield) : string = match te with TEPay -> "pay" | TEAxfer -> "axfer" | TEAppl -> "appl" | TEAcfg -> "acfg"

let oncompletion_to_str (onc:oncomplete) : string = match onc with NoOp -> "NoOp" | Update -> "UpdateApplication" | Delete -> "DeleteApplication" | OptIn -> "OptIn"
| OptOut -> "CloseOut" | ClearState -> "ClearState" |  Create -> failwith "No str"
