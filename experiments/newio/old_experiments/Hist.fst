module Hist

open FStar.Tactics
open FStar.List.Tot.Base

(** The postcondition for an io computation is defined over the
result (type: a) and local trace (type: list event).
The local trace represents the events that happend during the
computation. Local trace is in chronological order.

We also have the history (type: list event) that represents the
events that happend until the beginning of the io computation.
The history is in reverse chronological order.

At the end of an io computation, the local trace is
reversed and appended to the history. **)

let hist_post (#event) a = lt:list event -> r:a -> Type0
let hist_pre (#event) = h:list event -> Type0

private let hist0 (#event) a = hist_post #event a -> hist_pre #event

unfold
let hist_post_ord (p1 p2:hist_post 'a) = forall lt r. p1 lt r ==> p2 lt r

let hist_wp_monotonic (wp:hist0 'a) =
  forall p1 p2. (p1 `hist_post_ord` p2) ==> (forall h. wp p1 h ==> wp p2 h)

let hist #event a = wp:(hist0 #event a){hist_wp_monotonic wp}

let hist_return (x:'a) : hist 'a =
  fun p _ -> p [] x

unfold
let hist_post_shift (p:hist_post 'a) (lt:list 'event) : hist_post 'a =
  fun lt' r -> p (lt @ lt') r

unfold
let hist_post_bind
  (h:list 'event)
  (kw : 'a -> hist 'b)
  (p:hist_post 'b) :
  Tot (hist_post 'a) =
  fun lt r ->
    kw r (hist_post_shift p lt) (List.rev lt @ h)

unfold
let hist_bind (w : hist 'a) (kw : 'a -> hist 'b) : hist 'b =
  fun p h -> w (hist_post_bind h kw p) h

unfold
let wp_lift_pure_hist (w : pure_wp 'a) : hist 'a =
  FStar.Monotonic.Pure.elim_pure_wp_monotonicity_forall ();
  fun p _ -> w (p [])

let lemma_wp_lift_pure_hist_implies_as_requires #a #event w :
  Lemma (forall (p:hist_post #event a) h. wp_lift_pure_hist w p h ==> as_requires w) =
    assert (forall (p:hist_post #event a) x. p [] x ==> True) ;
    FStar.Monotonic.Pure.elim_pure_wp_monotonicity w ;
    assert (forall (p:hist_post #event a). w (fun x -> p [] x) ==> w (fun _ -> True))

unfold
val hist_ord (#event:Type) (#a : Type) : hist #event a -> hist #event a -> Type0
let hist_ord wp1 wp2 = forall h p. wp1 p h ==> wp2 p h

unfold
let hist_if_then_else (wp1 wp2:hist 'a) (b:bool) : hist 'a =
  fun p h -> (b ==> wp1 p h) /\ ((~b) ==> wp2 p h)
  
let lemma_hist_bind_associativity (w1:hist 'a) (w2:'a -> hist 'b) (w3: 'b -> hist 'c) :
  Lemma (
    hist_bind w1 (fun r1 -> hist_bind (w2 r1) w3) == hist_bind (hist_bind w1 w2) w3)
  by (l_to_r [`List.Tot.Properties.rev_append;`List.Tot.Properties.append_assoc]) =
  () 
