## ---------------------------------------------------------
##                NON-EXPORTED HELPERS
## ---------------------------------------------------------
.sim_internal <- function(A,
                  cms,
                  sms,
                  nsim         = 10000,
                  type         = "deviance",
                  ncores       = 1) {
  y <- replicate(nsim, vector("character", ncol(A)), simplify = FALSE)
  M <- nrow(A)
  Hx_M    <- Hx_(M)
  Delta   <- colnames(A)
  C1_vars <- attr(cms[[1]], "vars")
  C1_idx  <- match(C1_vars, Delta)
  p_nC1   <- cms[[1]] / M
  yC1_sim <- sample(names(p_nC1), nsim, replace = TRUE, prob = p_nC1)
  if (!(length(cms) - 1L)) {
    # The complete graph
    yC1_sim <- lapply(strsplit(yC1_sim, ""), function(z) {names(z) = C1_vars; z})
    if (type == "deviance") yC1_sim <- 2 * (.map_dbl(yC1_sim, TY, cms, sms) - Hx_M) # D(Y) 
    return(yC1_sim)
  }
  doParallel::registerDoParallel(ncores)
  combine_ <- switch(type, "deviance"  = 'c', "raw" = "rbind")
  y <- foreach::`%dopar%`(foreach::foreach(z = 1:nsim, .combine = combine_, .inorder = FALSE), {
    y_sim_z <- y[[z]]
    y_sim_z[C1_idx] <- .split_chars(yC1_sim[1])
    for (k in 2:length(cms)) {
      nCk     <- cms[[k]]
      Ck_vars <- attr(nCk, "vars")     # Clique names
      Ck_idx  <- match(Ck_vars, Delta) # Where is Ck in Delta
      nSk     <- sms[[k]]              # For Sk = Ø we have that nSk = M
      Sk_vars <- attr(nSk, "vars")     # Separator names
      if (is.null(Sk_vars)) {          # For empty separators
        p_nCk_minus_nSk <- nCk / nSk   # nSk = M !
        y_sim_z[Ck_idx] <- .split_chars(sample(names(p_nCk_minus_nSk), 1L, prob = p_nCk_minus_nSk))
      } else {
        Sk_idx              <- match(Sk_vars, Delta)
        Sk_idx_in_Ck        <- match(Sk_vars, Ck_vars)
        Ck_idx_minus_Sk_idx <- Ck_idx[-Sk_idx_in_Ck]
        ySk                 <- y_sim_z[Sk_idx]
        nSk_ySk             <- na_ya(nSk, paste0(ySk, collapse = ""))
        nCk_given_Sk        <- n_b(nCk, structure(Sk_idx_in_Ck, names = ySk) )
        p_nCk_given_Sk_ySk  <- nCk_given_Sk / nSk_ySk # Cant be Inf, since ySk MUST be present since we simulated it
        y_sim_z[Ck_idx_minus_Sk_idx] <- .split_chars(sample(names( p_nCk_given_Sk_ySk), 1L, prob =  p_nCk_given_Sk_ySk))
      }
    }
    out <- structure(y_sim_z, names = Delta)
    if (type == "deviance") {
      out <- TY(out, cms, sms)   # D(y) = 2*(T(y) - H(M))
    }
    out
  })
  doParallel::stopImplicitCluster()
  if (type == "deviance") y <- 2 * (y - Hx_M) # D(y)
  return(y)
}

extract_model_simulations <- function(models) {
  if (!inherits(models, "multiple_models")) stop("`models` needs to be an object returned from `fit_multiple_models`")
  sims <- lapply(seq_along(models), function(m) {
    data.frame(Deviance = models[[m]]$sims,
      response = names(models)[m],
      stringsAsFactors = FALSE)
  }) 
  do.call(rbind, sims)
}

make_observation_info <- function(models) {
  zdevs <- .map_dbl(models, function(m) m$dev)
  zpvs  <- .map_dbl(models, function(m) m$pv)
  data.frame(devs = zdevs, pvals = zpvs, response = names(models))
}

## ---------------------------------------------------------
##                   EXPORTED HELPERS
## ---------------------------------------------------------

#' Simulate observations from a decomposable graphical model
#'
#' This function simulates observations from a DGM
#' 
#' @param A Character Matrix (data)
#' @param adj Adjacency list of a decomposable graph
#' @param nsim Number of simulations
#' @param ncores Number of cores to use in parallelization
#' @return This function returns a matrix of dimension \code{nsim x ncol(A)} where each row correspond to a simulated observation from a DGM represented by \code{adj}.
#' @examples
#'
#' \dontrun{
#' 
#' library(dplyr)
#' 
#' d <- digits %>%
#'   filter(class == "1") %>%
#'   select(-class)
#' G <- adj_lst(fit_graph(d))
#' dgm_sim(as.matrix(d), G, nsim = 10)
#'
#' }
#' @export
dgm_sim <- function(A, adj, nsim = 1000, ncores = 1) {
  stopifnot( is.matrix(A) )
  RIP   <- rip(adj) # the rip (or actually mcs) will check for decomposability here
  cms   <- a_marginals(A, RIP$C)
  sms   <- a_marginals(A, RIP$S)
  out   <- .sim_internal(A, cms, sms, nsim = nsim, type = "raw", ncores = ncores)
  row.names(out) <- NULL
  return(out)
}

