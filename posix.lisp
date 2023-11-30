(in-package #:org.shirakumo.machine-state)

(cffi:defcvar (errno "errno") :int64)

(defmacro posix-call (function &rest args)
  `(let ((val (cffi:foreign-funcall ,function ,@args)))
     (if (= -1 val)
         (fail (cffi:foreign-funcall "strerror" :int64 errno))
         val)))

(cffi:defcstruct (timeval :conc-name timeval-)
  (sec :uint64)
  (usec :uint64))

(cffi:defcstruct (rusage :conc-name rusage-)
  (utime (:struct timeval))
  (stime (:struct timeval))
  ;; Linux fields
  (maxrss :long)
  (ixrss :long)
  (idrss :long)
  (isrss :long)
  (minflt :long)
  (majflt :long)
  (nswap :long)
  (inblock :long)
  (oublock :long)
  (msgsnd :long)
  (msgrcv :long)
  (nsignals :long)
  (nvcsw :long)
  (nivcsw :long))

(define-implementation process-room ()
  (cffi:with-foreign-object (rusage '(:struct rusage))
    (posix-call "getrusage" :int 0 :pointer rusage :int)
    (* 1024 (+ (rusage-ixrss rusage)
               (rusage-xdrss rusage)
               (rusage-isrss rusage)))))

(define-implementation process-time ()
  (cffi:with-foreign-object (rusage '(:struct rusage))
    (posix-call "getrusage" :int 0 :pointer rusage :int)
    (+ (timeval-sec rusage)
       (* (timeval-usec rusage) 10d-7))))

(cffi:defcstruct (sysinfo :conc-name sysinfo-)
  (uptime :long)
  (loads :ulong :count 3)
  (total-ram :ulong)
  (free-ram :ulong)
  (shared-ram :ulong)
  (buffer-ram :ulong)
  (total-swap :ulong)
  (free-swap :ulong)
  (processes :ushort)
  (total-high :ulong)
  (free-high :ulong)
  (memory-unit :uint)
  (_pad :char :count 22))

(define-implementation machine-room ()
  (cffi:with-foreign-objects ((sysinfo '(:struct sysinfo)))
    (posix-call "sysinfo" :pointer sysinfo :int)
    (let ((total (sysinfo-total-ram sysinfo))
          (free (sysinfo-free-ram sysinfo)))
      (values (- total free) total))))

(define-implementation machine-cores ()
  ;; _SC_NPROCESSORS_ONLN 84
  (posix-call "sysconf" :int 84 :long))

(defmacro with-thread-handle ((handle thread &optional (default 0)) &body body)
  `(if (or (eql ,thread T)
           (eql ,thread (bt:current-thread)))
       (let ((,handle (cffi:foreign-funcall "pthread_self" :pointer)))
         ,@body)
       ,default))

(define-implementation thread-time (thread)
  (with-thread-handle (handle thread 0d0)
    (cffi:with-foreign-object (rusage '(:struct rusage))
      (posix-call "getrusage" :int 1 :pointer rusage :int)
      (+ (timeval-sec rusage)
         (* (timeval-usec rusage) 10d-7)))))

(define-implementation thread-core-mask (thread)
  (with-thread-handle (handle thread (1- (ash 1 (machine-cores))))
    (cffi:with-foreign-objects ((cpuset :uint64))
      (unless (= 0 (cffi:foreign-funcall "pthread_getaffinity_np" :pointer handle :size (cffi:foreign-type-size :uint64) :pointer cpuset :int))
        (fail (cffi:foreign-funcall "strerror" :int64 errno)))
      (cffi:mem-ref cpuset :uint64))))

(define-implementation (setf thread-core-mask) (mask thread)
  (with-thread-handle (handle thread (1- (ash 1 (machine-cores))))
    (cffi:with-foreign-objects ((cpuset :uint64))
      (setf (cffi:mem-ref cpuset :uint64) mask)
      (unless (= 0 (cffi:foreign-funcall "pthread_setaffinity_np" :pointer handle :size (cffi:foreign-type-size :uint64) :pointer cpuset :int))
        (fail (cffi:foreign-funcall "strerror" :int64 errno)))
      (cffi:mem-ref cpuset :uint64))))
