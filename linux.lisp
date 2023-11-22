(in-package #:org.shirakumo.machine-state)

(define-implementation process-io-bytes ()
  ;; KLUDGE: we do this in C to avoid the stream system overhead.
  (cffi:with-foreign-object (io :char 1024)
    (let ((file (cffi:foreign-funcall "fopen" :string "/proc/self/io" :string "rb" :pointer)))
      (when (cffi:null-pointer-p file)
        (fail (cffi:foreign-funcall "strerror" :int64 errno)))
      (cffi:foreign-funcall "fread" :pointer io :size 1 :size 1024 :pointer file :size)
      (cffi:foreign-funcall "fclose" :pointer file :void))
    (flet ((read-int (field)
             (let* ((start (cffi:foreign-funcall "strstr" :pointer io :string field :pointer))
                    (ptr (cffi:inc-pointer start (length field))))
               (cffi:foreign-funcall "atoi" :pointer ptr :int))))
      (+ (read-int "read_bytes: ")
         (read-int "write_bytes: ")))))

;;;; For whatever reason on Linux rusage is useless for this, so redefine it here.
(define-implementation process-room ()
  (cffi:with-foreign-object (io :char 2048)
    (let ((file (cffi:foreign-funcall "fopen" :string "/proc/self/smaps_rollup" :string "rb" :pointer)))
      (when (cffi:null-pointer-p file)
        (fail (cffi:foreign-funcall "strerror" :int64 errno)))
      (cffi:foreign-funcall "fread" :pointer io :size 1 :size 2048 :pointer file :size)
      (cffi:foreign-funcall "fclose" :pointer file :void))
    (flet ((read-int (field)
             (let* ((start (cffi:foreign-funcall "strstr" :pointer io :string field :pointer))
                    (ptr (cffi:inc-pointer start (length field))))
               (cffi:foreign-funcall "atoi" :pointer ptr :int))))
      (* 1024 (read-int "Rss: ")))))
