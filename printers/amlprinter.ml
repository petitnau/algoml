open Types

(* VALUES *)

let string_of_address : address -> string = function
  | Address(n) -> Printf.sprintf "Addr(%d)" n

let string_of_token : tok -> string = function
  | Token(n) -> Printf.sprintf "Token(%d)" n
  | Algo -> Printf.sprintf "Algo"
  
let string_of_eval : eval -> string = function 
  | VInt(n) -> Printf.sprintf "%d" n
  | VString(s) -> Printf.sprintf "\"%s\"" s
  | VBool(b) -> Printf.sprintf "%b" b
  | VToken(t) -> Printf.sprintf "%s" (string_of_token t)
  | VAddress(x) -> Printf.sprintf "%s" (string_of_address x)
  
let string_of_muttype : muttype -> string = function
  | Mutable -> Printf.sprintf "mut"
  | Immutable -> Printf.sprintf "imm"
  
let string_of_vartype : vartype -> string = function
  | TInt -> Printf.sprintf "int"
  | TString -> Printf.sprintf "string"
  | TBool -> Printf.sprintf "bool"
  | TToken -> Printf.sprintf "token"
  | TAddress -> Printf.sprintf "address"

let string_of_dval : dval -> string = function 
  | DBound(m,t,eo) ->
    let es = (match eo with
      | Some(e) -> (string_of_eval e)
      | None -> "None") in
    Printf.sprintf "%s %s %s" (string_of_muttype m) (string_of_vartype t) es
    
| DUnbound -> Printf.sprintf "Unbound"

let string_of_ide : ide -> string = function Ide(s) -> s

let string_of_env : env -> string = fun d ->
  "Env"^(String.concat "" (List.map (fun (i,dv) -> Printf.sprintf "[%s/%s]" (string_of_ide i) (string_of_dval dv)) d))^""

let string_of_balance : balance -> string = fun b ->
  "Balance"^(String.concat "" (List.map (fun (t,n) -> Printf.sprintf "[%s/%d]" (string_of_token t) n) b))^""

let string_of_localenvs : localenvs -> string = fun lds ->
  "LocalEnv{"^(String.concat ", " (List.map (fun (x,d) -> Printf.sprintf "%s: %s" (string_of_address x) (string_of_env d)) lds))^"}"

let string_of_account : account -> string = function
  | UserAccount(x,b,lds) -> 
    Printf.sprintf "UserAccount(%s, %s, %s)" (string_of_address x) (string_of_balance b) (string_of_localenvs lds)
  | ContractAccount(x,b,lds,c,_,gd) ->
    Printf.sprintf "ContractAccount(%s, %s, %s, %s, <prog>, %s)" (string_of_address x) (string_of_balance b)
    (string_of_localenvs lds) (string_of_address c) (string_of_env gd)

let string_of_state : state -> string = function
  | {accounts; _} -> 
    ""^(String.concat "\n" (accounts |> List.map snd |> List.map (string_of_account)))^""

let string_of_key : key -> string = function 
  | GlobVar(i) -> Printf.sprintf "GlobVar(%s)" (string_of_ide i)
  | LocVar(i,None) -> Printf.sprintf "LocVar(%s)" (string_of_ide i)
  | LocVar(i,Some(_)) -> Printf.sprintf "LocVar(%s, <exp>)" (string_of_ide i)
  | NormVar(i) -> Printf.sprintf "NormVar(%s)" (string_of_ide i)
  
  