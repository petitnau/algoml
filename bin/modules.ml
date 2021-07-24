open General


module Ide = struct
  let to_str (Ide(s):ide) : string = s
end

module Env = struct 
  (* let empty : env = fun _ -> Unbound *)
  let empty : env = fun _ -> DUnbound
  
  let apply (d:env) (i:ide) : dval = d i

  let apply_ex (d:env) (i:ide) : eval = 
    match apply d i with
    | DUnbound -> failwith ("Ide "^(Ide.to_str i)^" not in env")
    | DBound(_,_,None) -> failwith ("Ide"^(Ide.to_str i)^" not initialized")
    | DBound(_,_,Some(v)) -> v
  
  let bind (d:env) (i:ide) (m:muttype) (t:vartype) (v:eval option) : env =
    fun i' -> if i <> i' then apply d i' else DBound(m, t, v)

  let decl (d:env) (i:ide) (m:muttype) (t:vartype) : env = 
    bind d i m t None

  let init (d:env) (i:ide) (m:muttype) (t:vartype) (v:eval) : env = 
    bind d i m t (Some v)

  let update (d:env) (i:ide) (v:eval) : env = 
    match apply d i with
    | DUnbound -> failwith ("Ide "^(Ide.to_str i)^" not bound") (* TO CHANGE WITH STATIC CHECK*)
    | DBound(m,t,_) -> bind d i m t (Some v)

  let rec init_state (d:env) (s:statetype) (dl:decl list) : env =
    match dl with
    | [] -> d
    | Declaration(s', m, t, i, None)::tl when s = s' -> 
      let d' = bind d i m t None in
      init_state d' s tl
    | _::tl -> init_state d s tl
  
  let rec init_params (d:env) (pl:parameter list) (apl:eval list) : env option =
      match pl, apl with
      | Parameter(t,i)::pltl, v::apltl -> 
        let d' = init d i Mutable t v in
        init_params d' pltl apltl
      | [], [] -> Some(d)
      | _ -> None
      
end


module LocalEnvs = struct
  let empty : localenvs = fun _ -> None

  let apply (lds:localenvs) (x:address) : env option = lds x

  let apply_ex (lds:localenvs) (x:address) : env = 
    match apply lds x with
    | None -> failwith "User not opted in"
    | Some(d) -> d

  let bind (lds:localenvs) (x:address) (d:env) : localenvs =
    fun x' -> if x <> x' then apply lds x' else Some(d)
end


module Balance = struct
  let empty : balance = fun t -> if t = Algo then Some(0) else None

  let apply (b:balance) (t:tok) : int option = b t

  let bind (b:balance) (t:tok) (amt:int option) = 
    fun t' -> if t <> t' then apply b t' else amt
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
    let gd' = Env.init gd (Ide "escrow.total") Mutable TInt (VInt 0) in
    ContractAccount(Address.create(), Balance.empty, LocalEnvs.empty, creator, p, gd')

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
    | None -> failwith "Only contract accounts have a global env"
    | Some(gd) -> gd

  let get_creator_ex (a:account) : address = 
    match a with
    | ContractAccount(_,_,_,c,_,_) -> c
    | UserAccount(_,_,_) -> failwith "User accounts do not have a creator"

  let bind_balance (a:account) (t:tok) (amt:int option) : account = 
    match a with
    | UserAccount(x, b, lds) ->  
      UserAccount(x, Balance.bind b t amt, lds) 
    | ContractAccount(x, b, lds, c, p, gd) ->
      ContractAccount(x, Balance.bind b t amt, lds, c, p, gd) 

  let bind_localenv (a:account) (cx:address) (ld:env) : account = 
    match a with
    | UserAccount(x, b, lds) ->  
      UserAccount(x, b, LocalEnvs.bind lds cx ld) 
    | ContractAccount(x, b, lds, c, p, gd) ->
      ContractAccount(x, b, LocalEnvs.bind lds cx ld, c, p, gd) 
  
  let bind_globalenv_ex (a:account) (gd:env) : account = 
    match a with
    | UserAccount(_, _, _) -> failwith "Only contract accounts have a global env"
    | ContractAccount(x, b, lds, c, p, _) ->
      ContractAccount(x, b, lds, c, p, gd) 
  
  let apply_balance (a:account) (t:tok) : int option = match a with
    | UserAccount(_,b,_) | ContractAccount(_,b,_,_,_,_) -> Balance.apply b t
    
  let opt_in (a:account) (c:account) : account =
    let cx = get_address c in
    let dl = (match c with
      | UserAccount(_,_,_) -> failwith "Cannot opt into user account"
      | ContractAccount(_, _, _, _, Contract(dl,_), _) -> dl) in 
    let ld = Env.init_state Env.empty TLoc dl in
    let ld' = Env.init ld (Ide "escrow.local") Mutable TInt (VInt 0) in
    bind_localenv a cx ld'

  let get_localv_ex (a:account) (cx:address) (i:ide) : eval = 
    let lds = get_localenvs a in
    let ld = LocalEnvs.apply_ex lds cx in
    Env.apply_ex ld i

  let set_localv_ex (a:account) (cx:address) (i:ide) (v:eval) : account = 
    let lds = get_localenvs a in
    let ld = LocalEnvs.apply_ex lds cx in
    let ld' = Env.update ld i v in
    bind_localenv a cx ld'
  
  let get_globalv_ex (a:account) (i:ide) : eval = 
    let gd = get_globalenv_ex a in
    Env.apply_ex gd i

  let set_globalv_ex (a:account) (i:ide) (v:eval) : account = 
    let gd = get_globalenv_ex a in
    let gd' = Env.update gd i v in
    bind_globalenv_ex a gd'
end


module State = struct
  let empty : state = {accounts = (fun _ -> None); round = 0; timestamp = 0}

  let get_account (s:state) (x:address) : account option = s.accounts x

  let get_account_ex (s:state) (x:address) : account = 
    match s.accounts x with
    | None -> failwith "Account does not exist"
    | Some(a) -> a

  let bind (s:state) (a:account) : state = 
    let x = match a with
      | UserAccount(x,_,_) -> x
      | ContractAccount(x,_,_,_,_,_) -> x
    in {s with accounts = fun x' -> if x <> x' then get_account s x' else Some(a)}
end