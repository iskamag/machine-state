(in-package #:org.shirakumo.machine-state)

(cffi:define-foreign-library psapi
  (:windows "Psapi.dll"))

(cffi:define-foreign-library ntdll
  (:windows "Ntdll.dll"))

(cffi:use-foreign-library psapi)
(cffi:use-foreign-library ntdll)

(defmacro windows-call (function &rest args)
  `(unless (cffi:foreign-funcall ,function ,@args)
     (fail (org.shirakumo.com-on:error-message))))

(cffi:defcstruct (io-counters :conc-name io-counters-)
  (reads :ullong)
  (writes :ullong)
  (others :ullong)
  (read-bytes :ullong)
  (write-bytes :ullong)
  (other-bytes :ullong))

(define-implementation process-io-bytes ()
  (cffi:with-foreign-object (io-counters '(:struct io-counters))
    (windows-call "GetProcessIoCounters"
                  :pointer (cffi:foreign-funcall "GetCurrentProcess" :pointer)
                  :pointer io-counters
                  :bool)
    (+ (io-counters-read-bytes io-counters)
       (io-counters-write-bytes io-counters)
       (io-counters-other-bytes io-counters))))

(cffi:defcstruct (memory-counters :conc-name memory-counters-)
  (cb :uint32)
  (page-fault-count :uint32)
  (peak-working-set-size :size)
  (working-set-size :size)
  (quota-peak-paged-pool-usage :size)
  (quota-paged-pool-usage :size)
  (quota-peak-non-paged-pool-usage :size)
  (quota-non-paged-pool-usage :size)
  (pagefile-usage :size)
  (peak-page-file-usage :size))

(define-implementation process-room ()
  (cffi:with-foreign-objects ((memory-counters '(:struct memory-counters)))
    (windows-call "GetProcessMemoryInfo"
                  :pointer (cffi:foreign-funcall "GetCurrentProcess" :pointer)
                  :pointer memory-counters
                  :bool)
    (memory-counters-working-set-size memory-counters)))

(define-implementation process-time ()
  (cffi:with-foreign-objects ((creation-time :uint64)
                              (exit-time :uint64)
                              (kernel-time :uint64)
                              (user-time :uint64))
    (windows-call "GetProcessTimes"
                  :pointer (cffi:foreign-funcall "GetCurrentProcess" :pointer)
                  :pointer creation-time
                  :pointer exit-time
                  :pointer kernel-time
                  :pointer user-time
                  :bool)
    (* (float (cffi:mem-ref user-time :uint64) 0d0)
       10d-9)))

(cffi:defcstruct (memory-status :conc-name memory-status-)
  (length :uint32)
  (memory-load :uint32)
  (total-physical :uint64)
  (available-physical :uint64)
  (total-page-file :uint64)
  (available-page-file :uint64)
  (total-virtual :uint64)
  (available-virtual :uint64)
  (available-extended-virtual :uint64))

(define-implementation machine-room ()
  (cffi:with-foreign-objects ((memory-status '(:struct memory-status)))
    (let ((available (memory-status-available-physical memory-status))
          (total (memory-status-total-physical memory-status)))
      (values (- total available)
              total))))

(cffi:defcstruct (system-info :conc-name system-info-)
  (oem-id :uint32)
  (page-size :uint32)
  (minimum-application-address :pointer)
  (maximum-application-address :pointer)
  (active-processor-mask :uint64)
  (number-of-processors :uint32)
  (processor-type :uint32)
  (allocation-granularity :uint32)
  (processor-level :uint16)
  (processor-revision :uint16))

(define-implementation machine-cores ()
  (cffi:with-foreign-objects ((system-info '(:struct system-info)))
    (windows-call "GetSystemInfo"
                  :pointer system-info
                  :bool)
    (system-info-number-of-processors system-info)))

(defmacro with-thread-handle ((handle thread &optional (default 0)) &body body)
  `(if (or (eql ,thread T)
           (eql ,thread (bt:current-thread)))
       (let ((,handle (cffi:foreign-funcall "GetCurrentThread" :pointer)))
         ,@body)
       ,default))

(define-implementation thread-time (thread)
  (with-thread-handle (handle thread)
    (cffi:with-foreign-objects ((creation-time :uint64)
                                (exit-time :uint64)
                                (kernel-time :uint64)
                                (user-time :uint64))
      (windows-call "GetThreadTimes"
                    :pointer handle
                    :pointer creation-time
                    :pointer exit-time
                    :pointer kernel-time
                    :pointer user-time
                    :bool)
      (* (float (cffi:mem-ref user-time :uint64) 0d0)
         10d-9))))

(cffi:defcstruct (thread-info :conc-name thread-info-)
  (exit-status :uint32)
  (base-address :pointer)
  (process :pointer)
  (thread :pointer)
  (affinity-mask :uint64)
  (priority :long)
  (base-priority :long))

(define-implementation thread-core-mask (thread)
  (with-thread-handle (handle thread (1- (ash 1 (machine-cores))))
    (cffi:with-foreign-objects ((info '(:struct thread-info)))
      (cffi:foreign-funcall "NtQueryInformationThread"
                            :pointer handle
                            :int #x04
                            :pointer info
                            :ulong (cffi:foreign-type-size '(:struct thread-info))
                            :uint32)
      (thread-info-affinity-mask info))))

(define-implementation (setf thread-core-mask) (mask thread)
  (with-thread-handle (handle thread (1- (ash 1 (machine-cores))))
    (if (= 0 (cffi:foreign-funcall "SetThreadAffinityMask"
                                   :pointer handle
                                   :uint64 mask
                                   :uint64))
        (fail (org.shirakumo.com-on:error-message))
        mask)))