#' Print outlier model
#'
#' A print method for \code{outlier_model} objects
#'
#' @param x A \code{outlier_model} object
#' @param ... Not used (for S3 compatability)
#' @export
print.outlier_model <- function(x, ...) {
  cls <- paste0("<", paste0(class(x), collapse = ", "), ">")
  cat(
    "\n --------------------------------",
    "\n  Simulations:",         length(x$sims),
    "\n  Variables:",           ncol(x$A),
    "\n  Observations:",        nrow(x$A),
    "\n  Estimated mean:",      round(x$mu, 2),
    "\n  Estimated variance:",  round(x$sigma, 2),
    paste0("\n  ", cls),
    "\n --------------------------------\n"
  )
}

#' Print outlier
#'
#' A print method for \code{outlier} objects
#'
#' @param x A \code{outlier} object
#' @param ... Not used (for S3 compatability)
#' @export
print.outlier <- function(x, ...) {
  cls <- paste0("<", paste0(class(x), collapse = ", "), ">")
  cat(
    "\n --------------------------------",
    "\n  Simulations:",         length(x$sims),
    "\n  Variables:",           ncol(x$A),
    "\n  Observations:",        nrow(x$A),
    "\n  Estimated mean:",      round(x$mu, 2),
    "\n  Estimated variance:",  round(x$sigma, 2),
    "\n    ---------------------------  ",
    "\n  Critical value:", x$cv,
    "\n  Deviance:", x$dev,
    "\n  P-value:", x$pval,
    "\n  Alpha:", x$alpha,
    paste0("\n  ", cls),
    "\n --------------------------------\n"
  )
}

#' Calculate deviance
#'
#' This function calculates the affine value \code{T(y)} of \code{-2 log} likelihood-ratio statistic which is also called the deviance
#'
#' @param x A \code{outlier_model} object
#' @param y An observation (name character vector)
#' @param ... Not used (for S3 compatibility)
#' @export
deviance <- function(x, y, ...) {
  UseMethod("deviance")
}

#' @rdname deviance
#' @export
deviance.outlier_model <- function(x, y,...) {
  2 * (TY(y, x$cms, x$sms) - Hx_(nrow(x$A))) # D(y)
}

#' Plot Deviance
#'
#' A plot method to show the approximated deviance distribution
#' @param x An object returned from \code{fit_outlier}
#' @param sig_col Color of the significance level area (default is red)
#' @param ... Extra arguments; see details.
#' @details The dotted line represents the observed deviance of the observation under the hypothesis
#' and the colored (red is default) area under the graph represents the significance level.
#' Thus, if the dotted line is to the left of the colored area, the hypothesis that the observation
#' is an outlier cannot be rejected. Notice however, if there is no dotted line, this simply means,
#' that the observed deviance is larger than all values and it would disturb the plot if included.
#'
#' No extra arguments \code{...} are implement at the moment.
#' @examples
#' # TBA
#' 1L
#' @export
plot.outlier <- function(x, sig_col = "#FF0000A0", ...) {
  # args <- list(...)
  # Old base approach:
  # graphics::hist(x$sims, breaks = 30, xlab = "Deviance",  freq = FALSE, main = " ")
  # dat <- data.frame(Deviance = x$sims, y = "")
  dat <- with(stats::density(x$sims), data.frame(x, y))
  dat$.region <- x$cv
  dat$.dev    <- x$dev
  p <- ggplot2::ggplot(data = dat, mapping = ggplot2::aes(x = x, y = y)) +
    ggplot2::geom_line() +
    ggplot2::geom_ribbon(data = subset(dat, x >= .region),
      ggplot2::aes(ymax = y),
      ymin   = 0,
      fill   = sig_col,
      colour = sig_col,
      alpha  = 0.7) + 
    ggplot2::geom_ribbon(data = subset(dat, x <= .region),
      ggplot2::aes(ymax = y),
      ymin   = 0,
      fill   = "#A0A0A0A0",
      colour = "#A0A0A0A0",
      alpha  = 0.7)
  p <- p + ggplot2::theme_bw() + ggplot2::ylab("") + ggplot2::xlab("Deviance")
  if (dat$.dev[1] < max(x$sims)) {
    p <- p + ggplot2::geom_vline(ggplot2::aes(xintercept = .dev), linetype = "dotted")
  }
  return(p)
}

