;; AUTHORS:
;; Robert Krug <rkrug@cs.utexas.edu>
;; Shilpi Goel <shigoel@cs.utexas.edu>

(in-package "X86ISA")

(include-book "x86-register-readers-and-writers" :ttags (:undef-flg))

;; ======================================================================

(defsection x86-physical-memory

  :parents (machine)

  :short "Physical memory read and write functions"

  :long "<p>Note that the top-level memory accessor function is @(see
  rm08) and updater function is @(see wm08).  Their 16, 32, and 64 bit
  counterparts are also available.  These functions behave differently
  depending upon the value of @('programmer-level-mode').</p>

<p>The functions defined here, like @(see rm-low-32) and @(see
wm-low-32), are low-level read and write functions that are used
<b>only</b> by the code for walking page tables.  We also prove some
RoW and WoW theorems about these functions.  We don't recommend using
these functions at the top-level.</p>"

  )

;; ======================================================================

(local (include-book "centaur/bitops/ihs-extensions" :dir :system))
(local (include-book "arithmetic-5/top" :dir :system))

(local (in-theory (disable logior-expt-to-plus-quotep)))

;; ======================================================================

(define physical-address-p (phy-addr)
  :parents (x86-physical-memory)
  :inline t
  :enabled t
  (mbe :logic (unsigned-byte-p #.*physical-address-size* phy-addr)
       :exec  (and (integerp phy-addr)
                   (<= 0 phy-addr)
                   (< phy-addr #.*mem-size-in-bytes*))))

(define physical-address-listp (lst)
  :parents (x86-physical-memory)
  :short "Recognizer of a list of physical addresses"
  :enabled t
  (if (equal lst nil)
      t
    (and (consp lst)
         (physical-address-p (car lst))
         (physical-address-listp (cdr lst)))))

(define create-physical-address-list (count addr)

  :guard (and (natp count)
              (physical-address-p addr)
              (physical-address-p (+ addr count)))
  :parents (x86-physical-memory)

  :long "<p>Given a physical address @('addr'),
  @('create-physical-address-list') creates a list of physical
  addresses where the first address is @('addr') and the last address
  is the last physical address in the range @('addr') to @('addr +
  count').</p>"
  :enabled t

  (if (or (zp count)
          (not (physical-address-p addr)))
      nil
    (cons addr (create-physical-address-list (1- count)
                                             (1+ addr))))
  ///

  (defthm physical-address-listp-create-physical-address-list
    (physical-address-listp
     (create-physical-address-list count addr))
    :rule-classes (:rewrite :type-prescription)))

;; ======================================================================

;; Memory read functions:

;; These functions are very similar to rvm32 and rvm64 --- they
;; differs in the guards and the number of return values.

(define rm-low-32
  ((addr :type (unsigned-byte #.*physical-address-size*))
   (x86))
  :guard (and (integerp addr)
              (<= 0 addr)
              (< (+ 3 addr) *mem-size-in-bytes*))
  :enabled t
  :inline t
  :parents (x86-physical-memory)

  (let ((addr (mbe :logic (ifix addr)
                   :exec addr)))

    (b* (((the (unsigned-byte 8) byte0) (memi addr x86))
         ((the (unsigned-byte 8) byte1) (memi (1+ addr) x86))
         ((the (unsigned-byte 16) word0)
          (logior (the (unsigned-byte 16)
                    (ash byte1 8)) byte0))
         ((the (unsigned-byte 8) byte2) (memi (+ 2 addr) x86))
         ((the (unsigned-byte 8) byte3) (memi (+ 3 addr) x86))
         ((the (unsigned-byte 16) word1)
          (the (unsigned-byte 16) (logior (the (unsigned-byte 16)
                                            (ash byte3 8))
                                          byte2)))
         ((the (unsigned-byte 32) dword) (logior (the (unsigned-byte 32)
                                                   (ash word1 16))
                                                 word0)))
        dword))


  ///

  (defthm-usb n32p-rm-low-32
    :hyp (x86p x86)
    :bound 32
    :concl (rm-low-32 addr x86)
    :hints (("Goal" :in-theory (e/d () (force (force)))))
    :gen-linear t
    :gen-type t))

(define rm-low-64
  ((addr :type (unsigned-byte #.*physical-address-size*))
   (x86))
  :enabled t
  :guard (and (integerp addr)
              (<= 0 addr)
              (< (+ 7 addr) *mem-size-in-bytes*))
  :guard-hints (("Goal" :in-theory (e/d () (force (force)))))
  :parents (x86-physical-memory)

  (let ((addr (mbe :logic (ifix addr)
                   :exec addr)))

    (b* (((the (unsigned-byte 32) dword0)
          (rm-low-32 addr x86))
         ((the (unsigned-byte 32) dword1)
          (rm-low-32 (+ 4 addr) x86))
         ((the (unsigned-byte 64) qword)
          (the (unsigned-byte 64) (logior
                                   (the (unsigned-byte 64)
                                     (ash dword1 32))
                                   dword0))))
        qword))

  ///

  (defthm-usb n64p-rm-low-64
    :hyp (x86p x86)
    :bound 64
    :concl (rm-low-64 addr x86)
    :hints (("Goal" :in-theory (e/d () (force (force)))))
    :gen-linear t
    :gen-type t)
  )

;; ======================================================================

;; Memory write functions:

;; These functions are very similar to wvm32 and wvm64 --- they
;; differs in the guards and the number of return values.

(local
 (in-theory (e/d () (ACL2::logand-constant-mask))))

(define wm-low-32
  ;; This function is very similar to wm-low-32 --- it differs in the
  ;; guards and the number of return values.
  ((addr :type (unsigned-byte #.*physical-address-size*))
   (val :type (unsigned-byte 32))
   (x86))
  :enabled t
  :inline t
  :guard (< (+ 3 addr) *mem-size-in-bytes*)
  :guard-hints (("Goal" :in-theory (e/d (logtail) ())))
  :parents (x86-physical-memory)

  (let ((addr (mbe :logic (ifix addr)
                   :exec addr)))

    (b* (((the (unsigned-byte 8) byte0)
          (mbe :logic (part-select val :low 0 :width 8)
               :exec  (logand #xff val)))
         ((the (unsigned-byte 8) byte1)
          (mbe :logic (part-select val :low 8 :width 8)
               :exec  (logand #xff (ash val -8))))
         ((the (unsigned-byte 8) byte2)
          (mbe :logic (part-select val :low 16 :width 8)
               :exec  (logand #xff (ash val -16))))
         ((the (unsigned-byte 8) byte3)
          (mbe :logic (part-select val :low 24 :width 8)
               :exec  (logand #xff (ash val -24))))
         (x86 (!memi addr  byte0 x86))
         (x86 (!memi (+ 1 addr) byte1 x86))
         (x86 (!memi (+ 2 addr) byte2 x86))
         (x86 (!memi (+ 3 addr) byte3 x86)))
        x86))

  ///

  (defthm x86p-wm-low-32
    (implies (and (x86p x86)
                  (integerp addr))
             (x86p (wm-low-32 addr val x86)))
    :rule-classes (:rewrite :type-prescription)))

(define wm-low-64
  ((addr :type (unsigned-byte #.*physical-address-size*))
   (val :type (unsigned-byte 64))
   (x86))
  :enabled t
  :guard (< (+ 7 addr) *mem-size-in-bytes*)
  :guard-hints (("Goal" :in-theory (e/d (logtail) ())))
  :parents (x86-physical-memory)

  (let ((addr (mbe :logic (ifix addr)
                   :exec addr)))

    (b* ((dword0 (mbe :logic (part-select val :low 0 :width 32)
                      :exec  (logand #xFFFFFFFF val)))
         (dword1 (mbe :logic (part-select val :low 32 :width 32)
                      :exec  (logand #xFFFFFFFF (ash val -32))))
         (x86 (wm-low-32 addr dword0 x86))
         (x86 (wm-low-32 (+ 4 addr) dword1 x86)))
        x86))
  ///
  (defthm x86p-wm-low-64
    (implies (and (x86p x86)
                  (integerp addr))
             (x86p (wm-low-64 addr val x86)))
    :rule-classes (:rewrite :type-prescription)))

;; ======================================================================

(globally-disable '(rm-low-32 rm-low-64 wm-low-32 wm-low-64))

;; ======================================================================
