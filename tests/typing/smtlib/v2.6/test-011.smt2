(set-logic QF_UF)
(declare-fun a () Bool)
(declare-fun b () Bool)
(declare-fun c () Bool)
(declare-fun d () Bool)
(assert (and (= a b) (= b c) (= c d) (or (not (= a c)) (not (= a a)))))
(check-sat)
