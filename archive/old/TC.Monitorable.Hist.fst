module TC.Monitorable.Hist

open FStar.Tactics
open FStar.Tactics.Typeclasses

open IO.Sig 

type monitorable_prop = (cmd:io_cmds) -> (io_sig.args cmd) -> (history:trace) -> Tot bool

unfold
let has_event_respected_pi (e:event) (check:monitorable_prop) (h:trace) : bool =
  match e with
  | EOpenfile arg _ -> check Openfile arg h
  | ERead arg _ -> check Read arg h
  | EClose arg _ -> check Close arg h

let rec enforced_locally
  (check : monitorable_prop)
  (h l: trace) :
  Tot bool (decreases l) =
  match l with
  | [] -> true
  | e  ::  t ->
    if has_event_respected_pi e check h then enforced_locally (check) (e::h) t
    else false
  
let pi_as_hist (#a:Type) (pi:monitorable_prop) : hist a =
  (fun p h -> forall r lt. enforced_locally pi h lt ==> p lt r)

let lemma_bind_pi_implies_pi (#a #b:Type) (pi:monitorable_prop) : 
  Lemma (pi_as_hist #b pi `hist_ord` (hist_bind (pi_as_hist #a pi) (fun (_:a) -> pi_as_hist pi))) = admit ()

class monitorable_hist
  (#t1:Type)
  (#t2:Type) 
  (pre : t1 -> trace -> Type0)
  (post : t1 -> trace -> resexn t2 -> trace -> Type0)
  (pi : monitorable_prop) = {
    post_implies_pi : squash (forall x h lt r. pre x h /\ post x h r lt ==> enforced_locally pi h lt);
}

class checkable_hist_post
  (#t1:Type)
  (#t2:Type) 
  (pre : t1 -> trace -> Type0)
  (post : t1 -> trace -> resexn t2 -> trace -> Type0)
  (pi : monitorable_prop) = {
    (** the refinement makes sure that the post can not reject the halting of the execution by the insturmentation **)
    result_check : t1 -> trace -> r:resexn t2 -> trace -> (b:bool{r == Inr Contract_failure ==> b});
    (** we want to make sure that result_check does not check any trace property, only properties related between
        the result and the trace **)
    (** this condition makes sure that all trace properties enforced by post are instrumented by pi **)
    c1post : squash (forall x h lt. pre x h /\ enforced_locally pi h lt ==> (exists r. post x h r lt));
    (** this one makes sure that the post at the end is enough **)
    c2post: squash (forall x h r lt. pre x h /\ enforced_locally pi h lt /\ result_check x h r lt ==> post x h r lt);
}
