#' A list of 1:
#' \itemize{
#' \item{\code{method}}{ Correlation method to use. It must be one of 
#'                   "spearman", "pearson", "kendall".
#'                         The default value is "spearman".}
#' }
#'
#' @name correlation.options
#' @title options list for \code{model="correlation"}
#' 
#' @examples 
#' model.options <- list(method="pearson")
NULL


runModel.getDefaultPcorrOptions <- function() {

  ret <- list(method="spearman")
  ops.c <- c("method")

  list(default=ret, ops.character=ops.c)


} # END: runModel.getDefaultPcorrOptions

runModel.checkPcorrOpList <- function(op, name="model.options") {

  n       <- length(op)
  if (n && !is.list(op)) stop(paste("ERROR: ", name, " must be a list", sep=""))

  tmp   <- runModel.getDefaultPcorrOptions()
  def   <- tmp$default
  valid <- names(def)
  ops.c <- tmp$ops.character
  if (n) {
    checkOptionListNames(op, valid, name)
    checkOp_check.cor.method(op$method, name="method")
  }
  op <- default.list(op, valid, def)

  op

} # END: runModel.checkPcorrOpList


runModel.defRetObj.pcor <- function(dmatCols0) {

  vec               <- c("term", "corr", "p.value")
  coef.names        <- vec
  coef.stats        <- matrix(data=NA, nrow=1, ncol=length(coef.names))
  names(coef.stats) <- coef.names
  fit.names         <- "nobs"
  fit.stats         <- rep(NA, length(fit.names))
  names(fit.stats)  <- fit.names
  adj               <- runModel.getVarStr(dmatCols0[-1])

  list(converged=TRUE, coef.stats=coef.stats, fit.stats=fit.stats, 
       msg="", adj=adj, adj.rem="", wald.pvalue=NA)

} # END: runModel.defRetObj.pcor

runModel.tidyPcorr <- function(nsubs, fit, expVars, defObj, designMatCols, dmatCols0) {

  if (!length(fit)) {
    ret           <- defObj
    ret$msg       <- runModel.getUnknownErrorStr()
  } else if (isString(fit)) {
    ret           <- defObj
    ret$msg       <- fit
  } else {
    obj1    <- cbind(expVars, fit$corr, fit$pvalue)              
    msg     <- fit$msg

    # We only want the non-intercept, non-exposure adjustments
    nms0    <- names(dmatCols0)
    nms     <- designMatCols
    tmp     <- nms %in% nms0
    tmp[1]  <- FALSE
    rem     <- !(nms0 %in% nms)
    adj     <- runModel.getAdjVarStr(nms[tmp], dmatCols0)
    adj.rem <- runModel.getAdjVarStr(nms0[rem], dmatCols0)

    ret  <- list(converged=TRUE, coef.stats=obj1, fit.stats=nsubs, 
                 msg=msg, adj=adj, adj.rem=adj.rem, wald.pvalue=NA)  
  } 

  ret

} # END: runModel.tidyPcorr

runModel.calcCorr <- function(designMat, y, expVars, op) {

  mop    <- op[[getModelOpsName()]]
  method <- mop$method

  # Use pcor.test for categorical exposure variables or if there are
  #   adjusted covariates
  nc <- ncol(designMat)
  if ((length(expVars) > 1) || (nc > 2)) {
    ret <- runModel.pcor.test(designMat, y, expVars, method) 
  } else {
    nsubs <- length(y)
    if (nc > 1) {
      corr  <- cor(designMat[, 2], y, method=method) 
      df    <- nsubs - 2
      test  <- sqrt(df)*corr/sqrt(1 - corr*corr)
      pval  <- 2*stats::pt(abs(test), df=df, lower.tail=FALSE)
      msg   <- ""
    } else {
      corr  <- NA
      pval  <- NA 
      msg   <- "exposure has been removed"
    }
    ret <- list(corr=corr, pvalue=pval, nsubs=nsubs, msg=msg)
  }

  ret

} # END: runModel.calcCorr 

runModel.getPcorData <- function(designMat, y, expVarsInd) {

  # Order the columns as outcome, exposure, adjustment vars (including exposure dummies)

  # Intercept column will be used for the outcome y
  designMat[, 1] <- y
  
  # Order the remaining cols 
  cols <- 1:ncol(designMat)
  cols <- cols[-c(1, expVarsInd)]
  ord  <- c(1, expVarsInd, cols) 
  x    <- designMat[, ord, drop=FALSE]

  x

} # END: runModel.getPcorData

# For a categorical exposure
runModel.pcor.test <- function(designMat, y, expVars, method) {

  n        <- length(expVars)
  nsub     <- length(y)
  nvec     <- rep(nsub, n)
  pvec     <- rep(NA, n)
  rvec     <- pvec
  msg      <- rep("", n)
  startCol <- ncol(designMat) - n
  if (startCol < 1) {
    stop("INTERNAL CODING ERROR in runModel.pcor.test")
  }

  # Loop over each dummy var
  for (i in 1:n) {
    # Get the pcor input data matrix
    x   <- runModel.getPcorData(designMat, y, startCol+i)
    fit <- try(runModel.pcor(x, method), silent=TRUE)
    if ("try-error" %in% class(fit)) {
      msg[i]  <- runModel.getErrorMsg(fit)
    } else {
      rvec[i] <- fit$estimate[1, 2]
      pvec[i] <- fit$p.value[1, 2] 
    }
  }

  # Message must be length 1
  msg <- paste(unique(msg), collapse=";", sep="")

  list(corr=rvec, pvalue=pvec, nsubs=nvec, msg=msg)

} # END: runModel.pcor.test

runModel.pcor <- function(x, method) {

  n   <- dim(x)[1]
  gp  <- dim(x)[2] - 2
  cvx <- cov(x, method = method)
  if (det(cvx) < .Machine$double.eps) {
    warning("The inverse of variance-covariance matrix is calculated using Moore-Penrose generalized matrix invers due to its determinant of zero.")
    icvx <- ginv(cvx)
    gp   <- qr(cvx)$rank - 2
  } else {
    icvx <- solve(cvx)
  }
  pcor <- -cov2cor(icvx)
  diag(pcor) <- 1
  if (method == "kendall") {
    statistic <- pcor/sqrt(2 * (2 * (n - gp) + 5)/(9 * (n - gp) * (n - 1 - gp)))
    p.value <- 2 * pnorm(-abs(statistic))
  } else {
    statistic <- pcor * sqrt((n - 2 - gp)/(1 - pcor^2))
    p.value <- 2 * pt(-abs(statistic), (n - 2 - gp))
  }
  diag(statistic) <- 0
  diag(p.value)   <- 0

  list(estimate = pcor, p.value = p.value, statistic = statistic, 
        n = n, gp = gp, method = method)

} # END: runModel.pcor
