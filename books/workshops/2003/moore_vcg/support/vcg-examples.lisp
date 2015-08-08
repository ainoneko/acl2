; Use of Tail-Recursion to Propagate Inductive Assertions
; J Strother Moore
; February 26, 2003

; cd /u/moore/m5/tolquhon
; (include-book "utilities")
; (ld "vcg-examples.lisp" :ld-pre-eval-print t)

; Certification:
; (include-book "utilities")
; (certify-book "vcg-examples" 1)

; ---------------------------------------------------------------------------
; Preliminaries

; This first part is just ``prelude''.  It has nothing to do with the
; specific programs we will verify.

(in-package "M5")

(include-book "../../../../misc/defpun")

(defmacro defpun (g args &rest tail)
  `(acl2::defpun ,g ,args ,@tail))

;(ACL2::SET-MATCH-FREE-ERROR NIL)

(defthm update-nth-opener
  (and (equal (update-nth 0 x a) (cons x (cdr a)))
       (implies (not (zp n))
                (equal (update-nth n x a)
                       (cons (car a) (update-nth (- n 1) x (cdr a)))))))

; ---------------------------------------------------------------------------
; Some Preliminaries for Our First Program

(defthm int-evenp-inv-a
  (implies (intp i)
           (iff (evenp (int-fix (- i 2)))
                (evenp i)))
  :hints
  (("Goal" :in-theory (e/d (intp int-fix)
                           (floor)))))

(defthm int-evenp-inv-b
  (implies (intp i)
           (iff (evenp (- i 2))
                (evenp i)))
  :hints
  (("Goal" :in-theory (e/d (intp int-fix)
                           (floor)))))

(in-theory (disable evenp))

(defthm int-lemma2a
  (implies (and (intp x)
                (<= 0 x))
           (equal (int-fix (+ -2 x))
                  (+ -2 x)))
  :hints (("Goal" :in-theory (e/d (intp) nil))))

(defthm int-lemma2b
  (implies (and (intp x)
                (<= 0 x))
           (intp (+ -2 x)))
  :hints (("Goal" :in-theory (e/d (intp) nil))))

; ---------------------------------------------------------------------------
; Our First Program

; Below is an m5 program that decrements its first local, n, by 2 and
; iterates until the result is 0.  On each iteration it adds 1 to a
; local variable, a, which is initialized to 0.  The program ends with
; a HALT instruction, which puts the machine in an infinite loop, i.e.,
; executing HALT doesn't change the pc and the machine "stops."  Later
; we deal with the more realistic situation of a RETURN to some caller.
; We will prove that if the program below reaches the HALT instruction,
; the initial value, n0, of n was even and the result on the stack is
; n0/2.  This program does not terminate when n0 is odd.

; To make the program slightly simpler to deal with, I only consider
; the case where n0 is a non-negative int.  (Java programmers will note
; that the program actually halts for even negative ints, because of
; wrap-around.)

(defconst *flat-prog*
  '((iconst_0)      ; 0
    (istore_1)      ; 1               a := 0;
    (iload_0)       ; 2  top of loop:
    (ifeq 14)       ; 3               if n=0, goto 17;
    (iload_1)       ; 6
    (iconst_1)      ; 7
    (iadd)          ; 8
    (istore_1)      ; 9               a := a+1;
    (iload_0)       ;10
    (iconst_2)      ;11
    (isub)          ;12
    (istore_0)      ;13               n := n-2;
    (goto -12)      ;14               goto top of loop
    (iload_1)       ;17
    (halt)))        ;18

; Here is the ``semantics'' of the loop, in the case in interest.

(defun halfa (n a)
  (declare (xargs :measure (nfix n)))
  (if (zp n)
      a
    (halfa (- n 2) (int-fix (+ a 1)))))

; ---------------------------------------------------------------------------
; The Assertions at the Three Cut Points

; We will use a classic ``inductive assertion'' method.  The following
; function takes a state, s, and the ``initial'' value of n, n0, and
; states the assertions we wish to attach to pcs 0, 2, and 18.  These
; are the so-called ``cut points'' of my choice: the entry to the
; program, the top of the loop, and exit from the program.

; The particular assertions are not my main interest in this paper.
; You can read them if you want.  The real nugget in this paper is not
; the assertions but the fact that I use tail recursion by step to
; propagate assertions from the cut points to all the pcs.

; That said, let me note that the assertions are complicated because
; they have to handle the fact that halfa tracks the program only as
; long as n stays non-negative.  Things would be simpler if I assumed
; that n0 was even.  But I like illustrating the capability of
; establishing conditions that hold for n0 in the event of
; termination.

(defun flat-pre-condition (n0 n)
  (and (equal n n0)
       (intp n0)
       (<= 0 n0)))

(defun flat-loop-invariant (n0 n a)
  (and (intp n0)
       (<= 0 n0)
       (intp n)
       (if (and (<= 0 n)
                (evenp n))
           (equal (halfa n a)
                  (halfa n0 0))
         (not (evenp n)))
       (iff (evenp n0) (evenp n))))

(defun flat-post-condition (n0 value)
  (and (evenp n0)
       (equal value (halfa n0 0))))

(defun flat-assertion (n0 th s)
  (let ((n (nth 0 (locals (top-frame th s))))
        (a (nth 1 (locals (top-frame th s)))))
    (and (equal (program (top-frame th s)) *flat-prog*)
         (case (pc (top-frame th s))
           (0 (flat-pre-condition n0 n))
           (2 (flat-loop-invariant n0 n a))
           (18 (let ((value (top (stack (top-frame th s)))))
                 (flat-post-condition n0 value)))
           (otherwise nil)))))

; Observe that the output condition is that n0 is even and that the
; top of the stack contains the semantic expression (halfa n0 0).
; We will later convert this to n0/2.

; ---------------------------------------------------------------------------
; The Invariant -- The Only New Idea in this Note

; Here is the new idea.  I define the invariant for the program by
; using defpun.  The assertions are attached at the three cut points
; and all other statements inherit the invariant of the next
; statement.

(defpun flat-inv (n0 th s)
  (if (or (equal (pc (top-frame th s)) 0)
          (equal (pc (top-frame th s)) 2)
          (equal (pc (top-frame th s)) 18))
      (flat-assertion n0 th s)
    (flat-inv n0 th (step th s))))

; In one sense, the next lemma is just a technical lemma to force
; flat-inv to keep opening if it hasn't reached a cut point yet.  But
; in another sense, this lemma highlights the nice feature of this
; approach.  Suppose that in our function flat-assertion we had failed
; to supply a cut point for some loop.  Then we'll get a stack
; overflow from the repeated indefinite application of this rewrite
; rule.  But we do not have to prove we've cut every loop, because the
; flat-inv function is tail recursive and so was admitted by defpun.

; In the past when I've used the classic inductive invariant approach
; and used recursion in flat-inv to avoid an assertion at every pc, I
; had to invent some kind of measure (``distance to the next cut
; point'') to prove that I had cut every loop.  That annoyed me
; because in the classic inductive invariant approach that burden is
; merely pragmatic -- you had to cut every loop or you couldn't
; generate verification conditions.  But you didn't have to prove you
; had cut every loop.  In my past attempts to mimic this, I had to
; prove more stuff!

(defthm flat-inv-opener
  (implies (and (equal pc (pc (top-frame th s)))
                (syntaxp (quotep pc))
                (not (equal pc 0))
                (not (equal pc 2))
                (not (equal pc 18)))
           (equal (flat-inv n0 th s)
                  (flat-inv n0 th (step th s)))))

; ---------------------------------------------------------------------------
; The Verification Conditions

(defthm VC1
  (implies (flat-pre-condition n0 n) (flat-loop-invariant n0 n 0)))


(defthm VC2
  (implies (and (flat-loop-invariant n0 n a)
                (not (equal n 0)))
           (flat-loop-invariant n0 (int-fix (- n 2)) (int-fix (+ 1 a)))))

(defthm VC3
  (implies (and (flat-loop-invariant N0 n a)
                (EQUAL n 0))
           (flat-post-condition N0 a)))

(in-theory (disable flat-pre-condition
                    flat-loop-invariant
                    flat-post-condition))

; ---------------------------------------------------------------------------
; Using the VCs in the Operational Semantics

; So here is the key theorem of the inductive invariant approach, showing
; that inv is an invariant.

(defthm flat-inv-step
  (implies (flat-inv n0 th s)
           (flat-inv n0 th (step th s))))

; We can immediately conclude that flat-inv is an invariant under run,
; as long as the only thread we step is th.

(defun mono-threadedp (th sched)
  (if (endp sched)
      t
    (and (equal th (car sched))
         (mono-threadedp th (cdr sched)))))

(defthm flat-inv-run
  (implies (and (mono-threadedp th sched)
                (flat-inv n0 th s))
           (flat-inv n0 th (run sched s)))
  :rule-classes nil
  :hints (("Goal" :in-theory (e/d (run)(flat-inv-def)))))

; And so we're done.  If we plug in an initial state satisfying the
; invariant we get a final state satisfying it.  If the final state is
; supposed to have pc 18, then we can read out what the invariant
; tells us about that cut point.

(defthm flat-main
  (let ((s1 (run sched s0)))
    (implies (and (intp n0)
                  (<= 0 n0)
                  (equal (pc (top-frame th s0)) 0)
                  (equal (locals (top-frame th s0)) (list n0 any))
                  (equal (program (top-frame th s0)) *flat-prog*)
                  (mono-threadedp th sched)
                  (equal (pc (top-frame th s1)) 18))
             (and (evenp n0)
                  (equal (top (stack (top-frame th s1)))
                         (halfa n0 0)))))

  :hints (("Goal" :use
           (:instance flat-inv-run
                      (n0 n0)
                      (s s0)
                      (th th)
                      (sched sched))
           :in-theory (enable flat-pre-condition flat-post-condition)))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; Getting Rid of the Semantic Function

; Now, following our standard paradigm, we get rid of halfa and
; introduce n/2 instead.  There is nothing new here, but I have to
; fight intp and int-fix.

(defthm int-back
  (implies (and (intp (+ a x))
                (integerp a)
                (<= 0 a)
                (integerp x)
                (<= 0 x)
                (integerp y)
                (<= 0 y)
                (<= y x))
           (intp (+ y a)))
  :hints (("Goal" :in-theory (enable intp))))

(defthm halfa-is-half
  (implies (and (intp n)
                (<= 0 n)
                (evenp n)
                (integerp a)
                (<= 0 a)
                (intp (+ (/ n 2) a)))
           (equal (halfa n a)
                  (+ (/ n 2) a)))
  :hints (("Goal" :in-theory (enable evenp))))

(defthm intp-half-n
  (implies (and (intp n)
                (<= 0 n)
                (evenp n))
           (intp (* 1/2 n)))
  :hints (("Goal" :in-theory (enable evenp intp))))

; ---------------------------------------------------------------------------
; The (Partial) Correctness Theorem for Half

; The following theorem summarizes what we now know.  Start with a a
; state running *flat-prog* from pc 0 with initial n=n0 and run it
; under an arbitrary mono-threaded schedule to get to s1.  Suppose n0
; is a non-negative int and the pc of s1 is 18.

; Then we conclude that n0 is even and that the top of the stack is
; n0/2.

(defthm flat-is-partially-correct
  (let ((s1 (run sched s0)))
    (implies (and (intp n0)
                  (<= 0 n0)
                  (equal (pc (top-frame th s0)) 0)
                  (equal (locals (top-frame th s0)) (list n0 any))
                  (equal (program (top-frame th s0)) *flat-prog*)
                  (mono-threadedp th sched)
                  (equal (pc (top-frame th s1)) 18))
             (and (evenp n0)
                  (equal (top (stack (top-frame th s1)))
                         (/ n0 2)))))
  :rule-classes nil
  :hints (("Goal"
           :use ((:instance flat-main)))))

; Note that at no point in this exercise have we counted instructions
; or defined a clock or schedule generator.

; ---------------------------------------------------------------------------
; Dealing with Return

(defconst *half-prog*
  '((iconst_0)      ; 0
    (istore_1)      ; 1               a := 0;
    (iload_0)       ; 2  top of loop:
    (ifeq 14)       ; 3               if n=0, goto 17;
    (iload_1)       ; 6
    (iconst_1)      ; 7
    (iadd)          ; 8
    (istore_1)      ; 9               a := a+1;
    (iload_0)       ;10
    (iconst_2)      ;11
    (isub)          ;12
    (istore_0)      ;13               n := n-2;
    (goto -12)      ;14               goto top of loop
    (iload_1)       ;17
    (ireturn)))     ;18               return a;

(defun sdepth (stk)
  (declare (xargs :hints (("Goal" :in-theory (enable pop)))))
  (if (endp stk)
      0
    (+ 1 (sdepth (pop stk)))))

(defun half-assertion (n0 d0 th s)
  (cond
   ((< (sdepth (call-stack th s)) d0)
    (let ((value (top (stack (top-frame th s)))))
      (flat-post-condition n0 value)))
   (t
    (let ((n (nth 0 (locals (top-frame th s))))
          (a (nth 1 (locals (top-frame th s)))))
      (and (equal (sdepth (call-stack th s)) d0)
           (equal (program (top-frame th s)) *half-prog*)
           (equal (sync-flg (top-frame th s)) 'UNLOCKED)
           (case (pc (top-frame th s))
             (0 (flat-pre-condition n0 n))
             (2 (flat-loop-invariant n0 n a))
             (18 (let ((value (top (stack (top-frame th s)))))
                   (flat-post-condition n0 value)))
             (otherwise nil)))))))

(defpun half-inv (n0 d0 th s)
  (if (or (< (sdepth (call-stack th s)) d0)
          (equal (pc (top-frame th s)) 0)
          (equal (pc (top-frame th s)) 2)
          (equal (pc (top-frame th s)) 18))
      (half-assertion n0 d0 th s)
    (half-inv n0 d0 th (step th s))))

(defthm half-inv-opener
  (implies (and (equal pc (pc (top-frame th s)))
                (syntaxp (quotep pc))
                (not (equal pc 0))
                (not (equal pc 2))
                (not (equal pc 18)))
           (equal (half-inv n0 d0 th s)
                  (if (< (sdepth (call-stack th s)) d0)
                      (half-assertion n0 d0 th s)
                    (half-inv n0 d0 th (step th s))))))

(defthm half-inv-step
  (implies (and (integerp d0)
                (< 1 d0)
                (<= d0 (sdepth (call-stack th s)))
                (half-inv n0 d0 th s))
           (half-inv n0 d0 th (step th s)))
  :hints (("Goal" :in-theory (disable halfa-is-half))))

(defun run-to-return (sched th d0 s)
  (cond ((endp sched) s)
        ((<= d0 (sdepth (call-stack th s)))
         (run-to-return (cdr sched) th d0 (step (car sched) s)))
        (t s)))

(defthm half-inv-run-to-return
  (implies (and (mono-threadedp th sched)
                (integerp d0)
                (< 1 d0)
                (half-inv n0 d0 th s))
           (half-inv n0 d0 th (run-to-return sched th d0 s)))
  :rule-classes nil
  :hints (("Goal" :in-theory (disable half-inv-def))))

; And so we're done.  If we plug in an initial state satisfying the
; invariant we get a final state satisfying it.  If the final state is
; supposed to have pc 18, then we can read out what the invariant
; tells us about that cut point.

(defthm half-main
  (let ((s1 (run-to-return sched th (sdepth (call-stack th s0)) s0)))
    (implies (and (intp n0)
                  (<= 0 n0)
                  (equal (pc (top-frame th s0)) 0)
                  (equal (locals (top-frame th s0)) (list n0 any))
                  (equal (program (top-frame th s0)) *half-prog*)
                  (equal (sync-flg (top-frame th s0)) 'unlocked)
                  (< 1 (sdepth (call-stack th s0)))
                  (mono-threadedp th sched)
                  (< (sdepth (call-stack th s1))
                     (sdepth (call-stack th s0))))
             (and (evenp n0)
                  (equal (top (stack (top-frame th s1)))
                         (halfa n0 0)))))
  :hints (("Goal" :use
           (:instance half-inv-run-to-return
                      (n0 n0)
                      (d0 (sdepth (call-stack th s0)))
                      (s s0)
                      (th th)
                      (sched sched))
           :in-theory (enable flat-pre-condition
                              flat-post-condition)))
  :rule-classes nil)

(defthm half-partially-correct
  (let ((s1 (run-to-return sched th (sdepth (call-stack th s0)) s0)))
    (implies (and (intp n0)
                  (<= 0 n0)
                  (equal (pc (top-frame th s0)) 0)
                  (equal (locals (top-frame th s0)) (list n0 any))
                  (equal (program (top-frame th s0)) *half-prog*)
                  (equal (sync-flg (top-frame th s0)) 'unlocked)
                  (< 1 (sdepth (call-stack th s0)))
                  (mono-threadedp th sched)
                  (< (sdepth (call-stack th s1))
                     (sdepth (call-stack th s0))))
             (and (evenp n0)
                  (equal (top (stack (top-frame th s1)))
                         (/ n0 2)))))
  :hints (("Goal" :use half-main))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; Doing a Sum Program

; To re-illustrate the same methodology, without worrying about
; demonstrating that we can conclude things about the input if we're
; told we terminate, here is a program that sums the ints from n0 down
; to 0.

(defconst *sum-prog*
                    ; We name local[0] n and local[1] a.
  '((iconst_0)      ; 0
    (istore_1)      ; 1               a := 0;
    (iload_0)       ; 2  top of loop:
    (ifeq 14)       ; 3               if n=0, goto 17;
    (iload_0)       ; 6
    (iload_1)       ; 7
    (iadd)          ; 8
    (istore_1)      ; 9               a := n+a;
    (iload_0)       ;10
    (iconst_m1)     ;11
    (iadd)          ;12
    (istore_0)      ;13               n := n-1;
    (goto -12)      ;14               goto top of loop
    (iload_1)       ;17
    (ireturn)))     ;18               return a;

(defun suma (n a)
  (if (zp n)
      a
    (suma (- n 1) (int-fix (+ n a)))))

(defun sum-pre-condition (n0 n)
  (and (equal n n0)
       (intp n0)
       (<= 0 n0)))

(defun sum-loop-invariant (n0 n a)
  (and (intp n0)
       (intp n)
       (<= 0 n)
       (<= n n0)
       (equal (suma n a)
              (suma n0 0))))

(defun sum-post-condition (n0 value)
  (equal value (suma n0 0)))

(defun sum-assertion (n0 d0 th s)
  (cond ((< (sdepth (call-stack th s)) d0)
         (let ((value (top (stack (top-frame th s)))))
           (sum-post-condition n0 value)))
        (t
         (let ((n (nth 0 (locals (top-frame th s))))
               (a (nth 1 (locals (top-frame th s)))))
           (and (equal (sdepth (call-stack th s)) d0)
                (equal (program (top-frame th s)) *sum-prog*)
                (equal (sync-flg (top-frame th s)) 'UNLOCKED)
                (case (pc (top-frame th s))
                  (0 (sum-pre-condition n0 n))
                  (2 (sum-loop-invariant n0 n a))
                  (18 (let ((value (top (stack (top-frame th s)))))
                        (sum-post-condition n0 value)))
                  (otherwise nil)))))))

(defpun sum-inv (n0 d0 th s)
  (if (or (< (sdepth (call-stack th s)) d0)
          (equal (pc (top-frame th s)) 0)
          (equal (pc (top-frame th s)) 2)
          (equal (pc (top-frame th s)) 18))
      (sum-assertion n0 d0 th s)
    (sum-inv n0 d0 th (step th s))))

(defthm sum-inv-opener
  (implies (and (equal pc (pc (top-frame th s)))
                (syntaxp (quotep pc))
                (not (equal pc 0))
                (not (equal pc 2))
                (not (equal pc 18)))
           (equal (sum-inv n0 d0 th s)
                  (if (< (sdepth (call-stack th s)) d0)
                      (sum-assertion n0 d0 th s)
                    (sum-inv n0 d0 th (step th s))))))

(defthm sum-VC1
  (implies (sum-pre-condition n0 n) (sum-loop-invariant n0 n 0)))

(defthm sum-VC2
  (implies (and (sum-loop-invariant n0 n a)
                (not (equal n 0)))
           (sum-loop-invariant n0 (int-fix (- n 1)) (int-fix (+ n a)))))

(defthm sum-VC3
  (implies (and (sum-loop-invariant N0 n a)
                (EQUAL n 0))
           (sum-post-condition N0 a)))

(in-theory (disable sum-pre-condition
                    sum-loop-invariant
                    sum-post-condition))

(defthm sum-inv-step
  (implies (and (integerp d0)
                (< 1 d0)
                (<= d0 (sdepth (call-stack th s)))
                (sum-inv  n0 d0 th s))
           (sum-inv n0 d0 th (step th s))))

(defthm sum-inv-run-to-return
  (implies (and (mono-threadedp th sched)
                (integerp d0)
                (< 1 d0)
                (sum-inv n0 d0 th s))
           (sum-inv n0 d0 th (run-to-return sched th d0 s)))
  :rule-classes nil
  :hints (("Goal" :in-theory (disable sum-inv-def))))

(defthm sum-main
  (let ((s1 (run-to-return sched th (sdepth (call-stack th s0)) s0)))
    (implies (and (intp n0)
                  (<= 0 n0)
                  (equal (pc (top-frame th s0)) 0)
                  (equal (locals (top-frame th s0)) (list n0 any))
                  (equal (program (top-frame th s0)) *sum-prog*)
                  (equal (sync-flg (top-frame th s0)) 'unlocked)
                  (< 1 (sdepth (call-stack th s0)))
                  (mono-threadedp th sched)
                  (< (sdepth (call-stack th s1))
                     (sdepth (call-stack th s0))))
             (equal (top (stack (top-frame th s1)))
                    (suma n0 0))))
  :hints (("Goal" :use
           (:instance sum-inv-run-to-return
                      (n0 n0)
                      (d0 (sdepth (call-stack th s0)))
                      (s s0)
                      (th th)
                      (sched sched))
           :in-theory (enable sum-pre-condition
                              sum-post-condition)))
  :rule-classes nil)

; We don't bother to eliminate suma, though we could if we hacked around
; with intp long enough!

; ---------------------------------------------------------------------------
; A Recursive Method

; Now let's do recursive factorial.   We'll bring in the clocked work
; we have already done, just to have the *demo-state* etc.

(include-book "demo")

(defun ! (n)
  (if (zp n)
      1
    (* n (! (- n 1)))))

; Here is the (redundant) definition of the program.

(defconst *fact-def*
  '("fact" (INT) NIL
    (ILOAD_0)                         ;;;  0
    (IFLE 12)                         ;;;  1
    (ILOAD_0)                         ;;;  4
    (ILOAD_0)                         ;;;  5
    (ICONST_1)                        ;;;  6
    (ISUB)                            ;;;  7
    (INVOKESTATIC "Demo" "fact" 1)    ;;;  8
    (IMUL)                            ;;; 11
    (IRETURN)                         ;;; 12
    (ICONST_1)                        ;;; 13
    (IRETURN)))                       ;;; 14

; The following function recognizes the call stack (cs) of a call of
; the "fact" method on n0.  The function is not applied to the
; top-most frame, because the constraints on the frame are so
; pc-sensitive and the top-most frame may have "any" pc.  So the
; function actually recognizes the rest of the "fact" call stack.
; Here is a picture of the entire call stack.

; -------------------   top-most frame
; pc:       any
; locals:   (n)          5  <- suppose n=5
; stack:    any
; program:  fact prog
; -------------------   caller-frame
; pc:       11
; locals:   (n+1)        6     this is caller-frame 3
; stack:    (n+1)
; program:  fact prog
; -------------------   caller-frame
; pc:       11
; locals:   (n+2)        7     this is caller-frame 2
; stack:    (n+2)
; program:  fact prog
; -------------------   caller-frame
; ...
; -------------------   caller-frame
; pc:       11
; locals:   (n0)         8  <- suppose n0 = 8 ; this is caller frame 1
; stack:    (n0)
; program:  fact prog
; -------------------   the frame below called fact on n0
; ...                   this is caller frame 0

; Note that there are n0-n fact caller frames.  We number them from
; n0-n down to 1.  Caller frame 0 is actually the ``external'' entry
; into fact on n0.  We don't know (or care) whether fact or some other
; program is running there.  Let k be the number of the caller frame.
; Then note that the value of n in that frame is n0-k+1.

(defun fact-caller-framesp (cs n0 k)
  (declare (xargs :measure (acl2-count k)))
  (cond ((zp k) t)
        ((and (equal (pc (top cs)) 11)
              (equal (program (top cs)) (cdddr *fact-def*))
              (equal (sync-flg (top cs)) 'UNLOCKED)
              (intp (nth 0 (locals (top cs))))
              (equal (+ n0 (- k)) (- (nth 0 (locals (top cs))) 1))
              (equal (nth 0 (locals (top cs)))
                     (top (stack (top cs)))))
         (fact-caller-framesp (pop cs) n0 (- k 1)))
        (t nil)))

(defun fact-assertion (n0 d0 th s)
  (cond
   ((< (sdepth (call-stack th s)) d0)
    (equal (top (stack (top-frame th s)))
           (int-fix (! n0))))
   (t
    (let ((n (nth 0 (locals (top-frame th s)))))
      (and (equal (program (top-frame th s)) (cdddr *fact-def*))
           (equal (lookup-method "fact" "Demo" (class-table s))
                  *fact-def*)
           (equal (sync-flg (top-frame th s)) 'UNLOCKED)
           (intp n0)
           (intp n)
           (<= 0 n)
           (<= n n0)
           (equal (sdepth (call-stack th s)) (+ d0 (- n0 n)))
           (fact-caller-framesp (pop (call-stack th s)) n0 (- n0 n))
           (case (pc (top-frame th s))
             (0 t)
             ((12 14) (equal (top (stack (top-frame th s)))
                             (int-fix (! n))))
             (otherwise nil)))))))

(defpun fact-inv (n0 d0 th s)
  (if (or (< (sdepth (call-stack th s)) d0)
          (equal (pc (top-frame th s)) 0)
          (equal (pc (top-frame th s)) 12)
          (equal (pc (top-frame th s)) 14))
      (fact-assertion n0 d0 th s)
    (fact-inv n0 d0 th (step th s))))

(defthm fact-inv-opener
  (implies (and (equal pc (pc (top-frame th s)))
                (syntaxp (quotep pc))
                (not (equal pc 0))
                (not (equal pc 12))
                (not (equal pc 14)))
           (equal (fact-inv n0 d0 th s)
                  (if (< (sdepth (call-stack th s)) d0)
                      (fact-assertion n0 d0 th s)
                    (fact-inv n0 d0 th (step th s))))))

; These next three lemmas are technical.  The first two force
; substitutions.  The last opens the stack predicate when we're
; returning and need to know what we're being told about the caller.

(DEFTHM KB-HACK1
  (IMPLIES
   (AND
    (FACT-CALLER-FRAMESP
     (POP (POP (CADR (ASSOC-EQUAL TH (THREAD-TABLE S)))))
     N0
     (+ -1 N0 (- NNN)))
    (EQUAL
     NNN
     (+ -1
        (CAR (LOCALS (TOP (POP (CADR (ASSOC-EQUAL TH (THREAD-TABLE S))))))))))
   (FACT-CALLER-FRAMESP
    (POP (POP (CADR (ASSOC-EQUAL TH (THREAD-TABLE S)))))
    N0
    (+
     N0
     (-
      (CAR (LOCALS (TOP (POP (CADR (ASSOC-EQUAL TH (THREAD-TABLE S))))))))))))

(defthm kb-hack2
  (implies
   (and (integerp n)
        (EQUAL
         tos
         (INT-FIX
          (! (CAR (LOCALS (TOP (CADR (ASSOC-EQUAL TH (THREAD-TABLE S))))))))))

   (EQUAL
    (INT-FIX (* tos n))
    (INT-FIX
     (* (! (CAR (LOCALS (TOP (CADR (ASSOC-EQUAL TH (THREAD-TABLE S)))))))
        n)))))

(defthm fact-caller-framesp-opener-1
  (implies (and (syntaxp
                 (equal cs
                        '(POP (CAR (CDR (ASSOC-EQUAL TH (THREAD-TABLE S)))))))
                (EQUAL (PC (TOP (CADR (ASSOC-EQUAL TH (THREAD-TABLE S))))) pc0)
                (syntaxp (or (equal pc0 ''12) (equal pc0 ''14))))
           (equal (fact-caller-framesp cs n0 k)
                  (COND ((ZP K) T)
                        ((AND (EQUAL (PC (TOP CS)) 11)
                              (EQUAL (PROGRAM (TOP CS))
                                     (CDDDR *FACT-DEF*))
                              (EQUAL (SYNC-FLG (TOP CS)) 'UNLOCKED)
                              (INTP (NTH 0 (LOCALS (TOP CS))))
                              (EQUAL (+ N0 (- K))
                                     (- (NTH 0 (LOCALS (TOP CS))) 1))
                              (EQUAL (NTH 0 (LOCALS (TOP CS)))
                                     (TOP (STACK (TOP CS)))))
                         (FACT-CALLER-FRAMESP (POP CS)
                                              N0 (- K 1)))
                        (T NIL)))))

(defthm fact-inv-step
  (implies (and (integerp d0)
                (< 1 d0)
                (<= d0 (sdepth (call-stack th s)))
                (fact-inv n0 d0 th s))
           (fact-inv n0 d0 th (step th s))))

(defthm fact-inv-run-to-return
  (implies (and (mono-threadedp th sched)
                (integerp d0)
                (< 1 d0)
                (fact-inv n0 d0 th s))
           (fact-inv n0 d0 th (run-to-return sched th d0 s)))
  :rule-classes nil
  :hints (("Goal" :in-theory (disable fact-inv-def))))

; Here is the main theorem.  It opens by letting s1 be a run-to-return
; of s0.  That particular call runs s0 with an abitrarily long
; schedule, sched.  Note that run-to-return does not always return a
; state that has returned to a shorter call-stack depth -- if the
; schedule is exhausted before that happens, the final state may still
; be as deep or deeper than the initial state.  In any case, s0 is the
; initial state and s1 is the final state.

; Now let's read the hypotheses of the implication.  There are five
; blocks of hypotheses.  The first says that n0 is a positive intp.
; The second says that the top-frame of thread th of s0 is a call of
; our "fact" method on n0.  The third says that the depth of the
; call-stack of thread th is greater than 1.  That means there is a
; frame under the call of "fact".  We will call that frame the
; ``caller's frame.''  Of course, if s1 has a shorter call-stack than
; s0, then the caller's frame will be its top-frame, since
; run-to-return stops as soon as we've returned to that depth.  The
; fourth says the schedule consists of nothing but th steps.  Note
; that otherwise we say nothing about the schedule -- it may be
; arbitrarily long.  The fifth block says that the depth of the call
; stack of s1 is less than that of s0, so we know the initial state
; did run long enough to return and hence, the caller's frame is the
; top-frame of s1.

; Then the conclusion is that (int-fix (! n0)) is on top of
; the stack of the caller's frame.

(defthm fact-main
  (let ((s1 (run-to-return sched th (sdepth (call-stack th s0)) s0)))
    (implies (and (intp n0)
                  (<= 0 n0)

                  (equal (pc (top-frame th s0)) 0)
                  (equal (locals (top-frame th s0)) (list n0))
                  (equal (program (top-frame th s0))
                         (cdddr *fact-def*))
                  (equal (sync-flg (top-frame th s0)) 'unlocked)
                  (equal (lookup-method "fact" "Demo" (class-table s0))
                         *fact-def*)

                  (< 1 (sdepth (call-stack th s0)))

                  (mono-threadedp th sched)

                  (< (sdepth (call-stack th s1))
                     (sdepth (call-stack th s0))))
             (equal (top (stack (top-frame th s1)))
                    (int-fix (! n0)))))

  :hints (("Goal"
           :use
           (:instance fact-inv-run-to-return
                      (n0 n0)
                      (d0 (sdepth (call-stack th s0)))
                      (s s0)
                      (th th)
                      (sched sched))))
  :rule-classes nil)

; ---------------------------------------------------------------------------
; The Basic Relation Between Run-to-Return and Run

(defun sched-to-return (sched th d0 s)
  (cond ((endp sched) sched)
        ((<= d0 (sdepth (call-stack th s)))
         (sched-to-return (cdr sched) th d0 (step (car sched) s)))
        (t sched)))

(defthm run-to-return-v-run
  (equal (run sched s)
         (run (sched-to-return sched th d0 s)
              (run-to-return sched th d0 s)))
  :rule-classes nil)

; I need to develop the compositional rules.
