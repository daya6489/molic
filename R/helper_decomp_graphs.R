## ---------------------------------------------------------
##                EXPORTED HELPERS
## ---------------------------------------------------------
#' Probability mass function for a decomposable graphical model
#'
#' @param A A character matrix of data
#' @param adj Adjacency list or gengraph object of a decomposable graph. See \code{fit_graph}.
#' @param logp Logical; if TRUE, probabilities p are given as log(p).
#' @return A function - the probability mass function corresponding
#' to the decomposable graph \code{adj} using \code{A} to estimate
#' the probabilities.
#' @details It should be noted, that \code{pmf} is a closure function; i.e. its return
#' value is a function. Once \code{pmf} is called, one can query probabilities from the
#' returned function. If the probability of an observation is zero, the function will return
#' \code{NA} if \code{logp} is set to \code{TRUE} and zero otherwise.
#' @examples
#' \dontrun{
#' library(dplyr)
#' 
#' # All handwritten digits that have true class equal to a "1".
#' d <- digits %>% # subset(digits, class == "1")
#'   filter(class == "1") %>%
#'   select(-class)
#'
#' # A handwritten digit with true class equal to "1"
#' z1 <- digits %>%
#'   filter(class == "1") %>%
#'   select(-class) %>%
#'   slice(5) %>%
#'   unlist()
#' 
#' # A handwritten digit with true class equal to "7"
#' z7 <- digits %>%
#'   filter(class == "7") %>%
#'   select(-class) %>%
#'   slice(1) %>%
#'   unlist()
#' 
#' # Fit an interaction graph
#' g <- fit_graph(d, trace = FALSE)
#' plot(g)
#'
#' g <- g %>%
#'   adj_lst()
#'
#' # Probability in class "1"
#' p1 <- pmf(d %>% as.matrix(), g)
#' p1(z7)
#' p1(z1)
#'
#' # Probability on component 23 in class "1"
#' cmp   <- components(g)
#' cmp23 <- cmp[[23]]
#' print(cmp23)
#' p1_23 <- pmf(d %>% select(cmp23) %>% as.matrix(), g[cmp23])
#' p1_23(z7)
#' p1_23(z1)
#'
#' }
#' @export
pmf <- function(A, adj, logp = FALSE) {
  if (!is_decomposable(adj)) stop("The graph corresponding to adj is not decomposable!")
  if (!setequal(colnames(A), names(adj))) stop("Variables in A and the names of adj do not conform!")
  RIP   <- rip(adj)
  cms   <- RIP$C
  sms   <- RIP$S
  ncms <- a_marginals(A, cms)
  nsms <- a_marginals(A, sms)
  .pmf <- function(y) {
    ny <- vapply(seq_along(ncms), FUN.VALUE = 1, FUN =  function(i) {
      nci    <- ncms[[i]]
      nsi    <- nsms[[i]]
      yci    <- y[match(attr(nci, "vars"), names(y))]
      ycinam <- paste0(yci, collapse = "")
      nciy   <- nci[ycinam] # NA if y is not seen on ci
      if (i == 1L) return(log(nciy))
      nsiy <- nsi[1]
      if (length(nsi) > 1) {
        ysi    <- y[match(attr(nsi, "vars"), names(y))]
        nsinam <- paste0(ysi, collapse = "")
        nsiy   <- nsi[nsinam] # NA if not seen on si
      } 
      return(log(nciy) - log(nsiy))
    })
    if (anyNA(ny)) return(ifelse(logp, NA, 0L)) # The observation was not seen on some marginals
    logprob <- sum(ny) - log(nrow(A))
    return(ifelse(logp, logprob , exp(logprob)))
  }
}

