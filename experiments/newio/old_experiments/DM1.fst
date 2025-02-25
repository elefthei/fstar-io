module DM1

open FStar.Classical.Sugar
open FStar.List.Tot.Base
open FStar.Tactics

open Free
open Free.IO
open Hist
open DM

(** This file contains a representation indexed by the pure pre- and post-condition and the hist
    weakest-precondition. 
    The file has two problems:
    1. the pure post-conditions refines the output type, but because we don't get subtyping 
       underneath type constructors (see io_subcomp) this is a problem.
    2. if a pure prop is implied by the weakest-precondition, the prop can not be checked with a 
       pure pre-condition.**)

let io_subcomp (a:Type)
  (q1:pure_post a) (q2:pure_post a)
  (m : io (v:a{q1 v})) :
  Pure (io (v:a{q2 v})) 
    (requires (forall x. q1 x ==> q2 x))
    (ensures (fun r -> True)) =
  admit ();
  m

unfold
let pure_post_return (x:'a) : pure_post 'a = fun y -> x == y

unfold
let pure_post_bind (#a #b:Type) (q1:pure_post a) (q2:a -> pure_post b) : pure_post b =
  fun y -> exists (x:a{q1 x}). q2 x y

unfold
let pure_post_if_then_else (q1 q2:pure_post 'a) (b:bool) : pure_post 'a =
  fun x -> (b ==> q1 x) /\ ((~b) ==> q2 x)

/////////////////////////////////////////////////////////////////////////////////////

(** Later we refine the output type of the dijkstra monad with the pure post condition (q),
which forces us to index the dijkstra monad by a weakest-precondition of type `hist (v:a{q v})`.
For cleanliness reasons, we define a synonym for that called `histq`. **)

unfold
let histq #event a (q:pure_post a) = hist #event (v:a{q v})

unfold
let histq_ord
  (#q1:pure_post 'a) (#q2:pure_post 'a)
  (wp1: histq 'a q1) 
  (wp2: histq 'a q2) :
  Pure Type0
    (requires (forall x. q2 x ==> q1 x))
    (ensures (fun _ -> True)) =
  forall h (p:hist_post (v:'a{q1 v})). 
    wp1 p h ==> wp2 (fun lt (r:'a{q2 r}) -> p lt (r <: (x:'a{q1 x}))) h

unfold
let histq_return (x:'a) : histq 'a (pure_post_return x) =
  hist_return x

let lemma_histq_subcomp_post
  (a b:Type)
  (q1:pure_post a) (q2:a -> pure_post b)
  (wp:(x:a{q1 x}) -> histq b (q2 x)) 
  (x: a{q1 x})
  (p1 p2 : hist_post (v:b{pure_post_bind q1 q2 v}))
  (h:trace) :
  Lemma
    (requires (p1 `hist_post_ord` p2 /\ wp x (fun lt r -> p1 lt r) h))
    (ensures (wp x (fun lt r -> p2 lt r) h)) = ()

unfold
let histq_subcomp_bind
  (a b:Type)
  (q1:pure_post a) (q2:a -> pure_post b)
  (wp2:(x:a) -> histq b (q2 x)) 
  (x: a{q1 x}) :
  Tot (histq b (pure_post_bind q1 q2)) = 
  Classical.forall_intro_3 (Classical.move_requires_3 (lemma_histq_subcomp_post a b q1 q2 wp2 x));
  fun p -> wp2 x (fun lt (r: b{q2 x r}) -> p lt r)

unfold
let histq_if_then_else (q1 q2:pure_post 'a) (wp1:histq 'a q1) (wp2:histq 'a q2) (b:bool) : histq 'a (pure_post_if_then_else q1 q2 b) by (
  explode ()
)=
  admit ();
  (** TODO: show that histq_if_then_else is monotonic **)
  fun (p:trace -> (x:'a{pure_post_if_then_else q1 q2 b x}) -> Type0) h -> (b ==> wp1 p h) /\ ((~b) ==> wp2 p h)

unfold
let histq_for_pure (#a:Type) q : histq a q = fun p h -> forall (r:a{q r}). p [] r

let dm_subcomp_histq (a:Type) 
  (q1:pure_post a) (q2:pure_post a)
  (wp1: histq a q1) 
  (wp2: histq a q2)
  (f : dm (v:a{q1 v}) wp1) :
  Pure (dm (v:a{q2 v}) wp2)
    (requires ((forall x. q1 x ==> q2 x) /\ wp2 `histq_ord` wp1))
    (ensures fun _ -> True) =
  assert (wp1 `hist_ord` (theta f));
  assert (wp2 `histq_ord` wp1);

  let m = io_subcomp a q1 q2 f in
  assert (wp2 `hist_ord` (theta m));
  m

/////////////////////////////////////////////////////////////////////////////

let dmq (a:Type) (q:pure_post a) (wp:histq a q) = 
  dm (v:a{q v}) wp 

let dmq_return (a:Type) (x:a) : dmq a (pure_post_return x) (histq_return x) = 
  dm_return _ x

let dmq_bind (a b:Type)
  (q1:pure_post a) (q2:a -> pure_post b)
  (wp1:histq a q1) (wp2:(x:a) -> histq b (q2 x))
  (f:dmq a q1 wp1) 
  (g:(x:a{q1 x}) -> dmq b (q2 x) (wp2 x)) :
  Tot (dmq b (pure_post_bind q1 q2) (hist_bind wp1 (histq_subcomp_bind a b q1 q2 wp2))) =
    dm_bind 
      (v:a{q1 v})
      (v:b{pure_post_bind q1 q2 v})
      wp1
      (histq_subcomp_bind a b q1 q2 wp2)
      f
      (fun (x:a{q1 x}) -> 
        dm_subcomp_histq b
         (q2 x) (pure_post_bind q1 q2)
         (wp2 x)
         (histq_subcomp_bind a b q1 q2 wp2 x)
         (g x))

let dmq_subcomp (a:Type) (q1 q2:pure_post a) (wp1:hist (v:a{q1 v})) (wp2:hist (v:a{q2 v})) (f:dmq a q1 wp1) :
  Pure (dmq a q2 wp2)
    (requires (
      (forall x. q1 x ==> q2 x) /\
      (wp2 `histq_ord` wp1)))
    (ensures fun _ -> True) =
  dm_subcomp_histq a q1 q2 wp1 wp2 f

///////////////////////////////////////////////////////////////////////////

unfold
let pure_pre_bind (#a:Type) (p1:pure_pre) (q1:pure_post a) (p2:a -> pure_pre) : pure_pre =
  p1 /\ (forall x. q1 x ==> p2 x)

let pdmq (a:Type) (p:pure_pre) (q:pure_post a) (wp:histq a q) = 
  squash p -> dmq a q wp 

let pdmq_return (a:Type) (x:a) : pdmq a True (pure_post_return x) (histq_return x) = 
  fun _ -> dmq_return _ x

let pdmq_bind (a b:Type)
  (p1:pure_pre) (p2:a -> pure_pre)
  (q1:pure_post a) (q2:a -> pure_post b)
  (wp1:histq a q1) (wp2:(x:a) -> histq b (q2 x))
  (f:pdmq a p1 q1 wp1) 
  (g:(x:a) -> pdmq b (p2 x) (q2 x) (wp2 x)) :
  Tot (pdmq b (pure_pre_bind p1 q1 p2) (pure_post_bind q1 q2) (hist_bind wp1 (histq_subcomp_bind a b q1 q2 wp2))) =
  fun (pre:squash (pure_pre_bind p1 q1 p2)) ->
  dmq_bind a b q1 q2 wp1 wp2 (f pre) (fun (x:a{q1 x}) -> g x pre)

let pdmq_subcomp (a:Type) (p1 p2:pure_pre) (q1 q2:pure_post a) (wp1:hist (v:a{q1 v})) (wp2:hist (v:a{q2 v})) (f:pdmq a p1 q1 wp1) :
  Pure (pdmq a p2 q2 wp2)
    (requires (
      (p2 ==> p1) /\
      (forall x. q1 x ==> q2 x) /\
      (wp2 `histq_ord` wp1)))
    (ensures fun _ -> True) =
  fun _ -> dmq_subcomp a q1 q2 wp1 wp2 (f ())
  
unfold
let pdmq_if_then_else 
  (a : Type)
  (p1 p2: pure_pre)
  (q1 q2: pure_post a)
  (wp1: histq a q1)
  (wp2: histq a q2)
  (f : pdmq a p1 q1 wp1)
  (g : pdmq a p2 q2 wp2)
  (b : bool) : Type =
  pdmq a
    ((b ==> p1) /\ ((~b) ==> p2)) 
    (pure_post_if_then_else q1 q2 b)
    (histq_if_then_else q1 q2 wp1 wp2 b)

total
reifiable
reflectable
effect {
  IOwp (a:Type) (p : pure_pre) (q : pure_post a) (wp : histq #event a q)
  with {
       repr       = pdmq
     ; return     = pdmq_return
     ; bind       = pdmq_bind 
     ; subcomp    = pdmq_subcomp
     ; if_then_else = pdmq_if_then_else
     }
}

effect IO
  (a:Type)
  (pre : trace -> Type0)
  (post : trace -> trace -> a -> Type0) =
  IOwp a 
    True
    (fun _ -> True)
    (fun (p:hist_post a) (h:trace) -> pre h /\ (forall lt r. post h lt r ==>  p lt r)) 


unfold let as_requires (#a: Type) (wp: pure_wp a) = wp (fun x -> True)
unfold let as_ensures (#a: Type) (wp: pure_wp a) (x: a) = ~(wp (fun y -> (y =!= x)))

(** histq_for_pure is labeled with unfold, but when trying to prove the lift,
the unfolding confuses
the SMT. Therefore, the following is just a trick to get an automated proof of the lift **)
let histq_for_pure0 = histq_for_pure
let lift_pure_pdmq0 (a : Type) (w : pure_wp a) (f:(eqtype_as_type unit -> PURE a w)) : 
  pdmq a (as_requires w) (as_ensures w) (histq_for_pure0 (as_ensures w)) =
  fun (pre:squash (as_requires w)) ->
    FStar.Monotonic.Pure.elim_pure_wp_monotonicity_forall ();
    let r = f () in
    let r' = dmq_return _ r in
    dmq_subcomp _ _ _ _ _ r'

let lift_pure_pdmq (a : Type) (w : pure_wp a) (f:(eqtype_as_type unit -> PURE a w)) : 
  pdmq a (as_requires w) (as_ensures w) (histq_for_pure (as_ensures w)) =
    lift_pure_pdmq0 a w f

sub_effect PURE ~> IOwp = lift_pure_pdmq
  
assume val p : prop
assume val p' : prop
assume val pure_lemma (_:unit) : Lemma p
assume val some_f (_:squash p) : IO unit (fun _ -> True) (fun _ _ _ -> True)
assume val some_f' : unit -> IO unit (requires (fun _ -> p)) (ensures fun _ _ _ -> p')

let test () : IO unit (fun _ -> True) (fun _ _ _ -> True) =
  pure_lemma ();
  some_f ()

(** The prop p' in the wp of some_f' can not be checked by the assert **)
let test'' () : IO unit (fun _ -> True) (fun _ _ _ -> True) =
  pure_lemma ();
  some_f ();
  some_f' ();
  assert p'

let static_cmd
  (cmd : io_cmds)
  (argz : io_args cmd) :
  IO (io_resm cmd)
    (requires (fun h -> io_pre cmd argz h))
    (ensures (fun h lt r ->
        lt == [convert_call_to_event cmd argz r])) =
  IOwp?.reflect (fun _ -> io_call cmd argz)

let testStatic3 (fd:file_descr) : IO unit (fun h -> is_open fd h) (fun h lt r -> ~(is_open fd (List.rev lt @ h))) =
  let _ = static_cmd Close fd in
  ()

let testStatic2 () : IO unit (fun _ -> True) (fun _ _ _ -> True) =
  let fd = static_cmd Openfile "../Makefile" in
  if Some? fd then begin (** test if Openfile was successful **)
    let msg = static_cmd Read (Some?.v fd) in
    let _ = static_cmd Close (Some?.v fd) in
    ()
  end else ()
