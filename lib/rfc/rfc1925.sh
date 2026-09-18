#!/usr/bin/env bs
# shellcheck shell=bash
# lib/rfc/rfc1925.sh — RFC 1925: The Twelve Networking Truths
# lib/rfc/rfc1925.sh — RFC 1925: Двенадцать истин сетей

# @depends core/lang

# Source Guard
bs::guard "LIB_RFC_1925" || return 0

# Dependencies
bs::source_relative "../../core/lang.sh"

# @description The Twelve Networking Truths (RFC 1925, April Fools' RFC).
# @description Двенадцать истин сетей (RFC 1925, первоапрельский RFC).
# @stdout the truths / истины
# @example
#   rfc1925::truths
rfc1925::truths() {
  cat <<'EOF'
RFC 1925 — The Twelve Networking Truths
=======================================

1.  It Has To Work. / Оно должно работать.
2.  No matter how hard you push and no matter what the priority, you
    can't increase the speed of light.
    Сколько ни толкай и какой приоритет ни ставь — скорость света
    не увеличить.
3.  With sufficient thrust, pigs fly just fine. However, this is not
    necessarily a good idea. It is hard to be sure where they are going
    to land, and it could be dangerous sitting under them as they fly
    overhead.
    При достаточной тяге и свиньи летают. Но приземлятся они
    непонятно где, и сидеть под ними опасно.
4.  Some things in life can never be fully appreciated, except by
    approaching them from a different direction.
    Некоторые вещи можно оценить, лишь подойдя к ним с другой стороны.
5.  It is always possible to agglutinate multiple separate problems into
    a single complex interdependent solution. In most cases this is a
    bad idea.
    Всегда можно склеить несколько отдельных проблем в одно сложное
    решение. В большинстве случаев это плохая идея.
6.  It is easier to move a problem around (for example, by moving the
    problem to a different part of the overall network architecture)
    than it is to eliminate it.
    Проблему проще перенести (например, в другое место архитектуры),
    чем устранить.
7.  It is always something. / Всегда что-нибудь да случится.
8.  It is more complicated than you think. / Всё сложнее, чем кажется.
9.  For every apparent bug, there is one more. / На каждый явный баг
    найдётся ещё один.
10. One size never fits all. / Один размер не подходит всем.
11. Every old idea will be proposed again with a different name and a
    different presentation, regardless of whether it works.
    Каждая старая идея будет предложена снова — под новым именем и в
    новой подаче, независимо от того, работает ли она.
12. In protocol design, perfection has been reached not when there is
    nothing left to add, but when there is nothing left to take away.
    В дизайне протоколов совершенство достигается не тогда, когда
    нечего добавить, а когда нечего убрать.
EOF
}