open Types
include Monads
open Amlprinter

module Ide = struct
  let to_str (Ide(s):ide) : string = s
end

module Eval = struct
  let get_type (v:eval) : vartype = 
    match v with
    | VInt(_) -> TInt
    | VString(_) -> TString
    | VBool(_) -> TBool
    | VToken(_) -> TToken
    | VAddress(_) -> TAddress
end

module Env = struct 
  (* let empty : env = fun _ -> Unbound *)
  let empty : env = []
  
  let rec apply (d:env) (i:ide) : dval = match d with
    | (i', dv)::_ when i = i' -> dv
    | _::tl -> apply tl i
    | [] -> DUnbound

  let apply_eval (d:env) (i:ide) : eval option = match apply d i with
    | DUnbound -> None
    | DBound(_,_,v) -> v

  let apply_ex (d:env) (i:ide) : eval = 
    match apply d i with
    | DUnbound -> raise (ErrDynamic ("Can't get "^(Ide.to_str i)^": ide not bound"))
    | DBound(_,_,None) -> raise (InitError ("Can't get "^(Ide.to_str i)^": ide not initialized"))
    | DBound(_,_,Some(v)) -> v
  
  let unbind (d:env) (i:ide) : env = List.filter (fun e -> (fst e) <> i) d

  let bind (d:env) (i:ide) (m:muttype) (t:vartype) (v:eval option) : env = 
    let d = unbind d i in (i, DBound(m, t, v))::d

  let decl (d:env) (i:ide) (m:muttype) (t:vartype) : env = 
    bind d i m t None

  let init (d:env) (i:ide) (m:muttype) (t:vartype) (v:eval) : env = 
    bind d i m t (Some v)

  let update (d:env) (i:ide) (v:eval) : env = 
    match apply d i with
    | DUnbound -> raise (ErrDynamic ("Can't update "^(Ide.to_str i)^": ide not bound")) (* TO CHANGE WITH STATIC CHECK*)
    | DBound(Mutable as m,t,_)
    | DBound(Immutable as m,t,None) when (Eval.get_type v) = t -> bind d i m t (Some v)
    | DBound(Immutable,_,Some(_)) -> raise (MutError ("Can't update "^(Ide.to_str i)^": immutable variable"))
    | _ -> raise TypeError

  let rec init_state (d:env) (s:statetype) (dl:decl list) : env =
    match dl with
    | [] -> d
    | Declaration(s', m, t, i)::tl when s = s' -> 
      let d' = decl d i m t in
      let d'' = 
        (if s=TGlob then decl d' (Ide "gstate") Mutable TString
        else decl d' (Ide "lstate") Mutable TString) in
      init_state d'' s tl
    | _::tl -> init_state d s tl
  
  let rec init_params (d:env) (pl:parameter list) (apl:eval list) : env option =
      match pl, apl with
      | Parameter(t,i)::pltl, v::apltl -> 
        let d' = init d i Immutable t v in
        init_params d' pltl apltl
      | [], [] -> Some(d)
      | _ -> None
      
end


module LocalEnvs = struct
  let empty : localenvs = []

  let rec apply (lds:localenvs) (x:address) : env option = match lds with
    | (x', d)::_ when x = x' -> Some(d)
    | _::tl -> apply tl x
    | [] -> None

  let apply_ex (lds:localenvs) (x:address) : env = 
    match apply lds x with
    | None -> raise NonOptedError
    | Some(d) -> d

  let unbind (lds:localenvs) (x:address) = List.filter (fun e -> (fst e) <> x) lds 

  let bind (lds:localenvs) (x:address) (d:env) : localenvs = 
    let lds = unbind lds x in (x, d)::lds
end


module Balance = struct
  let empty : balance = [(Algo, 0)]

  let rec apply (b:balance) (t:tok) : int option = match b with
    | (t', d)::_ when t = t' -> Some(d)
    | _::tl -> apply tl t
    | [] -> None

  let unbind (b:balance) (t:tok) = List.filter (fun e -> (fst e) <> t) b 

  let bind (b:balance) (t:tok) (amt:int) = 
    let b = unbind b t in (t, amt)::b
end


module Address = struct
  let counter = ref (-1)

  let latest () : address = Address(!counter)
  
  let create () : address =
    counter := !counter + 1;
    Address(!counter)
end


module Account = struct
  let empty_user (): account = 
    UserAccount(Address.create(), Balance.empty, LocalEnvs.empty) 
  
  let empty_contract (p:contract) (creator:address) : account =
    let Contract(dl,_) = p in
    let gd = Env.init_state Env.empty TGlob dl in
    ContractAccount(Address.create(), Balance.empty, LocalEnvs.empty, creator, p, gd)

  let get_address (a:account) : address = 
    match a with
    | UserAccount(x,_,_) | ContractAccount(x,_,_,_,_,_) -> x

  let get_localenvs (a:account) : localenvs = 
    match a with
    | UserAccount(_,_,lds) | ContractAccount(_,_,lds,_,_,_) -> lds

  let get_localenv (a:account) (cx:address): env option = 
    LocalEnvs.apply (get_localenvs a) cx
      
  let get_globalenv (a:account) : env option = 
    match a with
    | ContractAccount(_,_,_,_,_,gd) -> Some(gd)
    | _ -> None

  let get_globalenv_ex (a:account) : env = 
    match get_globalenv a with
    | None -> failwith "User accounts do not have a global env"
    | Some(gd) -> gd

  let get_creator_ex (a:account) : address = 
    match a with
    | ContractAccount(_,_,_,c,_,_) -> c
    | UserAccount(_,_,_) -> failwith "User accounts do not have a creator"

  let get_contract_ex (a:account) : contract = 
    match a with
    | ContractAccount(_,_,_,_,p,_) -> p
    | UserAccount(_,_,_) -> failwith "User accounts do not have a contract"

  let bind_balance (a:account) (t:tok) (amt:int) : account = 
    match a with
    | UserAccount(x, b, lds) ->  
      UserAccount(x, Balance.bind b t amt, lds) 
    | ContractAccount(x, b, lds, c, p, gd) ->
      ContractAccount(x, Balance.bind b t amt, lds, c, p, gd) 

  let unbind_balance (a:account) (t:tok) : account = 
    match a with
    | UserAccount(x, b, lds) ->  
      UserAccount(x, Balance.unbind b t, lds) 
    | ContractAccount(x, b, lds, c, p, gd) ->
      ContractAccount(x, Balance.unbind b t, lds, c, p, gd) 
      
  let unbind_localenv (a:account) (cx:address) : account = 
    match a with
    | UserAccount(x, b, lds) ->  
      UserAccount(x, b, LocalEnvs.unbind lds cx ) 
    | ContractAccount(x, b, lds, c, p, gd) ->
      ContractAccount(x, b, LocalEnvs.unbind lds cx, c, p, gd) 

  let bind_localenv (a:account) (cx:address) (ld:env) : account = 
    match a with
    | UserAccount(x, b, lds) ->  
      UserAccount(x, b, LocalEnvs.bind lds cx ld) 
    | ContractAccount(x, b, lds, c, p, gd) ->
      ContractAccount(x, b, LocalEnvs.bind lds cx ld, c, p, gd) 
  
  let bind_globalenv_ex (a:account) (gd:env) : account = 
    match a with
    | UserAccount(_, _, _) -> failwith "User accounts do not have a global env"
    | ContractAccount(x, b, lds, c, p, _) ->
      ContractAccount(x, b, lds, c, p, gd) 
  
  let apply_balance (a:account) (t:tok) : int option = match a with
    | UserAccount(_,b,_) | ContractAccount(_,b,_,_,_,_) -> Balance.apply b t
    
  let apply_balance_ex (a:account) (t:tok) : int = 
    match apply_balance a t with
    | Some(n) -> n
    | None -> raise (NonOptedTokenError (string_of_token t))

  let opt_in (a:account) (c:account) : account =
    let cx = get_address c in
    let dl = (match c with
      | UserAccount(_,_,_) -> failwith "Cannot opt into user account"
      | ContractAccount(_, _, _, _, Contract(dl,_), _) -> dl) in 
    let ld = Env.init_state Env.empty TLoc dl in
    bind_localenv a cx ld

  let opt_out (a:account) (cx:address) : account = 
    unbind_localenv a cx    

  let get_localv (a:account) (cx:address) (i:ide) : eval option =
    let lds = get_localenvs a in
    let* ld = LocalEnvs.apply lds cx in
    Env.apply_eval ld i
    

  let get_localv_ex (a:account) (cx:address) (i:ide) : eval = 
    let lds = get_localenvs a in
    let ld = LocalEnvs.apply_ex lds cx in
    Env.apply_ex ld i

  let set_localv_ex (a:account) (cx:address) (i:ide) (v:eval) : account = 
    let lds = get_localenvs a in
    let ld = LocalEnvs.apply_ex lds cx in
    let ld' = Env.update ld i v in
    bind_localenv a cx ld'
  
  let get_globalv (a:account) (i:ide) : eval option = 
    let* gd = get_globalenv a in
    let dv = Env.apply gd i in
    match dv with
    | DUnbound -> None
    | DBound(_,_,v) -> v

  let get_globalv_ex (a:account) (i:ide) : eval = 
    let gd = get_globalenv_ex a in
    Env.apply_ex gd i

  let set_globalv_ex (a:account) (i:ide) (v:eval) : account = 
    let gd = get_globalenv_ex a in
    let gd' = Env.update gd i v in
    bind_globalenv_ex a gd'
end


module State = struct
  let empty : state = {accounts = []; round = 0; timestamp = 0}

  let get_account (s:state) (x:address) : account option = 
    let rec apply_accounts al x = match al with
      | (x', a)::_ when x = x' -> Some(a)
      | _::tl -> apply_accounts tl x
      | [] -> None
    in apply_accounts s.accounts x

  let get_account_ex (s:state) (x:address) : account = 
    match get_account s x with
    | None -> failwith "Account does not exist"
    | Some(a) -> a

  let unbind (s:state) (x:address) : state = 
    {s with accounts = List.filter (fun e -> (fst e) <> x) s.accounts}

  let bind (s:state) (a:account) : state = 
    let x = match a with
      | UserAccount(x,_,_) -> x
      | ContractAccount(x,_,_,_,_,_) -> x in
    let s = unbind s x in {s with accounts = (x,a)::s.accounts}

  let apply_balance (s:state) (x:address) (t:tok) : int option = 
    let* a = get_account s x in
    match a with
    | UserAccount(_,b,_) | ContractAccount(_,b,_,_,_,_) -> Balance.apply b t  

  let get_localv (s:state) (x:address) (cx:address) (i:ide) : eval option = 
    let* a = get_account s x in
    Account.get_localv a cx i 

  let get_localv_ex (s:state) (x:address) (cx:address) (i:ide) : eval = 
    let a = get_account_ex s x in
    Account.get_localv_ex a cx i
    
  let set_localv_ex (s:state) (x:address) (cx:address) (i:ide) (v:eval) : state = 
    let a = get_account_ex s x in
    let a' = Account.set_localv_ex a cx i v in
    bind s a' 

  let get_globalv (s:state) (x:address) (i:ide) : eval option = 
    let* a = get_account s x in
    Account.get_globalv a i

  let get_globalv_ex (s:state) (x:address) (i:ide) : eval = 
    let a = get_account_ex s x in
    Account.get_globalv_ex a i   
  
  let set_globalv_ex (s:state) (x:address) (i:ide) (v:eval) : state = 
    let a = get_account_ex s x in
    let a' = Account.set_globalv_ex a i v in
    bind s a'   
end