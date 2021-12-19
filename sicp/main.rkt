#lang racket

(require racket/provide
         (prefix-in r5rs: r5rs)
         (only-in racket [random racket:random]
                           [collect-garbage racket:collect-garbage]))

(provide (filtered-out (λ (name) (regexp-replace #px"^r5rs:" name ""))
                       (except-out (all-from-out r5rs) r5rs:#%module-begin
                                   r5rs:eval r5rs:delay r5rs:force r5rs:set!
                                   ;r5rs:set-car! r5rs:set-cdr! r5rs:vector-set!
                                   ))
         (rename-out [module-begin #%module-begin]
                     [eval-in-underlying-scheme r5rs:eval]
                     [apply-in-underlying-scheme r5rs:apply]
                     [amb-set! set!]
                     [r5rs:set! permanent-set!]
                     ;[amb-vector-set! vector-set!]
                     [null? stream-null?]
                     [sqr square]
                     [add1 inc]
                     [sub1 dec]
                     [void quietly]))
;(provide set-car!)
;(provide set-cdr!)
;(provide define-namespace-anchor)
;(provide namespace-anchor->namespace)

(define-syntax (define+provide stx)
  (syntax-case stx ()
    [(_ (id . args) . body) #'(begin
                                (provide id)
                                (define (id . args) . body))]
    [(_ id expr) #'(begin
                     (provide id)
                     (define id expr))]))

;my additions that aren't technically part of the language spec
(define+provide ⟨??⟩ (void))
(define+provide (collect-garbage)
  (amb-clear)
  (racket:collect-garbage))

;(define+provide (eval exp . env)
;  (if (null? env)
;      (r5rs:eval exp (or (get 'meta 'namespace)
;                         (r5rs:interaction-environment)))
;      (r5rs:eval exp (car env))))
(define+provide (eval exp . env)
  (if (null? env)
      (r5rs:eval exp user-initial-environment)
      (r5rs:eval exp (car env))))
(define+provide eval-in-underlying-scheme eval)

;exception handling, so that errors won't automatically stop execution
(provide with-handlers)
(provide exn:fail?)
(provide exn-message)
(provide call/cc)
(provide true)
(provide false)
(provide error)
(provide identity)

(define+provide nil '())
(define+provide the-empty-stream '())
;(define+provide inc add1)
;(define+provide dec sub1)
(define+provide (runtime)
  (inexact->exact (truncate (* 1000 (current-inexact-milliseconds)))))
(define+provide (random n)
  (if (and (integer? n) (exact? n))
      (racket:random n)
      (* n (racket:random))))	
(provide cons-stream)
(define-syntax cons-stream
  (syntax-rules ()
    [(_ A B) (r5rs:cons A (delay B))]))
	
;the following are only necessary/available
;because I'm using the versions from racket instead of r5rs
;which I'm doing because I want access to (promise? exp) 
(provide delay)
(provide force)
(provide promise?)

(define (make-table)
  (let ((local-table (r5rs:list '*table*)))
    (define (lookup . args)
      (let iter ((keys args)
                 (table local-table))
        (if (null? keys)
            (r5rs:cdr table)
            (let ((subtable (r5rs:assoc (car keys) (r5rs:cdr table))))
              (and subtable
                   (iter (cdr keys) subtable))))))
    (define (insert! . args)
      (define (make-entry keys)
        (if (null? (cddr keys))
            (r5rs:cons (car keys)(cadr keys))
            (r5rs:list (car keys)(make-entry (cdr keys)))))
      (cadr args) ;will throw an exception if the list is too short
      (let iter ((keys args)
                 (table local-table))
        (if (null? (cdr keys))
            (r5rs:set-cdr! table (car keys))
            (let ((subtable (r5rs:assoc (car keys)(r5rs:cdr table))))
              (if subtable
                  (iter (cdr keys) subtable)
                  (r5rs:set-cdr! table (r5rs:cons (make-entry keys) 
                                                  (r5rs:cdr table)))))))
      'ok)
    (define (dispatch m)
      (cond ((eq? m 'lookup-proc) lookup)
            ((eq? m 'insert-proc!) insert!)
            (else (error "Unknown operation: TABLE" m))))
    dispatch))

(define operation-table (make-table))
(define+provide get (operation-table 'lookup-proc))
(define+provide put (operation-table 'insert-proc!))
(define coercion-table (make-table))
(define+provide get-coercion (coercion-table 'lookup-proc))
(define+provide put-coercion (coercion-table 'insert-proc!))

(define+provide apply-in-underlying-scheme r5rs:apply)
	
(provide amb)
(provide amb-collect)
(define+provide (try-again) (amb))
(define (base-amb-fail) (error "amb tree exhausted"))
(define amb-fail base-amb-fail)
(define (set-amb-fail! x) (set! amb-fail x))

(define-syntax-rule (explore +prev-amb-fail +sk alt)
  (call/cc
   (lambda (+fk)
     (set-amb-fail!
      (thunk
       (set-amb-fail! +prev-amb-fail)
       (+fk 'fail)))
     (+sk alt))))

(define-syntax-rule (amb alt ...)
  (let ([+prev-amb-fail amb-fail])
    (call/cc
     (lambda (+sk)
       (explore +prev-amb-fail +sk alt) ...
       (+prev-amb-fail)))))

(define-syntax-rule (amb-set! var expr)
  (let ([old-value var]
        [new-value expr]
        [+prev-amb-fail amb-fail])
    (or (eq? +prev-amb-fail base-amb-fail)
        ;we only want this to trigger if there's amb stuff going on,
        ;otherwise any call to set! would screw up garbage collection
        (set-amb-fail!
         (thunk
          (r5rs:set! var old-value)
          (+prev-amb-fail))))
    (r5rs:set! var new-value)))
(define-syntax-rule (set-car! pair expr)
  (let ([old-value (r5rs:car pair)]
        [new-value expr]
        [+prev-amb-fail amb-fail])
    (or (eq? +prev-amb-fail base-amb-fail)
        (set-amb-fail!
         (thunk
          (r5rs:set-car! pair old-value)
          (+prev-amb-fail))))
    (r5rs:set-car! pair new-value)))
(define-syntax-rule (set-cdr! pair expr)
  (let ([old-value (r5rs:cdr pair)]
        [new-value expr]
        [+prev-amb-fail amb-fail])
    (or (eq? +prev-amb-fail base-amb-fail)
        (set-amb-fail!
         (thunk
          (r5rs:set-cdr! pair old-value)
          (+prev-amb-fail))))
    (r5rs:set-cdr! pair new-value)))
(define-syntax-rule (amb-vector-set! vect k expr)
  (let ([old-value (vector-ref vect k)]
        [new-value expr]
        [+prev-amb-fail amb-fail])
    (or (eq? +prev-amb-fail base-amb-fail)
        (set-amb-fail!
         (thunk
          (vector-set! vect k old-value)
          (+prev-amb-fail))))
    (vector-set! vect k new-value)))
(define-syntax-rule (amb-collect proc)
  (let ((pairs nil))
    (with-handlers ((exn:fail? (lambda (exn)
                                 (r5rs:reverse pairs))))
      (r5rs:set! pairs (r5rs:cons proc pairs))
      (amb))))

(define+provide (amb-clear)
  (set-amb-fail! base-amb-fail))

(provide if-fail)
(define-syntax-rule (if-fail expr catch)
  (with-handlers ((exn:fail?
                   (lambda (exn)
                     catch)))
    expr))

(define+provide user-initial-environment #f)
(define+provide (set-user-initial-environment! namespace)
  (set! user-initial-environment namespace))
(define-syntax module-begin
  (syntax-rules ()
    ((_ . forms)
     (#%printing-module-begin
      (module configure-runtime '#%kernel
        ;(print-boolean-long-form #t)
        (print-as-expression #f)
        (print-pair-curly-braces  #t)
        (print-mpair-curly-braces #f))
      (define-namespace-anchor tmp)
      (set-user-initial-environment! (namespace-anchor->namespace tmp))
      . forms))))
