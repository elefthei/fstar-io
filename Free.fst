module Free

noeq
type op_sig (op:Type u#a) = {
  args : op -> Type u#a;
  res : (cmd:op) -> (args cmd) -> Type u#a;
}

(** We should try to define PartialCall as an operation, not as a new constructor
    on the free monad.

    CA: I tried to do this, but there are some universe problems:
    1. When trying to use add_sig on io_sig and req_sig, I get an error that one signature is
       u#0 u#0 and the other is u#1 u#0.
    2. To define an effect, the representation must be polymorphic in exact two universes.

    Some code that may be useful:
type cmds = | Requires | Openfile | Read | Close | GetTrace
let _req_cmds (x:cmds) : bool = x = Requires
type req_cmds : Type0 = x:cmds{_req_cmds x} 
unfold let req_args (x:req_cmds) : Type u#1 = pure_pre 
unfold let req_res (x:req_cmds) (pre:req_args x) : Type u#0 = squash pre
let req_sig : op_sig req_cmds = { args = req_args; res = req_res; }
**)

noeq
type free (op:Type0) (s:op_sig op) (dec:Type0) (a:Type) : Type =
| Call : (l:op) -> (arg:s.args l) -> cont:(s.res l arg -> free op s dec a) -> free op s dec a
| PartialCall : (pre:pure_pre) -> cont:((squash pre) -> free op s dec a) -> free op s dec a
| Decorated : (d:dec) -> #b:Type -> (* cont0:(unit -> *) free op s dec b (* ) *) ->
                                      cont1:(b-> free op s dec a) -> free op s dec a
| Return : a -> free op s dec a

let free_return (op:Type) (s:op_sig op) (dec:Type0) (a:Type) (x:a) : free op s dec a =
  Return x

let rec free_bind
  (op:Type0)
  (s:op_sig op)
  (dec:Type0)
  (a:Type)
  (b:Type)
  (l : free op s dec a)
  (k : a -> free op s dec b) :
  Tot (free op s dec b) =
  match l with
  | Return x -> k x
  | Call cmd args fnc ->
      Call cmd args (fun i ->
        free_bind op s dec a b (fnc i) k)
  | PartialCall pre fnc ->
      PartialCall pre (fun _ ->
        free_bind op s dec a b (fnc ()) k)
  | Decorated d m fnc -> Decorated d m (fun i ->
        free_bind op s dec a b (fnc i) k)

let free_map
  (op:Type)
  (s:op_sig op)
  (a:Type)
  (b:Type)
  (l : free op s a)
  (k : a -> b) :
  Tot (free op s b) =
  free_bind op s a b
    l (fun a -> free_return op s b (k a))

let free_codomain_ordering
  (#op:Type)
  (#s:op_sig op)
  (#a:Type)
  (x:(free op s a){Call? x}) :
  Lemma (forall r. Call?.cont x r << x) = ()

let add_sig
  (op:Type)
  (#p:op -> bool)
  (#q:op -> bool)
  (s1:op_sig (x:op{p x}))
  (s2:op_sig (x:op{q x})) :
  Tot (op_sig (y:op{p y || q y})) = {
    args = (fun (x:op{p x || q x}) -> if p x then s1.args x else s2.args x);
    res = (fun (x:op{p x || q x}) -> if p x then s1.res x else s2.res x)
 }
