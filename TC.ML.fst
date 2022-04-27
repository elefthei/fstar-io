module TC.ML

open FStar.Tactics
open FStar.Tactics.Typeclasses

open Common

(** ** First order **)

(** Principles for mlfo (ML First Order):
1. they work only with basic types (no functions).
2. We need to be really careful with what we say it is `mlfo` since
   the typeclass is not closed 
Arrows are not mlfo, because in F* they have an associated effect,
concept that does not exists in ML. **)

class mlfo (t:Type) = { mlfodummy : unit }

// Basic MIO types
instance mlfo_unit : mlfo unit = { mlfodummy = () }
instance mlfo_bool : mlfo bool = { mlfodummy = () }
instance mlfo_int : mlfo int = { mlfodummy = () }
instance mlfo_uint8 : mlfo UInt8.t = { mlfodummy = () }
instance mlfo_string : mlfo string = { mlfodummy = () }
instance mlfo_bytes : mlfo Bytes.bytes = { mlfodummy = () }
instance mlfo_open_flag : mlfo open_flag = { mlfodummy = () } 
instance mlfo_socket_bool_option : mlfo socket_bool_option = { mlfodummy = () }
instance mlfo_file_descr : mlfo file_descr = { mlfodummy = () }
instance mlfo_zfile_perm : mlfo zfile_perm = { mlfodummy = () }
instance mlfo_pair t1 t2 {| mlfo t1 |} {| mlfo t2 |} : mlfo (t1 * t2) = { mlfodummy = () }
instance mlfo_pair_2 t1 t2 t3 {| mlfo t1 |} {| mlfo t2 |} {| mlfo t3 |} : mlfo (t1 * t2 * t3) = { mlfodummy = () }
instance mlfo_pair_3 t1 t2 t3 t4 {| mlfo t1 |} {| mlfo t2 |} {| mlfo t3 |} {| mlfo t4 |} : mlfo (t1 * t2 * t3 * t4) = { mlfodummy = () }
instance mlfo_option t1 {| mlfo t1 |} : mlfo (option t1) = { mlfodummy = () }
instance mlfo_maybe t1 {| mlfo t1 |} : mlfo (maybe t1) = { mlfodummy = () }
instance mlfo_list t1 {| mlfo t1 |} : mlfo (list t1) = { mlfodummy = () }

(** ** Arrows **)

class ml_arrow (t:Type) = { mldummy : unit }
(** since all arrows in F* are effectful, we can not define instances here because 
we do not have the effect yet **)

(** ** Instrumented **)

class ml_instrumented (t:Type) = { mlinstdummy : unit }

(** ** Compilation (?) **)
class mlifyable (t : Type) =
  { matype : Type; 
    cmatype : ml_arrow matype;
    mlify : t -> matype }

let mk_mlifyable
  (#t1:Type)
  (t2:Type) {| ml_arrow t2 |} 
  (exp : t1 -> t2) : 
  mlifyable t1 =
  { matype = t2; 
    mlify = exp;
    cmatype = solve }

(** ** Instrumentation **)
class instrumentable (t:Type) = { 
  inst_type : Type;
  cinst_type : ml_instrumented inst_type;
  (** be careful to not use reify while writing strengthen **)
  strengthen : inst_type -> t
} 


(** ** ML Target language **)
noeq
type ml (t:Type) =
| ML_FO : mlfo t -> ml t
| ML_ARROW : ml_arrow t -> ml t
| ML_INST : ml_instrumented t -> ml t
