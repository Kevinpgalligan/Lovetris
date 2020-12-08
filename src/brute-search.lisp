(in-package lovetris)

(defclass brute-searcher ()
  ((search-depth
    :initarg :search-depth
    :initform 4
    :reader search-depth
    :documentation "How deep to search in the tree before picking a move.")
   (heuristic-eval
    :initarg :heuristic-eval
    :reader heuristic-eval
    :initform (error "Must supply heuristic evaluator.")
    :documentation "A function that estimates the 'goodness' of a state, should return a real number. Higher is better.")
   (search-tree
    :accessor search-tree)
   (num-threads
    :initarg :num-threads
    :initform 1
    :reader num-threads
    :documentation "How many threads to use for expanding the search tree.")))

(defmethod initialize-instance :after ((searcher brute-searcher)
                                       &key start-state)
  (when (not start-state)
    (error "No state to start from."))
  (setf (search-tree searcher) (make-instance 'node :state start-state)))

(defmethod advance ((searcher brute-searcher))
  (expand-nodes! (list (search-tree searcher))
                 (search-depth searcher)
                 (num-threads searcher)
                 (make-node-cache (search-tree searcher)))
  (propagate-heuristic-values! (search-tree searcher) (heuristic-eval searcher))
  (let* ((next-edge
           (alexandria:extremum (edges (search-tree searcher))
                                #'>
                                :key (lambda (edge)
                                       (heuristic-value (edge-child edge)))))
         (next-node (edge-child next-edge)))
    (let ((keep-cache (make-node-cache next-node)))
      (loop for node in (children (search-tree searcher)) do
            ;; This should help SBCL to perform garbage collection
            ;; properly. In large data structures, such as trees, SBCL's
            ;; garbage collector can leave entire branches of the tree
            ;; uncollected after we've discarded them, due to its conservatism.
            ;; Eventually, this will cause heap exhaustion. A rather nasty
            ;; trait of the implementation.
            (when (not (eq node next-node))
              (destroy-tree node keep-cache))))
    (setf (search-tree searcher) next-node)
    (values (state next-node) (edge-move-sequence next-edge))))


(defun expand-nodes! (nodes remaining-depth num-threads node-cache)
  (when (> remaining-depth 0)
    ;; Divide nodes as evenly as possible among threads for expansion, we
    ;; continue the single-threaded expansion of any remaining nodes.
    (let* ((split-index (* num-threads (floor (length nodes) num-threads)))
           (nodes-for-threads (subseq nodes 0 split-index))
           (leftover-nodes (subseq nodes split-index)))
      (when nodes-for-threads
        (expand-with-threads nodes-for-threads remaining-depth num-threads node-cache))
      (when leftover-nodes
        (loop for node in leftover-nodes do
              (when (not (expanded node))
                (generate-children! node node-cache)))
        (expand-nodes! (apply #'append
                              (mapcar #'children
                                      leftover-nodes))
                       (1- remaining-depth)
                       num-threads
                       node-cache)))))

(defun expand-with-threads (nodes remaining-depth num-threads node-cache)
  (let ((nodes-lock (bt:make-lock))
        (append-parent-lock (bt:make-lock)))
    (let ((threads
            (loop for i below num-threads collect
                  (bt:make-thread
                   (lambda ()
                     (loop (let ((node
                                   (bt:with-lock-held (nodes-lock)
                                     (pop nodes))))
                             (if (null node)
                                 (return)
                                 (add-leaves! node remaining-depth node-cache append-parent-lock)))))))))
      ;; Now wait for the threads to terminate.
      (loop for thread in threads do
            (bt:join-thread thread)))))

(defun generate-children! (node node-cache &optional append-parent-lock)
  (setf (edges node)
        (loop for placement in (possible-placements (state node))
              for child = (make-instance 'node
                                         :state (state placement)
                                         :parents (list node))
              for existing = (get-node node-cache child)
              ;; There is a race condition here. Threads A & B both
              ;; check the cache for node N, it's not there. Then they
              ;; both add it to their respective branches of the tree, and
              ;; to the node cache. But we're accepting that risk in exchange
              ;; for simplicity of implementation. It's not the end of the world
              ;; if we explore a branch of the search tree needlessly due to
              ;; a failure of the cache.
              do (if existing
                     (flet ((append-parent ()
                              (setf (parents existing) (cons node (parents existing)))))
                       (if append-parent-lock
                           ;; If it's super common for nodes to have multiple
                           ;; parents, then this might become a bottleneck.
                           (bt:with-lock-held (append-parent-lock) (append-parent))
                           (append-parent)))
                     (add node-cache child))
              collect (make-edge (move-sequence placement)
                                 (or existing child)))))

(defun add-leaves! (node remaining-depth node-cache &optional append-parent-lock)
  (when (< 0 remaining-depth)
    (when (not (expanded node))
      (generate-children! node node-cache append-parent-lock))
    (loop for child in (children node) do
          (add-leaves! child (1- remaining-depth) node-cache append-parent-lock))))

(defun propagate-heuristic-values! (node heuristic-eval)
  ;; Due to nodes having multiple parents, this
  ;; can result in us traversing the same branch
  ;; multiple times. If it's really inefficient
  ;; and crappy, there are ways of avoiding it.
  ;; E.g. clear heuristic values from tree when
  ;; we're finished & check if a node already has
  ;; a value before descending.
  (if (not (children node))
      (progn
        (when (not (heuristic-value node))
          (setf (heuristic-value node) (funcall heuristic-eval (state node))))
        (heuristic-value node))
      (setf (heuristic-value node)
            (apply #'max
                   (mapcar (lambda (node)
                             (propagate-heuristic-values! node heuristic-eval))
                           (children node))))))

