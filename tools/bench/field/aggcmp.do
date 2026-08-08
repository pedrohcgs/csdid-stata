clear all
foreach m in B1 D1 B2 D2 B3 crit {
    use aggbase_`m'_old, clear
    mkmat _all, matrix(OLD)
    use aggbase_`m'_new, clear
    mkmat _all, matrix(NEW)
    local d = mreldif(OLD, NEW)
    display "AGGCMP `m' mreldif=" %12.3e `d'
}
