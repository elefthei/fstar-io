(* Another idea:
  Could we have some type
  guarded A := { P : Prop & P → A }
  and then build D normally, and use D (guarded A) (gᵂ w) as PD?
  This is a whole different approach, going inside the monad instead of
  wrapping into a precondition.
*)

From Coq Require Import Utf8 RelationClasses.

Set Default Goal Selector "!".
Set Printing Projections.

Ltac forward_gen H tac :=
  match type of H with
  | ?X → _ => let H' := fresh in assert (H':X) ; [tac|specialize (H H'); clear H']
  end.

Tactic Notation "forward" constr(H) := forward_gen H ltac:(idtac).
Tactic Notation "forward" constr(H) "by" tactic(tac) := forward_gen H tac.

Notation val x := (let 'exist _ t _ := x in t).
Notation "⟨ u ⟩" := (exist _ u _).

Notation "'∑' x .. y , p" := (sigT (fun x => .. (sigT (fun y => p%type)) ..))
  (at level 200, x binder, right associativity,
   format "'[' '∑'  '/  ' x  ..  y ,  '/  ' p ']'")
  : type_scope.

Notation "( x ; y )" := (@existT _ _ x y).
Notation "( x ; y ; z )" := (x ; ( y ; z)).
Notation "( x ; y ; z ; t )" := (x ; ( y ; (z ; t))).
Notation "( x ; y ; z ; t ; u )" := (x ; ( y ; (z ; (t ; u)))).
Notation "( x ; y ; z ; t ; u ; v )" := (x ; ( y ; (z ; (t ; (u ; v))))).
Notation "x .π1" := (@projT1 _ _ x) (at level 3, format "x '.π1'").
Notation "x .π2" := (@projT2 _ _ x) (at level 3, format "x '.π2'").

Section State.

  Context (state : Type).

  (* Computation monad *)

  Inductive M A :=
  | retᴹ (x : A)
  | act_getᴹ (k : state → M A)
  | act_putᴹ (s : state) (k : M A).

  Arguments retᴹ [_].
  Arguments act_getᴹ [_].
  Arguments act_putᴹ [_].

  Fixpoint bindᴹ [A B] (c : M A) (f : A → M B) : M B :=
    match c with
    | retᴹ x => f x
    | act_getᴹ k => act_getᴹ (λ s, bindᴹ (k s) f)
    | act_putᴹ s k => act_putᴹ s (bindᴹ k f)
    end.

  Definition getᴹ : M state :=
    act_getᴹ (λ x, retᴹ x).

  Definition putᴹ (s : state) : M unit :=
    act_putᴹ s (retᴹ tt).

  (* Specification monad *)

  Definition preᵂ := state → Prop.
  Definition postᵂ A := state → A → Prop.

  Definition W A := postᵂ A → preᵂ.

  Definition wle [A] (w₀ w₁ : W A) : Prop :=
    ∀ P s, w₁ P s → w₀ P s.

  Notation "x ≤ᵂ y" := (wle x y) (at level 80).

  Definition retᵂ [A] (x : A) : W A :=
    λ P s₀, P s₀ x.

  Definition bindᵂ [A B] (w : W A) (wf : A → W B) : W B :=
    λ P, w (λ s₁ x, wf x P s₁).

  Definition getᵂ : W state :=
    λ P s, P s s.

  Definition putᵂ (s : state) : W unit :=
    λ P s₀, P s tt.

  Instance trans [A] : Transitive (@wle A).
  Proof.
    intros x y z h₁ h₂. intros P s₀ h.
    apply h₁. apply h₂.
    assumption.
  Qed.

  (* Monotonicity *)

  Class Monotonous [A] (w : W A) :=
    ismono : ∀ (P Q : postᵂ A) s₀, (∀ s₁ x, P s₁ x → Q s₁ x) → w P s₀ → w Q s₀.

  Instance retᵂ_ismono [A] (x : A) : Monotonous (retᵂ x).
  Proof.
    intros P Q s₀ hPQ h.
    apply hPQ. apply h.
  Qed.

  Instance bindᵂ_ismono [A B] (w : W A) (wf : A → W B) :
    Monotonous w →
    (∀ x, Monotonous (wf x)) →
    Monotonous (bindᵂ w wf).
  Proof.
    intros mw mwf.
    intros P Q s₀ hPQ h.
    eapply mw. 2: exact h.
    simpl. intros s₁ x hf.
    eapply mwf. 2: exact hf.
    assumption.
  Qed.

  Instance getᵂ_ismono : Monotonous (getᵂ).
  Proof.
    intros P Q s₀ hPQ h.
    red. red in h.
    apply hPQ. assumption.
  Qed.

  Instance putᵂ_ismono : ∀ s, Monotonous (putᵂ s).
  Proof.
    intros s. intros P Q s₀ hPQ h.
    apply hPQ. assumption.
  Qed.

  Lemma bindᵂ_mono :
    ∀ [A B] (w w' : W A) (wf wf' : A → W B),
      Monotonous w' →
      w ≤ᵂ w' →
      (∀ x, wf x ≤ᵂ wf' x) →
      bindᵂ w wf ≤ᵂ bindᵂ w' wf'.
  Proof.
    intros A B w w' wf wf' mw' hw hwf.
    intros P s₀ h.
    red. red in h.
    apply hw. eapply mw'. 2: exact h.
    simpl. intros s₁ x hf. apply hwf. assumption.
  Qed.

  (* Effect observation (in two passes) *)

  Fixpoint θ₀ [A] (c : M A) (s₀ : state) : state * A :=
    match c with
    | retᴹ x => (s₀, x)
    | act_getᴹ k => θ₀ (k s₀) s₀
    | act_putᴹ s k => θ₀ k s
    end.

  Definition θ [A] (c : M A) : W A :=
    λ P s₀, let '(s₁, x) := θ₀ c s₀ in P s₁ x.

  Lemma θ_ret :
    ∀ A (x : A),
      θ (retᴹ x) ≤ᵂ retᵂ x.
  Proof.
    intros A x. intros P s₀ h.
    cbn. red in h. assumption.
  Qed.

  Lemma θ_bind :
    ∀ A B c f,
      θ (@bindᴹ A B c f) ≤ᵂ bindᵂ (θ c) (λ x, θ (f x)).
  Proof.
    intros A B c f.
    induction c as [| ? ih | ?? ih] in B, f |- *.
    - cbn. intros P s₀ h.
      assumption.
    - cbn. intros P s₀ h.
      apply ih. assumption.
    - cbn. intros P s₀ h.
      apply ih. assumption.
  Qed.

  (* Dijkstra monad *)

  Definition D A w :=
    { c : M A | θ c ≤ᵂ w }.

  Definition retᴰ [A] (x : A) : D A (retᵂ x).
  Proof.
    exists (retᴹ x).
    apply θ_ret.
  Defined.

  Definition bindᴰ [A B w wf] (c : D A w) (f : ∀ x, D B (wf x))
    `{Monotonous _ w} :
    D B (bindᵂ w wf).
  Proof.
    exists (bindᴹ (val c) (λ x, val (f x))).
    etransitivity. 1: apply θ_bind.
    apply bindᵂ_mono.
    - assumption.
    - destruct c. simpl. assumption.
    - intro x. destruct (f x). simpl. assumption.
  Qed.

  Definition subcompᴰ [A w w'] (c : D A w) {h : w ≤ᵂ w'} : D A w'.
  Proof.
    exists (val c).
    etransitivity. 2: exact h.
    destruct c. assumption.
  Defined.

  Definition getᴰ : D state getᵂ.
  Proof.
    exists getᴹ.
    cbv. auto.
  Defined.

  Definition putᴰ s : D unit (putᵂ s).
  Proof.
    exists (putᴹ s).
    cbv. auto.
  Defined.

  (* Partial Dijkstra monad *)

  Definition guarded A :=
    ∑ (P : Prop), P → A.

  (* TODO Figure out if it's the right spec *)
  Definition guardedᵂ [A] (w : W A) : W (guarded A) :=
    λ P s₀, w (λ s₁ x, P s₁ (True ; λ _, x)) s₀.

  Instance guardedᵂ_ismono [A] (w : W A) {mw : Monotonous w} :
    Monotonous (guardedᵂ w).
  Proof.
    intros P Q s₀ hPQ h.
    unfold guardedᵂ in *.
    eapply mw. 2: exact h.
    intuition eauto.
  Qed.

  Definition P A w :=
    D (guarded A) (guardedᵂ w).

  Definition retᴾ [A] (x : A) : P A (retᵂ x).
  Proof.
    refine (subcompᴰ (retᴰ (True ; λ _, x))).
    intros post s₀ h. assumption.
  Defined.

  Fixpoint mapᴹ [A B] (f : A → B) (c : M A) : M B :=
    match c with
    | retᴹ x => retᴹ (f x)
    | act_getᴹ k => act_getᴹ (λ s, mapᴹ f (k s))
    | act_putᴹ s k => act_putᴹ s (mapᴹ f k)
    end.

  Definition mapᴰ [A B w] (f : A → B) (c : D A w) :
    D B (λ post s₀, w (λ s₁ x, post s₁ (f x)) s₀).
  Proof.
    exists (mapᴹ f (val c)).
    destruct c as [c hc].
    induction c as [| ? ih | ?? ih] in B, w, f, hc |- *.
    - simpl. etransitivity. 1: eapply θ_ret.
      intros post s₀ h.
      apply hc in h. assumption.
    - simpl. intros post s₀ h.
      unfold θ. simpl. eapply ih. 2: eapply h.
      unfold θ in hc. simpl in hc.
      intros ? ? h'. admit.
      (* Maybe should prove laws for get and put after all *)
    - admit.
  Admitted.

  Definition getᴾ : P state getᵂ.
  Proof.
    refine (subcompᴰ (mapᴰ (λ x, (True ; λ _, x)) getᴰ)).
    intros post s₀ h. apply h.
  Defined.

  Definition putᴾ (s : state) : P unit (putᵂ s).
  Proof.
    refine (subcompᴰ (mapᴰ (λ x, (True ; λ _, x)) (putᴰ s))).
    intros post s₀ h. apply h.
  Defined.

  (* Could also use it in retᴾ for instance *)
  Definition retᵍ [A] (x : A) : guarded A :=
    (True ; λ _, x).

  Definition bindᵍ [A B] (x : guarded A) (f : A → guarded B) : guarded B.
  Proof.
    exists (∃ (h : x.π1), (f (x.π2 h)).π1).
    simple refine (λ h, (f (x.π2 _)).π2 _).
    - destruct h. assumption.
    - destruct h as [h hf]. assumption.
  Defined.

  Definition bindᴾ [A B w wf] (c : P A w) (f : ∀ x, P B (wf x)) :
    Monotonous w →
    P B (bindᵂ w wf).
  Proof.
    intros mw.
    unfold P in *.
    (* refine (subcompᴰ (bindᴰ c (λ x, mapᴰ (bindᵍ x) _))). *)
    refine (subcompᴰ (bindᴰ c (λ x, _))).
    1:{
      unshelve apply f.
      (* Here I wanted to reinforce the pre of f somehow to be able to use
        x but maybe there is no way? Can we use bindᵍ in any way?
        With mapᴹ (bindᵍ x)?
      *)
      give_up.
    }
  Abort.

End State.