# Rscript --no-save --no-restore --verbose test/deb.R > test/log/deb.R.log 2>&1

library(did)
library(haven)
library(foreign)
library(here)

source(file.path(here(), "test/common.R"))

tmp    <- file.path(here(), "tmp")
deb    <- read_dta(file.path(here(), "../reply_to_DNWZ/data/Deb_etal_20251006_Stata.dta"))
deb$id <- 1:nrow(deb)

methods <- c("drimp", "dripw", "reg", "stdipw")
aggtyps <- c("simple", "group", "calendar", "dynamic")
kwargs  <- list(data        = deb,
                yname       = "y",
                tname       = "t",
                gname       = "c",
                idname      = "id",
                clustervars = "g",
                panel       = FALSE,
                cband       = FALSE,
                bstrap      = FALSE)

results <- list()
for ( m in methods ) {
    print(m); results[[m]] <- do.call(att_gt, c(kwargs, list(est_method=m)))
}

aggres <- list()
for ( m in methods ) {
    res <- results[[m]]
    for ( typ in aggtyps ) {
        print(c(m, typ)); aggres[[paste(m, typ, sep="_")]] <- aggte(res, type=typ)
    }
}

dir.create(tmp, showWarnings=F)
for ( m in methods ) {
    res <- results[[m]]
    out <- cbind(res$att,  sqrt(diag(as.matrix(res$V_analytical)) /res$n))
    .savemat(file.path(tmp, paste("tmpout", m, sep="_")), out)
    for ( typ in aggtyps ) {
        agg <- aggres[[paste(m, typ, sep="_")]]
        all <- cbind(agg$overall.att, agg$overall.se)
        row <- cbind(agg$att.egt,     agg$se.egt)
        .savemat(file.path(tmp, paste("tmpout", m, typ, sep="_")), rbind(all, row))
    }
}