#' Plot Deviance of Multiple Models
#'
#' A plot method to show the approximated deviance distribution of multiple models
#' @param x A \code{multiple_models} object returned from a called to \code{fit_multiple_models}
#' @param sig_col Color of the significance level area (default is red)
#' @param ... Extra arguments. See details.
#' @details The dotted line represents the observed deviance of the observation under the hypothesis
#' and the colored (red is default) area under the graph represents the significance level.
#' Thus, if the dotted line is to the left of the colored area, the hypothesis that the observation
#' is an outlier cannot be rejected. Notice however, if there is no dotted line, this simply means,
#' that the observed deviance is larger than all values and it would disturb the plot if included.
#'
#' No extra arguments \code{...} are implement at the moment.
#' @examples
#' # TBA
#' 1L
#' @export
plot.multiple_models <- function(x, sig_col = "#FF0000A0", ...) {
  z_dev_pval <- make_observation_info(x)
  dat        <- extract_model_simulations(x)
  p <- ggplot2::ggplot(dat, ggplot2::aes(x = Deviance, y = response))
  p <- p + ggridges::stat_density_ridges(ggplot2::aes(fill=factor(..quantile..)),
    geom      = "density_ridges_gradient",
    calc_ecdf = TRUE,
    quantiles = c(1 - x[[1]]$alpha, 1)
  )
  p <- p + ggplot2::scale_y_discrete(limits = names(x))
  p <- p + ggplot2::scale_fill_manual(
    name  = "Significance level",
    values = c("#A0A0A0A0", sig_col, sig_col),
    labels = c("", "(ms[[1]]$alpha, 1]", "")
  )
  
  for (i in 1:nrow(z_dev_pval)) {
    max_dev_i <- max(dat$Deviance)
    dev       <- z_dev_pval[i, "devs"]
    if (dev < max_dev_i) { # Dont plot the dotted line if it is larger than all deviances
      linet  <- "dotted"
      df_seg <- data.frame(x1 = dev, x2 = dev, y1 = i , y2 = i + 1)
      p <- p + ggplot2::geom_segment(ggplot2::aes(x = x1,
        y    = y1,
        xend = x2,
        yend = y2
      ),
      linetype = linet,
      size     = 1,
      color    = "black",
      data     = df_seg
      )
    }
  }
  p <- p + ggplot2::theme_bw() +
    ggplot2::ylab("") +
    ggplot2::xlab("Deviance") +
    ggplot2::theme(legend.position = "none")
  return(p)
}


#' Plot of pmf
#'
#' A plot method to show the pmf of the approximated pmf of \code{T(Y)}
#'
#' @param x A \code{outlier_model} object
#' @param ... Not used (for S3 compatibility)
#' @export
plot.outlier_model <- function(x, ...) {
  graphics::hist(x$sims, breaks = 30, xlab = "Deviance",  freq = FALSE, main = " ")
}


#' Empirical distribution function
#'
#' The empirical cdf of \code{T(Y)}
#'
#' @param x A \code{outlier_model} object
#' @param ... Not used (for S3 compatibility)
#' @export
cdf <- function(x, ...) UseMethod("cdf")

#' @rdname cdf
#' @export
cdf.outlier_model <- function(x, ...) return(x$cdf)

#' P-value
#'
#' Calculate the p-value for obtaining \code{ty_new} under \code{H_0}
#'
#' @param x A \code{outlier_model} object
#' @param dz The deviance of the observation \code{z}.
#' @param ... Not used (for S3 compatibility)
#' @details The value \code{dz} can be obtained used the \code{deviance} function.
#' @seealso \code{\link{deviance}}
#' @export
pval <- function(x, dz, ...) UseMethod("pval")

#' @rdname pval
#' @export
pval.outlier_model <- function(x, dz, ...) return(1 - x$cdf(dz))


#' Critical value
#'
#' Calculate the critical value for test statistic under \code{H_0}
#'
#' @param m A \code{outlier_model} object
#' @param alpha Significance level (between \code{0} and \code{1})
#' @details The value \code{dz} can be obtained used the \code{deviance} function.
#' @seealso \code{\link{deviance}}
#' @export
critval <- function(m, alpha = 0.05) UseMethod("critval")

#' @rdname critval
#' @export
critval.outlier_model <- function(m, alpha = 0.05) {
  stats::uniroot(function(x) pval(m, x) - alpha,
    interval = range(m$sims),
    extendInt = "yes",
    tol = 0.0001)$root
}

#' Mean
#'
#' Estimated mean of deviance statistic \code{T(Y)}
#'
#' @param x A \code{outlier_model} object
#' @param ... Not used (for S3 compatibility)
#' @export
mean.outlier_model <- function(x, ...) return(x$mu)

#' Variance
#'
#' Estimated variance of the deviance statistic \code{T(Y)}
#'
#' @param x A \code{outlier_model} object
#' @param ... Not used (for S3 compatibility)
#' @export
variance <- function(x) UseMethod("variance")

#' @rdname variance
#' @export
variance.outlier_model <- function(x, ...) return(x$sigma)