#' Subgraph
#'
#' Construct a subgraph with a given set of nodes removed
#'
#' @param x Character vector of nodes
#' @param g Adjacency list (named) or a neighbor matrix with dimnames given as the nodes
#' @examples
#' adj1 <- list(a = c("b", "d"), b = c("a", "c", "d"), c = c("b", "d"), d = c("a", "c", "b"))
#' # Toy data so we can plot the graph
#' d <- data.frame(a = "", b = "", c ="", d = "")
#' g <- gengraph(d, type = "gen", adj = adj1)
#' plot(g)
#' subgraph(c("c", "b"), adj1)
#' subgraph(c("b", "d"), as_adj_mat(adj1))
#' @export
subgraph <- function(x, g) {
  # x: vector of nodes to delete
  if (inherits(g, "matrix")) {
    keepers <- setdiff(dimnames(g)[[1]], x)
    g <- g[keepers, keepers]
    return(g)
  }
  else if (inherits(g, "list")) {
    l <- list(a = "a", b = "b")
    g <- g[-match(x, names(g))]
    g <- lapply(g, function(e) {
      rm_idx <- as.vector(stats::na.omit(match(x, e)))
      if (neq_empt_int(rm_idx)) return(e[-rm_idx])
      return(e)
    })
    return(g)
  }
  else {
    stop("g must either be a matrix of an adjacency list.", call. = FALSE)
  }
}

#' A test for decomposability in undirected graphs
#'
#' This function returns \code{TRUE} if the graph is decomposable and \code{FALSE} otherwise
#'
#' @param adj Adjacency list of an undirected graph
#' @examples
#' # 4-cycle:
#' adj1 <- list(a = c("b", "d"), b = c("a", "c"), c = c("b", "d"), d = c("a", "c"))
#' is_decomposable(adj1) # FALSE
#' # Two triangles:
#' adj2 <- list(a = c("b", "d"), b = c("a", "c", "d"), c = c("b", "d"), d = c("a", "c", "b"))
#' is_decomposable(adj2) # TRUE
#' @export
is_decomposable <- function(adj) {
  m <- try(mcs(adj), silent = TRUE)
  if( inherits(m, "list") ) return(TRUE)
    else return(FALSE)
}

#' Finds the components of a graph
#'
#' @param adj Adjacency list
#' @return A list with the elements being the components of the graph
#' @export
components <- function(adj) {
  nodes <- names(adj)
  comps <- list()
  comps[[1]] <- dfs(adj, nodes[1])
  while (TRUE) {
    new_comp  <- setdiff(nodes, unlist(comps))
    if (identical(new_comp, character(0))) return(comps)
    comps <- c(comps, list(dfs(adj[new_comp], new_comp[1])))
  }
  return(comps)
}


#' Print
#'
#' A print method for \code{gengraph} objects
#'
#' @param x A \code{gengraph} object
#' @param ... Not used (for S3 compatability)
#' @export
print.gengraph <- function(x, ...) {
  nv  <- ncol(x$G_A)
  ne  <- sum(x$G_A)/2
  cls <- paste0("<", paste0(class(x), collapse = ", "), ">")
  cat(" A Decomposable Graph With",
    "\n -------------------------",
    "\n  Nodes:", nv,
    "\n  Edges:", ne, "/", nv*(nv-1)/2,
    "\n  Cliques:", length(x$CG),
    paste0("\n  ", cls),
    "\n -------------------------\n"
  )
}


#' Make a complete graph
#'
#' A helper function to make an adjacency list corresponding to a complete graph
#'
#' @param nodes A character vector containing the nodes to be used in the graph
#' @examples
#' d  <- digits[, 5:8]
#' cg <- make_complete_graph(colnames(d))
#' @export
make_complete_graph <- function(nodes) {
  structure(lapply(seq_along(nodes), function(k) {
    nodes[-which(nodes == nodes[k])]
  }), names = nodes)
}

#' Make a null graph
#'
#' A helper function to make an adjacency list corresponding to a null graph (no edges)
#'
#' @param nodes A character vector containing the nodes to be used in the graph
#' @examples
#' d  <- digits[, 5:8]
#' ng <- make_null_graph(colnames(d))
#' @export
make_null_graph <- function(nodes) {
  structure(lapply(seq_along(nodes), function(x) {
    character(0)
  }), names = nodes)
}
