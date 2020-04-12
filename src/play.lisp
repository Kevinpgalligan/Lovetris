;;;; Play the game through a GUI.

(in-package lovetris)

(defconstant +width+ 10)
(defconstant +height+ 20)
(defconstant +bar+ 4)

(defconstant +border-pixels+ 10)
(defconstant +square-size+ 25)
(defconstant +pixels-for-score+ 50)

(defconstant +window-width+
  (+ (* 2 +border-pixels+)
     (* +width+ +square-size+)))
(defconstant +window-height+
  (+ (* 2 +border-pixels+)
     (* +height+ +square-size+)
     +pixels-for-score+))

(defparameter *blue* (gamekit:vec4 0 0 1 1))
(defparameter *red* (gamekit:vec4 1 0 0 1))
(defparameter *black* (gamekit:vec4 0 0 0 1))

(defvar *state*)
(defvar *piece*)

(gamekit:defgame hatetris () ()
  (:viewport-title "HATETRIS")
  (:viewport-width +window-width+)
  (:viewport-height +window-height+))

(defmethod gamekit:draw ((app hatetris))
  ;; Draw board.
  (loop for y from 0 below (well-height *state*) do
        (loop for x from 0 below (well-width *state*) do
              (draw-square x
                           y
                           (if (equalp +full+ (get-square *state* x y))
                               *blue*
                               *black*))))
  ;; Draw piece.
  (when *piece*
    (loop for (x y) in (piece-absolute-coords *piece*) do
          (draw-square x y *red*)))
  ;; Draw score.
  (gamekit:draw-text (format nil "Score: ~D" (state-score *state*))
                     (gamekit:vec2 (* 2 +border-pixels+)
                                   (+ +border-pixels+
                                      (/ +pixels-for-score+ 3))))
  ;; Draw the horizontal bar.
  (let ((bar-y (- +window-height+
                  +border-pixels+
                  (* +bar+ +square-size+)
                  1)))
    (gamekit:draw-rect (gamekit:vec2 +border-pixels+ bar-y)
                       (* +square-size+ +width+)
                       1
                       :fill-paint *red*)))

(defmethod gamekit:post-initialize ((app hatetris))
  ;; Yes, I'm aware that this is some horrible duplication, but
  ;; it wouldn't work when I put the button / function pairs
  ;; in a list and looped through them. For some reason, all of
  ;; the buttons were bound to the last function in the list.
  ;; Maybe the lambda in the loop was being overwritten? Anyway,
  ;; I'm too frustrated to spend any more time on it.
  (gamekit:bind-button :up
                       :pressed
                       (lambda ()
                         (update-piece #'piece-rotate)))
  (gamekit:bind-button :up
                       :repeating
                       (lambda ()
                         (update-piece #'piece-rotate)))
  (gamekit:bind-button :down
                       :pressed
                       (lambda ()
                         (update-piece #'piece-down)))
  (gamekit:bind-button :down
                       :repeating
                       (lambda ()
                         (update-piece #'piece-down)))
  (gamekit:bind-button :left
                       :pressed
                       (lambda ()
                         (update-piece #'piece-left)))
  (gamekit:bind-button :left
                       :repeating
                       (lambda ()
                         (update-piece #'piece-left)))
  (gamekit:bind-button :right
                       :pressed
                       (lambda ()
                         (update-piece #'piece-right)))
  (gamekit:bind-button :right
                       :repeating
                       (lambda ()
                         (update-piece #'piece-right))))

(defun update-piece (piece-move)
  (when *piece*
    (if (and (lockable-p *state* *piece*)
             (eq piece-move #'piece-down))
        (progn
          (setf *state* (merge-piece *state* *piece*))
          (setf *piece*
                (if (state-game-over *state*)
                    nil
                    (get-worst-piece-in-middle *state*))))
        (let ((new-piece (funcall piece-move *piece*)))
          (when (valid-position-p *state* new-piece)
            (setf *piece* new-piece))))))

(defun get-worst-piece-in-middle (state)
  (let ((next-piece (get-worst-piece state)))
    (setf (slot-value next-piece 'x)
          (+ 3 (piece-x next-piece)))
    next-piece))

(defun draw-square (x y colour)
  (gamekit:draw-rect (gamekit:vec2 (+ +border-pixels+
                                      (* x +square-size+))
                                   (- +window-height+
                                      1
                                      +border-pixels+
                                      (* (1+ y) +square-size+)))
                     +square-size+
                     +square-size+
                     :fill-paint colour))

(defun play-game ()
  (setf *state* (new-state :width +width+
                           :height +height+
                           :bar +bar+))
  (setf *piece* (get-worst-piece-in-middle *state*))
  (gamekit:start 'hatetris))